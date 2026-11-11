extends Node3D

## Shallow-water field over the island heightfield: GPU sim, water sheet render, wet-ground map,
## waterfalls at drain edges and the water-tower sequence. Group &"liquid_field".
## Keep this node at the identity transform: `area` and every position are world XZ.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const P := preload("res://scripts/liquid/liquid_profile.gd")
const Sim := preload("res://scripts/liquid/liquid_sim.gd")
const Fx := preload("res://scripts/liquid/liquid_fx.gd")
const Tower := preload("res://scripts/liquid/liquid_tower.gd")
const Feedback := preload("res://scripts/liquid/liquid_feedback.gd")
const Curtain := preload("res://scripts/liquid/liquid_curtain.gd")
const SURFACE_SHADER := preload("res://shaders/liquid/liquid_surface.gdshader")

const WETNESS_PARAM: StringName = &"liquid_wetness_map"
const AREA_PARAM: StringName = &"liquid_area"

enum Phase { AWAKE, DRYING, ASLEEP }

var area := Rect2(-16.0, -16.0, 32.0, 32.0)
var res := Vector2i(256, 256)
var cell: float = 0.125
var fx: Fx
var phase: int = Phase.ASLEEP
var last_sim_gpu_ms: float:
	get:
		return _sim.last_gpu_ms if _sim != null else 0.0
var total_volume: float = 0.0
var drained_rate: float = 0.0

var _sim: Sim
var _tower: Tower
var _curtain: Curtain
var _surface: MeshInstance3D
var _material: ShaderMaterial
var _state_tex := Texture2DRD.new()
var _aux_tex := Texture2DRD.new()
var _height_tex := Texture2DRD.new()
var _bound: bool = false
var _publish: bool = false
var _night: float = 0.0

var _heights := PackedFloat32Array()
var _height_bytes := PackedByteArray()
var _solid_bytes := PackedByteArray()
var _drain_bytes := PackedByteArray()
var _lips: Dictionary = {} # event block index -> Array[Vector4(x, z, lip y, base y)] + outward dirs
var _lip_dirs: Dictionary = {}

var _sources: Array[Dictionary] = []
var _disturbs: Array[Vector4] = []
var _disturb_vel: Array[Vector2] = []
var _accum: float = 0.0
var _fx_accum: float = 0.0
var _dry_time: float = 0.0
var _quiet_time: float = 0.0
var _calm: bool = false

var _grid := PackedFloat32Array()
var _grid_serial: int = -1
var _rres := Vector2i.ZERO
var _eres := Vector2i.ZERO
var _rb_width: int = 0
var _scan_timer: float = 0.0
var _falls: Array[Dictionary] = []
var _max_speed: float = 0.0
var _flow_energy: float = 0.0
var _flow_center := Vector3.ZERO
var _fall_center := Vector3.ZERO
var _flow_loop: Node
var _fall_loop: Node
var _rng := RandomNumberGenerator.new()


func configure(world_area: Rect2) -> void:
	area = world_area
	var longest: float = maxf(area.size.x, area.size.y)
	var step: int = LT.READBACK_DIV * 2
	var nx: int = maxi(step * 2, int(round(float(P.sim_resolution()) * area.size.x / longest / step)) * step)
	var nz: int = maxi(step * 2, int(round(float(P.sim_resolution()) * area.size.y / longest / step)) * step)
	res = Vector2i(nx, nz)
	cell = area.size.x / float(nx)
	# Keep square cells: stretch the area depth to match the rounded resolution.
	area.size.y = cell * float(nz)
	_rres = res / LT.READBACK_DIV
	_eres = _rres / 2
	_rb_width = _rres.x + _eres.x * 2
	var n: int = res.x * res.y
	_heights.resize(n)
	_height_bytes = _heights.to_byte_array()
	_solid_bytes.resize(n)
	_drain_bytes.resize(n)


func _ready() -> void:
	add_to_group(&"liquid_field")
	_rng.randomize()
	if _heights.is_empty():
		configure(area)
	_sim = Sim.new(res, cell, area.position)
	RenderingServer.call_on_render_thread(_sim.setup.bind(_height_bytes, _solid_bytes, _drain_bytes))
	fx = Fx.new()
	fx.name = "LiquidFx"
	fx.area = area
	add_child(fx)
	_build_surface()
	_curtain = Curtain.new()
	add_child(_curtain)
	_curtain.setup(_material.get_shader_parameter(&"foam_tex"), cell)
	# Declared in project.godot by the game; a test scene that registers them at runtime sets the Engine meta.
	_publish = (ProjectSettings.has_setting("shader_globals/" + WETNESS_PARAM) and ProjectSettings.has_setting("shader_globals/" + AREA_PARAM)) or Engine.has_meta(&"liquid_globals_registered")
	if _publish:
		RenderingServer.global_shader_parameter_set(AREA_PARAM, Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	set_night(_night)


func _exit_tree() -> void:
	Feedback.stop_loop(_flow_loop, 0.2)
	Feedback.stop_loop(_fall_loop, 0.2)
	if _sim != null:
		if _publish:
			RenderingServer.global_shader_parameter_set(WETNESS_PARAM, null)
		_surface.material_override = null
		_state_tex.texture_rd_rid = RID()
		_aux_tex.texture_rd_rid = RID()
		_height_tex.texture_rd_rid = RID()
		RenderingServer.call_on_render_thread(_sim.free_all)


# --- Public API ---------------------------------------------------------------------------------

## Images span `area` (x -> world X, y -> world Z, row 0 at area.position.y), any resolution.
## height: FORMAT_RF world height. solid: white = no water. drain: white = water leaves (waterfalls).
func set_terrain(height: Image, solid: Image, drain: Image) -> void:
	var h: Image = height.duplicate() as Image
	if h.get_format() != Image.FORMAT_RF:
		h.convert(Image.FORMAT_RF)
	if h.get_size() != res:
		h.resize(res.x, res.y, Image.INTERPOLATE_BILINEAR)
	_height_bytes = h.get_data()
	_heights = _height_bytes.to_float32_array()
	_solid_bytes = _mask_bytes(solid)
	_drain_bytes = _mask_bytes(drain)
	_find_lips()
	if _curtain != null:
		_curtain.clear_terrain_cache()
	var gpu_drain: PackedByteArray = _encode_basins(_drain_bytes)
	if _sim != null:
		RenderingServer.call_on_render_thread(_sim.upload_terrain.bind(_height_bytes, _solid_bytes, gpu_drain))


func attach_tower(tower: Node3D, button: Node3D) -> void:
	if _tower != null:
		_tower.queue_free()
	_tower = Tower.new()
	_tower.name = "WaterTowerSequence"
	add_child(_tower)
	_tower.setup(self, tower, button)
	_curtain.prepare.call_deferred(_lips, _lip_dirs)


func trigger() -> void:
	if _tower != null:
		_tower.trigger()


func can_trigger() -> bool:
	return _tower != null and _tower.can_trigger()


func depth_at(pos: Vector3) -> float:
	return _grid_sample(pos, 0)


func velocity_at(pos: Vector3) -> Vector3:
	return Vector3(_grid_sample(pos, 1), 0.0, _grid_sample(pos, 2))


## Wake of a body wading through the water; call every physics frame while it moves.
func add_disturbance(pos: Vector3, velocity: Vector3, radius: float) -> void:
	if phase != Phase.AWAKE or _disturbs.size() >= LT.MAX_DISTURBANCES:
		return
	if depth_at(pos) < 0.003:
		return
	_disturbs.append(Vector4(pos.x, pos.z, maxf(radius, cell * 2.0), 0.0))
	_disturb_vel.append(Vector2(velocity.x, velocity.z))


## Adds `volume` world units^3 at `pos` over the next sim step, with horizontal momentum `velocity`.
func add_water(pos: Vector3, volume: float, velocity: Vector3 = Vector3.ZERO, radius: float = 0.6, push: float = 0.0) -> void:
	if volume <= 0.0:
		return
	for s: Dictionary in _sources:
		if (s["pos"] as Vector2).distance_to(Vector2(pos.x, pos.z)) < radius * 0.5:
			s["volume"] = float(s["volume"]) + volume
			s["vel"] = velocity
			return
	if _sources.size() >= LT.MAX_SOURCES:
		_sources[0]["volume"] = float(_sources[0]["volume"]) + volume
		return
	_sources.append({"pos": Vector2(pos.x, pos.z), "volume": volume, "vel": velocity, "radius": radius, "push": push})
	_wake()


func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter(&"scatter_color", LT.SCATTER_COLOR.lerp(LT.NIGHT_SCATTER_COLOR, _night))
		_material.set_shader_parameter(&"foam_color", LT.FOAM_COLOR.lerp(LT.NIGHT_FOAM_COLOR, _night))
		_material.set_shader_parameter(&"day", 1.0 - _night)
		_material.set_shader_parameter(&"night", _night)
		_material.set_shader_parameter(&"scatter_strength", lerpf(0.8, 0.4, _night))
		_material.set_shader_parameter(&"sky_top", LT.SKY_TOP.lerp(LT.NIGHT_SKY_TOP, _night))
		_material.set_shader_parameter(&"sky_horizon", LT.SKY_HORIZON.lerp(LT.NIGHT_SKY_HORIZON, _night))
	if fx != null:
		fx.set_night(_night)
	if _curtain != null:
		_curtain.set_night(_night)
	if _tower != null:
		_tower.set_night(_night)


func ground_height(x: float, z: float) -> float:
	var i: int = clampi(int((x - area.position.x) / cell), 0, res.x - 1)
	var j: int = clampi(int((z - area.position.y) / cell), 0, res.y - 1)
	return _heights[j * res.x + i]


func is_solid(x: float, z: float) -> bool:
	var i: int = int((x - area.position.x) / cell)
	var j: int = int((z - area.position.y) / cell)
	if i < 0 or j < 0 or i >= res.x or j >= res.y:
		return true
	return _solid_bytes[j * res.x + i] > 127


## Deepest readback block (debug/telemetry).
func max_depth() -> float:
	var m: float = 0.0
	if _grid.is_empty():
		return m
	for z: int in _rres.y:
		for x: int in _rres.x:
			m = maxf(m, _grid[(z * _rb_width + x) * 4 + 3])
	return m


func get_wetness_texture() -> Texture2D:
	return _aux_tex


func get_foam_texture() -> Texture2D:
	return _material.get_shader_parameter(&"foam_tex") as Texture2D


# --- Frame loop ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _sim == null:
		return
	if not _bound and _sim.ready:
		_state_tex.texture_rd_rid = _sim.state_rid
		_aux_tex.texture_rd_rid = _sim.aux_rid
		_height_tex.texture_rd_rid = _sim.height_rid
		_bound = true
		if _publish:
			RenderingServer.global_shader_parameter_set(WETNESS_PARAM, _aux_tex)
	if not _bound:
		return
	_consume_readback()
	_scan_timer -= delta
	if _scan_timer <= 0.0 and phase == Phase.AWAKE:
		_scan_timer = LT.EVENT_SCAN_INTERVAL
		_scan_events()
	_update_phase(delta)
	_emit_falls(delta)
	_update_loops()
	match phase:
		Phase.AWAKE:
			_step_awake(delta)
		Phase.DRYING:
			_step_drying(delta)
		_:
			RenderingServer.call_on_render_thread(_sim.read_timing)
	_surface.visible = phase == Phase.AWAKE


func _step_awake(delta: float) -> void:
	var hz: float = P.calm_sim_hz() if _calm and _sources.is_empty() else P.sim_hz()
	var dt: float = 1.0 / hz
	_accum = minf(_accum + delta, dt * P.max_steps())
	var n: int = 0
	while _accum >= dt:
		_accum -= dt
		n += 1
	if n == 0:
		return
	var span: float = dt * float(n)
	var data := PackedFloat32Array()
	data.resize((LT.MAX_SOURCES + LT.MAX_DISTURBANCES) * 8)
	var sc: int = mini(_sources.size(), LT.MAX_SOURCES)
	for i: int in sc:
		var s: Dictionary = _sources[i]
		var p: Vector2 = s["pos"]
		var v: Vector3 = s["vel"]
		data[i * 8 + 0] = p.x
		data[i * 8 + 1] = p.y
		data[i * 8 + 2] = s["radius"]
		data[i * 8 + 3] = float(s["volume"]) / span
		data[i * 8 + 4] = v.x
		data[i * 8 + 5] = v.z
		data[i * 8 + 6] = s["push"]
	var dc: int = mini(_disturbs.size(), LT.MAX_DISTURBANCES)
	for i: int in dc:
		var o: int = (sc + i) * 8
		var d: Vector4 = _disturbs[i]
		data[o + 0] = d.x
		data[o + 1] = d.y
		data[o + 2] = d.z
		data[o + 4] = _disturb_vel[i].x
		data[o + 5] = _disturb_vel[i].y
	_sources.clear()
	_disturbs.clear()
	_disturb_vel.clear()
	RenderingServer.call_on_render_thread(_sim.step.bind(n, dt, span, data, sc, dc, true))
	_material.set_shader_parameter(&"cell", cell)


func _step_drying(delta: float) -> void:
	_fx_accum += delta
	var dt: float = 1.0 / LT.DRYING_FX_HZ
	if _fx_accum < dt:
		RenderingServer.call_on_render_thread(_sim.read_timing)
		return
	var span: float = _fx_accum
	_fx_accum = 0.0
	RenderingServer.call_on_render_thread(_sim.step.bind(0, dt, span, PackedFloat32Array(), 0, 0, false))


func _wake() -> void:
	if phase != Phase.AWAKE:
		phase = Phase.AWAKE
		_accum = 0.0
		_quiet_time = 0.0


func _update_phase(delta: float) -> void:
	match phase:
		Phase.AWAKE:
			var wet: bool = total_volume > LT.SLEEP_DEPTH * cell * cell * 4.0 or not _sources.is_empty()
			if wet or _grid_serial < 0:
				_quiet_time = 0.0
			else:
				_quiet_time += delta
			if _quiet_time > 1.2:
				phase = Phase.DRYING
				_dry_time = 0.0
				_fx_accum = 0.0
				_grid.fill(0.0)
				total_volume = 0.0
				_flow_energy = 0.0
				drained_rate = 0.0
				_falls.clear()
		Phase.DRYING:
			_dry_time += delta
			if _dry_time > LT.DRY_TIME + 2.0:
				phase = Phase.ASLEEP


# --- Readback -----------------------------------------------------------------------------------

func _consume_readback() -> void:
	var got: Array = _sim.latest()
	var serial: int = got[1]
	if serial == _grid_serial:
		return
	var bytes: PackedByteArray = got[0]
	if bytes.size() < _rb_width * _rres.y * 16:
		return
	_grid_serial = serial
	if phase == Phase.AWAKE:
		_grid = bytes.to_float32_array()


func _grid_sample(pos: Vector3, channel: int) -> float:
	if _grid.is_empty() or phase != Phase.AWAKE:
		return 0.0
	var size: float = cell * LT.READBACK_DIV
	var gx: float = (pos.x - area.position.x) / size - 0.5
	var gz: float = (pos.z - area.position.y) / size - 0.5
	var x0: int = clampi(floori(gx), 0, _rres.x - 1)
	var z0: int = clampi(floori(gz), 0, _rres.y - 1)
	var x1: int = mini(x0 + 1, _rres.x - 1)
	var z1: int = mini(z0 + 1, _rres.y - 1)
	var fx_: float = clampf(gx - float(x0), 0.0, 1.0)
	var fz: float = clampf(gz - float(z0), 0.0, 1.0)
	var a: float = _grid[(z0 * _rb_width + x0) * 4 + channel]
	var b: float = _grid[(z0 * _rb_width + x1) * 4 + channel]
	var c: float = _grid[(z1 * _rb_width + x0) * 4 + channel]
	var d: float = _grid[(z1 * _rb_width + x1) * 4 + channel]
	return lerpf(lerpf(a, b, fx_), lerpf(c, d, fx_), fz)


func _scan_events() -> void:
	if _grid.is_empty():
		return
	var area_cell: float = cell * cell
	var block: float = cell * LT.READBACK_DIV * 2.0
	var vol: float = 0.0
	var energy: float = 0.0
	var drained: float = 0.0
	var max_v: float = 0.0
	var flow_c := Vector3.ZERO
	var fall_c := Vector3.ZERO
	_falls.clear()
	for ey: int in _eres.y:
		for ex: int in _eres.x:
			var o0: int = (ey * _rb_width + _rres.x + ex * 2) * 4
			var o1: int = o0 + 4
			var sum_h: float = _grid[o1]
			if sum_h <= 0.0 and _grid[o0 + 1] <= 0.0:
				continue
			var wall: float = _grid[o0]
			var drain_rate: float = _grid[o0 + 1]
			var surf_y: float = _grid[o0 + 2]
			var e: float = _grid[o1 + 1] * area_cell
			vol += sum_h * area_cell
			energy += e
			drained += drain_rate
			max_v = maxf(max_v, _grid[o1 + 3])
			var cx: float = area.position.x + (ex + 0.5) * block
			var cz: float = area.position.y + (ey + 0.5) * block
			var center := Vector3(cx, surf_y if surf_y > -999.0 else ground_height(cx, cz), cz)
			flow_c += center * e
			if wall > LT.WALL_SPLASH_THRESHOLD and surf_y > -999.0 and _rng.randf() < 0.55:
				var jitter := Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)) * block
				var p: Vector3 = center + jitter
				var v: Vector3 = velocity_at(p)
				fx.splash(p + Vector3.UP * 0.05, int(3 + wall * 5.0), 0.8 + wall * 0.6, 1.2 + wall * 1.6, 0.3, -v * 0.3)
				if wall > LT.WALL_SPLASH_THRESHOLD * 2.5 and _rng.randf() < 0.3:
					fx.mist(p, 1, 0.3, 0.5, 0.8)
			var key: int = ey * _eres.x + ex
			if drain_rate > LT.FALL_EMIT_THRESHOLD and _lips.has(key):
				_falls.append({"key": key, "rate": drain_rate})
				fall_c += center * drain_rate
	total_volume = vol
	_flow_energy = energy
	drained_rate = drained
	_max_speed = max_v
	_calm = max_v < LT.CALM_SPEED
	if energy > 0.0:
		_flow_center = flow_c / energy
	if drained > 0.0:
		_fall_center = fall_c / drained


func _emit_falls(delta: float) -> void:
	var targets: Dictionary = {}
	for f: Dictionary in _falls:
		var key: int = f["key"]
		var lips: Array = _lips[key]
		var dirs: Array = _lip_dirs[key]
		var weights := PackedFloat32Array()
		var wsum: float = 0.0
		for i: int in lips.size():
			var lp: Vector4 = lips[i]
			var o: Vector2 = dirs[i]
			var wd: float = maxf(depth_at(Vector3(lp.x - o.x * cell, 0.0, lp.y - o.y * cell)), 0.0)
			weights.append(wd)
			wsum += wd
		for i: int in lips.size():
			var share: float = weights[i] / wsum if wsum > 1e-5 else 1.0 / float(lips.size())
			var flow: float = clampf(float(f["rate"]) * share / LT.CURTAIN_FULL_RATE, 0.0, 1.0)
			if flow > 0.03:
				targets[key * 4096 + i] = [flow, lips[i], dirs[i], key]
	_curtain.update(targets, delta, fx)
	for f: Dictionary in _falls:
		var lips: Array = _lips[f["key"]]
		var dirs: Array = _lip_dirs[f["key"]]
		var rate: float = f["rate"]
		var count: int = int(floor(rate * P.fall_particles_per_unit() * delta + _rng.randf()))
		for k: int in mini(count, 12):
			var idx: int = _rng.randi_range(0, lips.size() - 1)
			var lip: Vector4 = lips[idx]
			var out: Vector2 = dirs[idx]
			var along := Vector2(-out.y, out.x) * _rng.randf_range(-0.5, 0.5) * cell * 2.0
			var p := Vector3(lip.x + along.x + out.x * LT.FALL_LIP_OFFSET, lip.z + 0.05, lip.y + along.y + out.y * LT.FALL_LIP_OFFSET)
			var v: Vector3 = velocity_at(p)
			var speed: float = maxf(Vector2(v.x, v.z).dot(out), 0.4) + 0.3
			var vel := Vector3(out.x * speed, -0.2, out.y * speed)
			fx.fall(p, vel, lip.w, rate)


func _update_loops() -> void:
	var tree: SceneTree = get_tree()
	var flow: float = clampf(sqrt(_flow_energy / LT.FLOW_LOOP_FULL), 0.0, 1.0)
	if flow > 0.04:
		if _flow_loop == null:
			_flow_loop = Feedback.play_loop(tree, &"water_flow", LT.FLOW_LOOP_DB_RANGE.x, _flow_center)
		Feedback.set_loop_volume(_flow_loop, lerpf(LT.FLOW_LOOP_DB_RANGE.x, LT.FLOW_LOOP_DB_RANGE.y, flow))
		Feedback.set_loop_position(_flow_loop, _flow_center)
	elif _flow_loop != null:
		Feedback.stop_loop(_flow_loop, 1.5)
		_flow_loop = null
	var fall: float = clampf(sqrt(drained_rate / LT.FALL_LOOP_FULL), 0.0, 1.0)
	if fall > 0.04:
		if _fall_loop == null:
			_fall_loop = Feedback.play_loop(tree, &"waterfall", LT.FALL_LOOP_DB_RANGE.x, _fall_center)
		Feedback.set_loop_volume(_fall_loop, lerpf(LT.FALL_LOOP_DB_RANGE.x, LT.FALL_LOOP_DB_RANGE.y, fall))
		Feedback.set_loop_position(_fall_loop, _fall_center)
	elif _fall_loop != null:
		Feedback.stop_loop(_fall_loop, 2.0)
		_fall_loop = null


# --- Setup helpers ------------------------------------------------------------------------------

func _mask_bytes(mask: Image) -> PackedByteArray:
	var m: Image = mask.duplicate() as Image
	if m.is_compressed():
		m.decompress()
	m.convert(Image.FORMAT_L8)
	if m.get_size() != res:
		m.resize(res.x, res.y, Image.INTERPOLATE_BILINEAR)
	var data: PackedByteArray = m.get_data()
	for i: int in data.size():
		data[i] = 255 if data[i] > 127 else 0
	return data


## GPU drain map: 255 = drain, otherwise the basin factor (0..204) of cells lower than their surroundings.
func _encode_basins(drain_bytes: PackedByteArray) -> PackedByteArray:
	var r: int = maxi(1, int(round(LT.BASIN_RADIUS / cell)))
	var blur: PackedFloat32Array = _box_blur(_heights, res.x, res.y, r)
	var out := PackedByteArray()
	out.resize(drain_bytes.size())
	for i: int in out.size():
		if drain_bytes[i] > 0:
			out[i] = 255
			continue
		var depth: float = blur[i] - _heights[i]
		var f: float = clampf((depth - LT.BASIN_DEPTH.x) / (LT.BASIN_DEPTH.y - LT.BASIN_DEPTH.x), 0.0, 1.0)
		out[i] = int(f * f * (3.0 - 2.0 * f) * 204.0)
	return out


static func _box_blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(src.size())
	var dst := PackedFloat32Array()
	dst.resize(src.size())
	for y: int in h:
		var acc: float = 0.0
		var row: int = y * w
		for x: int in range(-r, r + 1):
			acc += src[row + clampi(x, 0, w - 1)]
		for x: int in w:
			tmp[row + x] = acc / float(2 * r + 1)
			acc += src[row + mini(x + r + 1, w - 1)] - src[row + maxi(x - r, 0)]
	for x: int in w:
		var acc: float = 0.0
		for y: int in range(-r, r + 1):
			acc += tmp[clampi(y, 0, h - 1) * w + x]
		for y: int in h:
			dst[y * w + x] = acc / float(2 * r + 1)
			acc += tmp[mini(y + r + 1, h - 1) * w + x] - tmp[maxi(y - r, 0) * w + x]
	return dst


## Waterfall lips: wet-side cells next to a drain cell, grouped by readback event block.
func _find_lips() -> void:
	_lips.clear()
	_lip_dirs.clear()
	var ediv: int = LT.READBACK_DIV * 2
	for j: int in res.y:
		for i: int in res.x:
			var idx: int = j * res.x + i
			if _drain_bytes[idx] > 0 or _solid_bytes[idx] > 0:
				continue
			var out := Vector2.ZERO
			var base: float = INF
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni < 0 or nj < 0 or ni >= res.x or nj >= res.y:
					continue
				var nidx: int = nj * res.x + ni
				if _drain_bytes[nidx] > 0:
					out += Vector2(d)
					base = minf(base, _heights[nidx])
			if out == Vector2.ZERO:
				continue
			var key: int = (j / ediv) * (res.x / ediv) + (i / ediv)
			var x: float = area.position.x + (i + 0.5) * cell + out.normalized().x * cell * 0.5
			var z: float = area.position.y + (j + 0.5) * cell + out.normalized().y * cell * 0.5
			var lip_y: float = _heights[idx]
			if not _lips.has(key):
				_lips[key] = []
				_lip_dirs[key] = []
			(_lips[key] as Array).append(Vector4(x, z, lip_y, maxf(base, lip_y - 10.0)))
			(_lip_dirs[key] as Array).append(out.normalized())


func _build_surface() -> void:
	var longest: float = maxf(area.size.x, area.size.y)
	var plane := PlaneMesh.new()
	plane.size = area.size
	plane.subdivide_width = maxi(1, int(P.surface_grid() * area.size.x / longest) - 1)
	plane.subdivide_depth = maxi(1, int(P.surface_grid() * area.size.y / longest) - 1)
	_material = ShaderMaterial.new()
	_material.shader = P.shader(SURFACE_SHADER)
	_material.set_shader_parameter(&"state_tex", _state_tex)
	_material.set_shader_parameter(&"aux_tex", _aux_tex)
	_material.set_shader_parameter(&"height_tex", _height_tex)
	_material.set_shader_parameter(&"area", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	_material.set_shader_parameter(&"texel", Vector2(1.0 / res.x, 1.0 / res.y))
	_material.set_shader_parameter(&"cell", cell)
	_material.set_shader_parameter(&"shallow_color", LT.SHALLOW_COLOR)
	_material.set_shader_parameter(&"ripple_tex", _noise_texture(true, 0.035, 3))
	_material.set_shader_parameter(&"foam_tex", _noise_texture(false, 0.06, 4))
	_surface = MeshInstance3D.new()
	_surface.name = "WaterSheet"
	_surface.mesh = plane
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.position = Vector3(area.get_center().x, 0.0, area.get_center().y)
	_surface.custom_aabb = AABB(Vector3(-area.size.x * 0.5, -12.0, -area.size.y * 0.5), Vector3(area.size.x, 24.0, area.size.y))
	_surface.visible = false
	add_child(_surface)


static func _noise_texture(normal: bool, freq: float, octaves: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	if normal:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	else:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = normal
	t.bump_strength = 6.0
	t.generate_mipmaps = true
	t.normalize = true
	return t
