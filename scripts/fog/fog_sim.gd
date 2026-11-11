extends RefCounted

## GPU stable-fluids solver on the main RenderingDevice. Every RD call here runs on the render thread
## (through RenderingServer.call_on_render_thread); the main thread only reads `ready` and the RIDs.

const FT := preload("res://scripts/fog/fog_tuning.gd")
const SHADER_FILE := preload("res://shaders/fog/fog_sim.glsl")

enum Mode { ADVECT, CURL, VORTICITY, DIVERGENCE, JACOBI, GRADIENT, COORDS, COPY, INIT, LIFT }

var ready: bool = false
var last_gpu_ms: float = 0.0
var res := Vector2i(256, 256)
var cell: float = 0.1
var state_rid := RID()
var coords_rid := RID()
var obstacle_rid := RID()
var lift_rid := RID()

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _splat_buffer := RID()
var _obstacle := RID()
var _base := RID()
var _reach := RID()
var _owned: Array[RID] = []
var _sets: Dictionary = {}
var _iterations: int = 30
var _hz: float = 60.0


func _init(resolution: Vector2i, cell_size: float, hz: float, iterations: int) -> void:
	res = resolution
	cell = cell_size
	_hz = hz
	_iterations = iterations + (iterations % 2)


## Render thread.
func setup(obstacle_data: PackedByteArray, base_data: PackedByteArray, reach_data: PackedByteArray) -> void:
	_rd = RenderingServer.get_rendering_device()
	var spirv: RDShaderSPIRV = SHADER_FILE.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("[Fog] compute compile error: %s" % spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv, "FogSim")
	_pipeline = _rd.compute_pipeline_create(_shader)

	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)

	var s0: RID = _field()
	var s1: RID = _field()
	var s2: RID = _field()
	var curl: RID = _field()
	var div: RID = _field()
	var p0: RID = _field()
	var p1: RID = _field()
	var c0: RID = _field()
	var c1: RID = _field()
	var l0: RID = _field()
	var l1: RID = _field()
	_obstacle = _mask(obstacle_data)
	_base = _mask(base_data)
	_reach = _mask(reach_data)
	_splat_buffer = _rd.storage_buffer_create(FT.MAX_SPLATS_PER_STEP * 32)
	_owned.append(_splat_buffer)

	_sets = {
		"advect": _make_set(s0, s0, s1),
		"curl": _make_set(s1, s1, curl),
		"vort": _make_set(s1, curl, s2),
		"div": _make_set(s2, s2, div),
		"jac0": _make_set(p0, div, p1),
		"jac1": _make_set(p1, div, p0),
		"grad": _make_set(s2, p0, s0),
		"coords": _make_set(c0, s0, c1),
		"copy": _make_set(c1, c1, c0),
		"lift": _make_set(l0, s0, l1),
		"copy_lift": _make_set(l1, l1, l0),
		"init": _make_set(s1, s1, s0),
	}
	state_rid = s0
	obstacle_rid = _obstacle
	coords_rid = c0
	lift_rid = l0

	var cl: int = _rd.compute_list_begin()
	_dispatch(cl, "init", Mode.INIT, _params(0.0, 0.0, 0, 0.0))
	_rd.compute_list_end()
	ready = true


## Render thread. `steps` holds one Vector4(time, reset_flags, splat_count, night) per sim step.
func step(steps: Array[Vector4], splat_data: PackedFloat32Array) -> void:
	if not ready:
		return
	_read_timing()
	if splat_data.size() > 0:
		_rd.buffer_update(_splat_buffer, 0, splat_data.size() * 4, splat_data.to_byte_array())
	var dt: float = 1.0 / _hz
	_rd.capture_timestamp("FogSimBegin")
	var cl: int = _rd.compute_list_begin()
	for s: Vector4 in steps:
		var flags: int = int(s.y)
		var pa: PackedFloat32Array = _params(dt, s.x, int(s.z), s.w)
		pa[7] = FT.NIGHT_FLOOR_VARIATION
		_dispatch(cl, "advect", Mode.ADVECT, pa)
		var p: PackedFloat32Array = _params(dt, s.x, 0, s.w)
		_dispatch(cl, "curl", Mode.CURL, p)
		_dispatch(cl, "vort", Mode.VORTICITY, p)
		_dispatch(cl, "div", Mode.DIVERGENCE, p)
		for i: int in _iterations:
			_dispatch(cl, "jac0" if i % 2 == 0 else "jac1", Mode.JACOBI, p)
		_dispatch(cl, "grad", Mode.GRADIENT, p)
		p[7] = float(flags)
		_dispatch(cl, "coords", Mode.COORDS, p)
		_dispatch(cl, "copy", Mode.COPY, p)
		_dispatch(cl, "lift", Mode.LIFT, _lift_params(dt, int(s.z)))
		_dispatch(cl, "copy_lift", Mode.COPY, p)
	_rd.compute_list_end()
	_rd.capture_timestamp("FogSimEnd")


## Render thread. Keeps the last measured GPU time of one sim batch.
func read_timing() -> void:
	if ready:
		_read_timing()


func _read_timing() -> void:
	var begin: int = -1
	var end: int = -1
	for i: int in _rd.get_captured_timestamps_count():
		var n: String = _rd.get_captured_timestamp_name(i)
		if n == "FogSimBegin":
			begin = _rd.get_captured_timestamp_gpu_time(i)
		elif n == "FogSimEnd":
			end = _rd.get_captured_timestamp_gpu_time(i)
	if begin >= 0 and end >= begin:
		last_gpu_ms = float(end - begin) / 1000000.0 # timestamps are in nanoseconds


## Render thread.
func upload_obstacles(data: PackedByteArray) -> void:
	if ready:
		_rd.texture_update(_obstacle, 0, data)


## Render thread.
func upload_base(data: PackedByteArray, reach_data: PackedByteArray) -> void:
	if ready:
		_rd.texture_update(_base, 0, data)
		_rd.texture_update(_reach, 0, reach_data)


## Render thread.
func free_all() -> void:
	if _rd == null:
		return
	ready = false
	for rid: RID in _owned:
		if rid.is_valid():
			_rd.free_rid(rid)
	_owned.clear()
	if _sampler.is_valid():
		_rd.free_rid(_sampler)
	if _shader.is_valid():
		_rd.free_rid(_shader) # also frees the pipeline and the uniform sets


func _dispatch(cl: int, set_name: String, mode: int, params: PackedFloat32Array) -> void:
	params[2] = float(mode)
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _sets[set_name], 0)
	var bytes: PackedByteArray = params.to_byte_array()
	_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
	_rd.compute_list_dispatch(cl, ceili(res.x / 8.0), ceili(res.y / 8.0), 1)
	_rd.compute_list_add_barrier(cl)


func _params(dt: float, time: float, splat_count: int, night: float) -> PackedFloat32Array:
	var drift: float = lerpf(1.0, FT.NIGHT_DRIFT_SCALE, night)
	var p := PackedFloat32Array()
	p.resize(32)
	p[0] = res.x
	p[1] = res.y
	p[3] = splat_count
	p[4] = dt
	p[5] = cell
	p[6] = time
	p[8] = FT.WIND.x * drift
	p[9] = FT.WIND.y * drift
	p[10] = exp(-FT.AMBIENT_COUPLING * dt)
	p[11] = 1.0 - exp(-lerpf(FT.REGEN_RATE, FT.NIGHT_REGEN_RATE, night) * dt)
	p[12] = FT.VORTICITY
	p[13] = exp(-FT.SOURCE_DECAY * dt)
	p[14] = FT.DRIFT_STRENGTH * drift
	p[15] = FT.DRIFT_FREQUENCY * cell
	p[16] = FT.IMPULSE_COUPLING
	p[17] = FT.IMPULSE_CARVE
	p[18] = FT.IMPULSE_PUSH
	p[19] = FT.DRIFT_SPEED * drift
	p[20] = FT.BURST_SOURCE
	p[21] = FT.BURST_RADIAL
	p[22] = FT.BURST_SWIRL
	p[23] = FT.BURST_CARVE
	p[24] = FT.BURST_RING_GAIN
	p[25] = FT.BURST_LIFT
	p[26] = FT.NIGHT_VILLAGE_FLOOR if night > 0.001 else 0.0
	p[27] = lerpf(FT.BASE_DENSITY_MAX, FT.NIGHT_BASE_MAX, night)
	p[28] = lerpf(FT.PATCH_AMOUNT, FT.NIGHT_PATCH_AMOUNT, night)
	p[29] = FT.PATCH_FREQUENCY * cell
	p[30] = FT.PATCH_SPEED * lerpf(1.0, FT.NIGHT_DRIFT_SCALE, night)
	# Front leads the light transition so the fog has time to flow in during dusk.
	p[31] = 1.0 - sqrt(night) * (1.0 + FT.NIGHT_FRONT_OVERSHOOT)
	return p


func _lift_params(dt: float, splat_count: int) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(32)
	p[0] = res.x
	p[1] = res.y
	p[3] = splat_count
	p[4] = dt
	p[5] = cell
	p[8] = FT.LIFT_GRAVITY
	p[9] = exp(-FT.LIFT_DRAG * dt)
	p[10] = exp(-FT.LIFT_DECAY * dt)
	p[11] = FT.LIFT_MAX
	p[12] = FT.LIFT_RUN_VELOCITY
	p[13] = FT.AGITATE_RUN_SPEED
	p[14] = FT.LIFT_BURST_VELOCITY
	p[15] = FT.LIFT_BURST_CORE
	return p


func _field() -> RID:
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = res.x
	tf.height = res.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var rid: RID = _rd.texture_create(tf, RDTextureView.new(), [])
	_rd.texture_clear(rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_owned.append(rid)
	return rid


func _mask(data: PackedByteArray) -> RID:
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = res.x
	tf.height = res.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var rid: RID = _rd.texture_create(tf, RDTextureView.new(), [data])
	_owned.append(rid)
	return rid


func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array[RID]) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id: RID in ids:
		u.add_id(id)
	return u


func _make_set(a: RID, b: RID, dst: RID) -> RID:
	var st := RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	var uniforms: Array[RDUniform] = [
		_uniform(st, 0, [_sampler, a]),
		_uniform(st, 1, [_sampler, b]),
		_uniform(st, 2, [_sampler, _obstacle]),
		_uniform(st, 3, [_sampler, _base]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 4, [dst]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, [_splat_buffer]),
		_uniform(st, 6, [_sampler, _reach]),
	]
	return _rd.uniform_set_create(uniforms, _shader, 0)
