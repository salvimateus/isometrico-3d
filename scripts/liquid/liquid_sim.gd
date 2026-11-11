extends RefCounted

## GPU shallow-water solver on the main RenderingDevice. Every RD call runs on the render thread
## (RenderingServer.call_on_render_thread); the main thread only reads `ready`, the RIDs and `latest`.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const SHADER_FILE := preload("res://shaders/liquid/liquid_sim.glsl")

enum Mode { FLUX, DEPTH, FX, COPY, REDUCE, CLEAR }

var ready: bool = false
var res := Vector2i(256, 256)
var cell: float = 0.1
var origin := Vector2.ZERO
var state_rid := RID()
var aux_rid := RID()
var height_rid := RID()
var readback_size := Vector2i.ZERO
var last_gpu_ms: float = 0.0

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _linear := RID()
var _nearest := RID()
var _height := RID()
var _solid := RID()
var _drain := RID()
var _state := RID()
var _flux := RID()
var _aux_a := RID()
var _aux_b := RID()
var _readback := RID()
var _emitters := RID()
var _set_main := RID()
var _set_copy := RID()
var _owned: Array[RID] = []
var _mutex := Mutex.new()
var _latest := PackedByteArray()
var _latest_serial: int = 0
var _pending_reads: int = 0


func _init(resolution: Vector2i, cell_size: float, area_origin: Vector2) -> void:
	res = resolution
	cell = cell_size
	origin = area_origin
	readback_size = Vector2i(res.x / LT.READBACK_DIV + res.x / LT.READBACK_DIV / 2 * 2, res.y / LT.READBACK_DIV)


## Main thread: newest readback bytes (RGBA32F, readback_size) and a serial that grows per arrival.
func latest() -> Array:
	_mutex.lock()
	var out: Array = [_latest, _latest_serial]
	_mutex.unlock()
	return out


## Render thread.
func setup(height: PackedByteArray, solid: PackedByteArray, drain: PackedByteArray) -> void:
	_rd = RenderingServer.get_rendering_device()
	var spirv: RDShaderSPIRV = SHADER_FILE.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("[Liquid] compute compile error: %s" % spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv, "LiquidSim")
	_pipeline = _rd.compute_pipeline_create(_shader)
	_linear = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR)
	_nearest = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST)

	_height = _texture(res, RenderingDevice.DATA_FORMAT_R32_SFLOAT, false, height)
	_solid = _texture(res, RenderingDevice.DATA_FORMAT_R8_UNORM, false, solid)
	_drain = _texture(res, RenderingDevice.DATA_FORMAT_R8_UNORM, false, drain)
	_state = _texture(res, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true)
	_flux = _texture(res, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true)
	_aux_a = _texture(res, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, true)
	_aux_b = _texture(res, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, true)
	_readback = _texture(readback_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true)
	_emitters = _rd.storage_buffer_create((LT.MAX_SOURCES + LT.MAX_DISTURBANCES) * 32)
	_owned.append(_emitters)

	_set_main = _make_set(_aux_a, _aux_b)
	_set_copy = _make_set(_aux_b, _aux_a)
	state_rid = _state
	aux_rid = _aux_a
	height_rid = _height
	ready = true


## Render thread. Re-uploads the terrain and clears the water.
func upload_terrain(height: PackedByteArray, solid: PackedByteArray, drain: PackedByteArray) -> void:
	if not ready:
		return
	_rd.texture_update(_height, 0, height)
	_rd.texture_update(_solid, 0, solid)
	_rd.texture_update(_drain, 0, drain)
	var cl: int = _rd.compute_list_begin()
	_dispatch(cl, _set_main, Mode.CLEAR, _params(0.0, 0, 0), res)
	_rd.compute_list_end()


## Render thread. `substeps` sim steps of `dt`, then one fx pass over `fx_dt` (0 skips it) and a readback.
## `emitters` holds `source_count` source pairs followed by `disturb_count` disturbance pairs (2 x vec4 each).
func step(substeps: int, dt: float, fx_dt: float, emitters: PackedFloat32Array, source_count: int, disturb_count: int, read_back: bool) -> void:
	if not ready:
		return
	_read_timing()
	if emitters.size() > 0:
		_rd.buffer_update(_emitters, 0, emitters.size() * 4, emitters.to_byte_array())
	_rd.capture_timestamp("LiquidSimBegin")
	var cl: int = _rd.compute_list_begin()
	for i: int in substeps:
		var p: PackedFloat32Array = _params(dt, source_count, disturb_count)
		_dispatch(cl, _set_main, Mode.FLUX, p, res)
		_dispatch(cl, _set_main, Mode.DEPTH, p, res)
	if fx_dt > 0.0:
		var pf: PackedFloat32Array = _params(fx_dt, source_count, 0)
		_dispatch(cl, _set_main, Mode.FX, pf, res)
		_dispatch(cl, _set_copy, Mode.COPY, pf, res)
	if read_back:
		_dispatch(cl, _set_main, Mode.REDUCE, _params(dt, 0, 0), readback_size)
	_rd.compute_list_end()
	_rd.capture_timestamp("LiquidSimEnd")
	if read_back and _pending_reads < 3:
		_pending_reads += 1
		_rd.texture_get_data_async(_readback, 0, _on_readback)


## Render thread.
func read_timing() -> void:
	if ready:
		_read_timing()


## Render thread.
func free_all() -> void:
	if _rd == null:
		return
	ready = false
	for rid: RID in _owned:
		if rid.is_valid():
			_rd.free_rid(rid)
	_owned.clear()
	for s: RID in [_linear, _nearest]:
		if s.is_valid():
			_rd.free_rid(s)
	if _shader.is_valid():
		_rd.free_rid(_shader) # also frees the pipeline and the uniform sets


func _on_readback(data: PackedByteArray) -> void:
	_mutex.lock()
	_latest = data
	_latest_serial += 1
	_pending_reads = maxi(0, _pending_reads - 1)
	_mutex.unlock()


func _read_timing() -> void:
	var begin: int = -1
	var end: int = -1
	for i: int in _rd.get_captured_timestamps_count():
		var n: String = _rd.get_captured_timestamp_name(i)
		if n == "LiquidSimBegin":
			begin = _rd.get_captured_timestamp_gpu_time(i)
		elif n == "LiquidSimEnd":
			end = _rd.get_captured_timestamp_gpu_time(i)
	if begin >= 0 and end >= begin:
		last_gpu_ms = float(end - begin) / 1000000.0


func _dispatch(cl: int, uniform_set: RID, mode: int, params: PackedFloat32Array, size: Vector2i) -> void:
	params[2] = float(mode)
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	var bytes: PackedByteArray = params.to_byte_array()
	_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
	_rd.compute_list_dispatch(cl, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_add_barrier(cl)


func _params(dt: float, source_count: int, disturb_count: int) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(32)
	p[0] = res.x
	p[1] = res.y
	p[3] = cell
	p[4] = dt
	p[5] = LT.GRAVITY
	p[6] = LT.WALL_DRAG
	p[7] = source_count
	p[8] = disturb_count
	p[9] = LT.LINEAR_DRAG
	p[10] = LT.BED_DRAG
	p[11] = LT.MAX_SPEED
	p[12] = LT.ABSORB_FILM
	p[13] = LT.ABSORB_FLAT
	p[14] = LT.ABSORB_BASIN
	p[15] = LT.ABSORB_FILM_DEPTH
	p[16] = LT.WET_RISE_RATE
	p[17] = 1.0 / LT.DRY_TIME
	p[18] = LT.FOAM_DECAY
	p[19] = LT.WET_DEPTH
	p[20] = LT.FOAM_SPEED_RANGE.x
	p[21] = LT.FOAM_SPEED_RANGE.y
	p[22] = LT.FOAM_FROM_SPEED
	p[23] = LT.FOAM_FROM_FRONT
	p[24] = LT.FOAM_FROM_CONVERGE
	p[25] = LT.FOAM_FROM_WALL
	p[26] = LT.FOAM_FROM_DRAIN
	p[27] = LT.DRAIN_DROP
	p[28] = origin.x
	p[29] = origin.y
	p[30] = LT.READBACK_DIV
	p[31] = LT.DISTURB_GAIN
	return p


func _sampler(filter: RenderingDevice.SamplerFilter) -> RID:
	var ss := RDSamplerState.new()
	ss.min_filter = filter
	ss.mag_filter = filter
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	return _rd.sampler_create(ss)


func _texture(size: Vector2i, format: RenderingDevice.DataFormat, storage: bool, data: PackedByteArray = PackedByteArray()) -> RID:
	var tf := RDTextureFormat.new()
	tf.format = format
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = size.x
	tf.height = size.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if storage:
		tf.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var initial: Array[PackedByteArray] = []
	if not data.is_empty():
		initial.append(data)
	var rid: RID = _rd.texture_create(tf, RDTextureView.new(), initial)
	if data.is_empty():
		_rd.texture_clear(rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_owned.append(rid)
	return rid


func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array[RID]) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id: RID in ids:
		u.add_id(id)
	return u


func _make_set(aux_src: RID, aux_dst: RID) -> RID:
	var st := RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	var img := RenderingDevice.UNIFORM_TYPE_IMAGE
	var uniforms: Array[RDUniform] = [
		_uniform(st, 0, [_linear, _height]),
		_uniform(st, 1, [_nearest, _solid]),
		_uniform(st, 2, [_nearest, _drain]),
		_uniform(img, 3, [_state]),
		_uniform(img, 4, [_flux]),
		_uniform(st, 5, [_linear, aux_src]),
		_uniform(img, 6, [aux_dst]),
		_uniform(img, 7, [_readback]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, [_emitters]),
	]
	return _rd.uniform_set_create(uniforms, _shader, 0)
