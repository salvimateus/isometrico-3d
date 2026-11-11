extends Node3D

## Ground fog field: owns the GPU fluid sim and the raymarched slab that renders it.
## Public API: add_impulse, add_burst, set_obstacles, set_base_density. Group &"fog_field". F3 toggles debug.
## Keep this node at the identity transform: `area` and every position are world XZ.

const FT := preload("res://scripts/fog/fog_tuning.gd")
const Sim := preload("res://scripts/fog/fog_sim.gd")
const VOLUME_SHADER := preload("res://shaders/fog/fog_volume.gdshader")

const KIND_IMPULSE: float = 0.0
const KIND_BURST: float = 1.0

const QUALITY_PATH: String = "res://scripts/quality.gd"

var area := Rect2(-17.0, -17.0, 34.0, 34.0)
var mobile: bool = false
var _enabled: bool = true
var _fade: float = 1.0
var last_sim_gpu_ms: float:
	get:
		return _sim.last_gpu_ms if _sim != null else 0.0

var _sim: Sim
var _res := Vector2i(256, 256)
var _cell: float = 0.1
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _state_tex := Texture2DRD.new()
var _coords_tex := Texture2DRD.new()
var _obstacle_tex := Texture2DRD.new()
var _lift_tex := Texture2DRD.new()
var _night: float = 0.0
var _bound: bool = false
var _pending: PackedFloat32Array = PackedFloat32Array()
var _pending_count: int = 0
var _delayed: Array[Dictionary] = []
var _accum: float = 0.0
var _sim_time: float = 0.0
var _debug: bool = false
var _sun: DirectionalLight3D
var _sun_color: Color = FT.SUN_FALLBACK_COLOR
var _lights: Array[OmniLight3D] = []
var _light_scan: float = 0.0
var _light_pick: float = 0.0
var _sun_search_cooldown: float = 0.0
var _obstacle_data: PackedByteArray
var _base_data: PackedByteArray
var _reach_data: PackedByteArray


func configure(world_area: Rect2) -> void:
	area = world_area
	mobile = _is_mobile_tier()
	if OS.get_cmdline_user_args().has("--bench"):
		print("[FogBench] profile mobile=", mobile, " args=", OS.get_cmdline_user_args())
	var longest: float = maxf(area.size.x, area.size.y)
	_cell = longest / float(FT.MOBILE_SIM_RESOLUTION if mobile else FT.SIM_RESOLUTION)
	_res = Vector2i(maxi(8, ceili(area.size.x / _cell)), maxi(8, ceili(area.size.y / _cell)))


func _ready() -> void:
	add_to_group(&"fog_field")
	if _obstacle_data.is_empty():
		_obstacle_data = PackedByteArray()
		_obstacle_data.resize(_res.x * _res.y)
	if _base_data.is_empty():
		_base_data = _noise_base()
	_sim = Sim.new(_res, _cell, _hz(), FT.MOBILE_PRESSURE_ITERATIONS if mobile else FT.PRESSURE_ITERATIONS)
	_reach_data = _reach_from(_base_data)
	RenderingServer.call_on_render_thread(_sim.setup.bind(_obstacle_data, _base_data, _reach_data))
	_build_volume()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fog-dusk-at="):
			_dev_dusk_at(arg.trim_prefix("--fog-dusk-at=").to_int())


func _exit_tree() -> void:
	if _sim != null:
		_mesh.material_override = null
		_state_tex.texture_rd_rid = RID()
		_coords_tex.texture_rd_rid = RID()
		_obstacle_tex.texture_rd_rid = RID()
		_lift_tex.texture_rd_rid = RID()
		RenderingServer.call_on_render_thread(_sim.free_all)


## Continuous push from a moving body near the ground (call every physics frame).
func add_impulse(pos: Vector3, velocity: Vector3, radius: float) -> void:
	var v := Vector2(velocity.x, velocity.z)
	var run: float = clampf(v.length() / FT.AGITATE_RUN_SPEED, 0.0, 1.0)
	_queue(pos, radius, KIND_IMPULSE, v, lerpf(FT.AGITATE_WALK_GAIN, 1.0, run * run))


## Radial outward blast that displaces density (takeoff, landing). Strength ~0.3 (puff) to ~1.5 (heavy landing).
func add_burst(pos: Vector3, strength: float, radius: float) -> void:
	_queue(pos, radius, KIND_BURST, Vector2.ZERO, strength)
	if strength > 0.0:
		_delayed.append({"t": FT.RECOIL_DELAY, "pos": pos, "strength": -strength * FT.RECOIL_RATIO, "radius": radius * FT.RECOIL_RADIUS_SCALE})


## White = solid. Image spans `area`: x -> world X, y -> world Z (row 0 at area.position.y). Any resolution.
func set_obstacles(mask: Image) -> void:
	_obstacle_data = _mask_bytes(mask)
	if _sim != null:
		RenderingServer.call_on_render_thread(_sim.upload_obstacles.bind(_obstacle_data))


## White = thickest fog, black = thinnest. Same mapping as set_obstacles.
func set_base_density(mask: Image) -> void:
	_base_data = _mask_bytes(mask)
	_base_data = _apply_dev_remap(_base_data)
	if _sim != null:
		_reach_data = _reach_from(_base_data)
		RenderingServer.call_on_render_thread(_sim.upload_base.bind(_base_data, _reach_data))


## 0 = day, 1 = night: denser, taller, bluish moonlit fog that regenerates faster and drifts slower.
## Cheap to call every frame during a transition.
func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	_apply_look()


## Off: fades out, then hides the volume and stops dispatching the sim (~0 cost). On: resumes and fades in.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if on:
		_accum = 0.0
		if _bound:
			_mesh.visible = true
		set_process(true)
	else:
		_pending = PackedFloat32Array()
		_pending_count = 0
		_delayed.clear()


func is_enabled() -> bool:
	return _enabled


## Returns false when the field is fully off and nothing else should run this frame.
func _update_fade(delta: float) -> bool:
	var target: float = 1.0 if _enabled else 0.0
	if _fade != target:
		_fade = move_toward(_fade, target, delta / FT.TOGGLE_FADE_TIME)
		_material.set_shader_parameter(&"fade", _fade)
	if not _enabled:
		if _fade <= 0.0:
			_mesh.visible = false
			set_process(false)
		return false
	return true


func set_debug_view(enabled: bool) -> void:
	_debug = enabled
	if _material != null:
		_material.set_shader_parameter(&"debug_view", enabled)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		set_debug_view(not _debug)


func _process(delta: float) -> void:
	if _sim == null:
		return
	if not _bound and _sim.ready:
		_state_tex.texture_rd_rid = _sim.state_rid
		_coords_tex.texture_rd_rid = _sim.coords_rid
		_obstacle_tex.texture_rd_rid = _sim.obstacle_rid
		_lift_tex.texture_rd_rid = _sim.lift_rid
		_bound = true
		_mesh.visible = true
	if not _update_fade(delta):
		return
	_update_sun(delta)
	_update_lights(delta)
	_update_delayed(delta)

	var dt: float = 1.0 / _hz()
	_accum = minf(_accum + delta, dt * FT.SIM_MAX_STEPS_PER_FRAME)
	var steps: Array[Vector4] = []
	while _accum >= dt:
		_accum -= dt
		var prev: float = _sim_time
		_sim_time += dt
		var flags: int = 0
		if floorf(_sim_time / FT.FLOW_PERIOD) != floorf(prev / FT.FLOW_PERIOD):
			flags |= 1
		if floorf(_sim_time / FT.FLOW_PERIOD + 0.5) != floorf(prev / FT.FLOW_PERIOD + 0.5):
			flags |= 2
		steps.append(Vector4(_sim_time, flags, _pending_count if steps.is_empty() else 0, _night))
	if steps.is_empty():
		RenderingServer.call_on_render_thread(_sim.read_timing)
		return
	var data: PackedFloat32Array = _pending
	_pending = PackedFloat32Array()
	_pending_count = 0
	RenderingServer.call_on_render_thread(_sim.step.bind(steps, data))
	_material.set_shader_parameter(&"flow_time", _sim_time)


func _queue(pos: Vector3, radius: float, kind: float, vel: Vector2, strength: float) -> void:
	if not _enabled or _pending_count >= FT.MAX_SPLATS_PER_STEP:
		return
	var c := Vector2((pos.x - area.position.x) / _cell, (pos.z - area.position.y) / _cell)
	var r: float = radius / _cell
	if c.x < -3.0 * r or c.y < -3.0 * r or c.x > _res.x + 3.0 * r or c.y > _res.y + 3.0 * r:
		return
	_pending.append_array(PackedFloat32Array([c.x, c.y, r, kind, vel.x, vel.y, strength, randf()]))
	_pending_count += 1


func _update_delayed(delta: float) -> void:
	for i: int in range(_delayed.size() - 1, -1, -1):
		var d: Dictionary = _delayed[i]
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) <= 0.0:
			_queue(d["pos"], d["radius"], KIND_BURST, Vector2.ZERO, d["strength"])
			_delayed.remove_at(i)


func _build_volume() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(area.size.x, FT.FOG_BOX_HEIGHT, area.size.y)
	_mesh = MeshInstance3D.new()
	_mesh.name = "FogVolume"
	_mesh.mesh = box
	_mesh.position = Vector3(area.get_center().x, FT.FOG_BOX_HEIGHT * 0.5, area.get_center().y)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.visible = false
	_material = ShaderMaterial.new()
	if OS.get_cmdline_user_args().has("--fog-no-depth"):
		var variant := Shader.new()
		variant.code = VOLUME_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define FOG_NO_DEPTH")
		_material.shader = variant
	else:
		_material.shader = VOLUME_SHADER
	var m := _material
	m.set_shader_parameter(&"state_tex", _state_tex)
	m.set_shader_parameter(&"coords_tex", _coords_tex)
	m.set_shader_parameter(&"obstacle_tex", _obstacle_tex)
	m.set_shader_parameter(&"lift_tex", _lift_tex)
	m.set_shader_parameter(&"lift_density", FT.LIFT_DENSITY)
	m.set_shader_parameter(&"lift_floor_gap", FT.LIFT_FLOOR_GAP)
	m.set_shader_parameter(&"lift_spread", FT.LIFT_SPREAD)
	m.set_shader_parameter(&"light_fog_gain", FT.FOG_LIGHT_GAIN)
	m.set_shader_parameter(&"density_contrast", FT.DENSITY_CONTRAST)
	m.set_shader_parameter(&"light_probe", FT.LIGHT_PROBE)
	m.set_shader_parameter(&"obstacle_shadow_height", FT.OBSTACLE_SHADOW_HEIGHT)
	m.set_shader_parameter(&"noise_tex", _noise_texture())
	m.set_shader_parameter(&"area_origin", area.position)
	m.set_shader_parameter(&"area_size", area.size)
	m.set_shader_parameter(&"box_height", FT.FOG_BOX_HEIGHT)
	m.set_shader_parameter(&"top_min", FT.FOG_TOP_MIN)
	m.set_shader_parameter(&"top_softness", FT.FOG_TOP_SOFTNESS)
	m.set_shader_parameter(&"extinction", FT.FOG_EXTINCTION)
	m.set_shader_parameter(&"edge_fade", FT.FOG_EDGE_FADE)
	m.set_shader_parameter(&"wisp_scale", FT.WISP_SCALE)
	m.set_shader_parameter(&"wisp_strength", FT.WISP_STRENGTH)
	m.set_shader_parameter(&"top_noise_scale", FT.TOP_NOISE_SCALE)
	m.set_shader_parameter(&"top_noise_strength", FT.TOP_NOISE_STRENGTH)
	m.set_shader_parameter(&"flow_period", FT.FLOW_PERIOD)
	m.set_shader_parameter(&"steps_min", FT.MOBILE_MARCH_STEPS_MIN if mobile else FT.MARCH_STEPS_MIN)
	m.set_shader_parameter(&"steps_max", FT.MOBILE_MARCH_STEPS_MAX if mobile else FT.MARCH_STEPS_MAX)
	m.set_shader_parameter(&"step_length", FT.MOBILE_MARCH_STEP_LENGTH if mobile else FT.MARCH_STEP_LENGTH)
	m.set_shader_parameter(&"high_lighting", FT.MOBILE_HIGH_LIGHTING if mobile else true)
	m.set_shader_parameter(&"max_distance", FT.MARCH_MAX_DISTANCE)
	m.set_shader_parameter(&"clear_near", FT.CAMERA_CLEAR_NEAR)
	m.set_shader_parameter(&"clear_far", FT.CAMERA_CLEAR_FAR)
	m.set_shader_parameter(&"grazing_dir_y", Vector2(FT.GRAZING_DIR_Y_MIN, FT.GRAZING_DIR_Y_MAX))
	m.set_shader_parameter(&"grazing_fade", Vector2(FT.GRAZING_FADE_NEAR, FT.GRAZING_FADE_FAR))
	m.set_shader_parameter(&"grazing_far_density", FT.GRAZING_FAR_DENSITY)
	m.set_shader_parameter(&"grazing_max_alpha", FT.GRAZING_MAX_ALPHA)
	m.set_shader_parameter(&"sun_dir", FT.SUN_FALLBACK_DIR.normalized())
	_mesh.material_override = _material
	add_child(_mesh)
	_apply_look()


func _update_sun(delta: float) -> void:
	# Re-pick every second: day/night may hide the sun and show a separate moon light.
	_sun_search_cooldown -= delta
	if _sun_search_cooldown <= 0.0 or not is_instance_valid(_sun) or not _sun.is_visible_in_tree():
		_sun_search_cooldown = 1.0
		var best: DirectionalLight3D = _find_sun(get_tree().root)
		if best != null:
			_sun = best
	if is_instance_valid(_sun):
		_material.set_shader_parameter(&"sun_dir", _sun.global_basis.z.normalized())
		_sun_color = _sun.light_color * (_sun.light_energy / 1.5)
		_apply_look()


func _apply_look() -> void:
	if _material == null:
		return
	var n: float = _night
	var m := _material
	var moon: Color = FT.NIGHT_MOON_COLOR * FT.NIGHT_MOON_ENERGY
	m.set_shader_parameter(&"night", n)
	if mobile:
		m.set_shader_parameter(&"steps_max", roundi(lerpf(FT.MOBILE_MARCH_STEPS_MAX, FT.MOBILE_NIGHT_STEPS_MAX, n)))
	m.set_shader_parameter(&"sun_scatter", lerpf(FT.SUN_SCATTER, FT.NIGHT_SUN_SCATTER, n))
	m.set_shader_parameter(&"self_shadow", lerpf(FT.SELF_SHADOW, FT.NIGHT_SELF_SHADOW, n))
	m.set_shader_parameter(&"sun_color", _sun_color.lerp(moon, n))
	m.set_shader_parameter(&"density_scale", lerpf(1.0, FT.NIGHT_DENSITY_SCALE, n))
	m.set_shader_parameter(&"fog_height", FT.FOG_HEIGHT * lerpf(1.0, FT.NIGHT_HEIGHT_SCALE, n))
	m.set_shader_parameter(&"top_color", FT.FOG_TOP_COLOR.lerp(FT.NIGHT_TOP_COLOR, n))
	m.set_shader_parameter(&"shadow_color", FT.FOG_SHADOW_COLOR.lerp(FT.NIGHT_SHADOW_COLOR, n))
	m.set_shader_parameter(&"ambient", lerpf(FT.FOG_AMBIENT, FT.NIGHT_AMBIENT, n))
	m.set_shader_parameter(&"forward_scatter", lerpf(FT.FORWARD_SCATTER, FT.NIGHT_FORWARD_SCATTER, n))
	m.set_shader_parameter(&"billow_shading", lerpf(FT.BILLOW_SHADING, FT.NIGHT_BILLOW_SHADING, n))
	m.set_shader_parameter(&"obstacle_shadow", lerpf(FT.OBSTACLE_SHADOW, FT.NIGHT_OBSTACLE_SHADOW, n))


## Feeds the nearest visible OmniLight3D nodes (lanterns, windows) to the fog as a warm glow.
func _update_lights(delta: float) -> void:
	_light_scan -= delta
	_light_pick -= delta
	if _light_scan <= 0.0:
		_light_scan = FT.FOG_LIGHT_SCAN
		_lights.clear()
		for node: Node in get_tree().root.find_children("*", "OmniLight3D", true, false):
			_lights.append(node as OmniLight3D)
	if _light_pick > 0.0:
		return
	_light_pick = FT.FOG_LIGHT_REFRESH
	var cam: Camera3D = get_viewport().get_camera_3d()
	var origin: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var live: Array[OmniLight3D] = []
	for l: OmniLight3D in _lights:
		if is_instance_valid(l) and l.is_visible_in_tree() and l.light_energy > 0.01:
			var p: Vector3 = l.global_position
			if area.has_point(Vector2(p.x, p.z)) and p.y < FT.FOG_BOX_HEIGHT + l.omni_range:
				live.append(l)
	live.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	var count: int = mini(live.size(), FT.FOG_LIGHTS_MAX)
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	pos.resize(FT.FOG_LIGHTS_MAX)
	col.resize(FT.FOG_LIGHTS_MAX)
	for i: int in count:
		var l: OmniLight3D = live[i]
		var c: Color = l.light_color * l.light_energy
		pos[i] = Vector4(l.global_position.x, l.global_position.y, l.global_position.z, l.omni_range * FT.FOG_LIGHT_RANGE_SCALE)
		col[i] = Vector4(c.r, c.g, c.b, 0.0)
	_material.set_shader_parameter(&"light_count", count)
	_material.set_shader_parameter(&"light_pos", pos)
	_material.set_shader_parameter(&"light_col", col)


func _find_sun(root: Node) -> DirectionalLight3D:
	var best: DirectionalLight3D = null
	for node: Node in root.find_children("*", "DirectionalLight3D", true, false):
		var l := node as DirectionalLight3D
		if l.is_visible_in_tree() and (best == null or l.light_energy > best.light_energy):
			best = l
	return best


func _mask_bytes(mask: Image) -> PackedByteArray:
	var img: Image = mask.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	img.resize(_res.x, _res.y, Image.INTERPOLATE_BILINEAR)
	return img.get_data()


func _noise_base() -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = FT.BASE_NOISE_FREQUENCY * _cell
	noise.fractal_octaves = 3
	noise.seed = 7
	var img: Image = noise.get_image(_res.x, _res.y, false, false, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


func _noise_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 4.0 / float(FT.NOISE_TEXTURE_SIZE)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.45
	noise.seed = 3
	var img: Image = noise.get_seamless_image(FT.NOISE_TEXTURE_SIZE, FT.NOISE_TEXTURE_SIZE, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Dev only: `--fog-base-remap=lo,hi` remaps base mask values linearly to test new mask values without
## editing the mask producer.
func _apply_dev_remap(data: PackedByteArray) -> PackedByteArray:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--fog-base-remap="):
			continue
		var parts: PackedStringArray = arg.trim_prefix("--fog-base-remap=").split(",")
		if parts.size() != 2:
			return data
		var img := Image.create_from_data(_res.x, _res.y, false, Image.FORMAT_L8, data)
		var lo: float = parts[0].to_float()
		var hi: float = parts[1].to_float()
		for y: int in _res.y:
			for x: int in _res.x:
				var v: float = clampf((img.get_pixel(x, y).r - lo) / maxf(hi - lo, 1e-3), 0.0, 1.0)
				img.set_pixel(x, y, Color(v, v, v))
		return img.get_data()
	return data


## Wide blur of the base map: how close a cell is to thick fog. Drives the night front.
func _reach_from(base: PackedByteArray) -> PackedByteArray:
	var img := Image.create_from_data(_res.x, _res.y, false, Image.FORMAT_L8, base)
	var small := Vector2i(maxi(2, _res.x / FT.NIGHT_REACH_BLUR), maxi(2, _res.y / FT.NIGHT_REACH_BLUR))
	img.resize(small.x, small.y, Image.INTERPOLATE_BILINEAR)
	img.resize(_res.x, _res.y, Image.INTERPOLATE_CUBIC)
	return img.get_data()


func _hz() -> float:
	return FT.MOBILE_SIM_HZ if mobile else FT.SIM_HZ


## Quality tier from the shared quality script when present; else the --quality=mobile flag or a mobile OS.
static func _is_mobile_tier() -> bool:
	if ResourceLoader.exists(QUALITY_PATH):
		var q: Script = load(QUALITY_PATH)
		if q != null:
			for m: Dictionary in q.get_script_method_list():
				if m["name"] == "tier":
					return q.call(&"tier") == &"mobile"
	return OS.get_cmdline_user_args().has("--quality=mobile") or OS.has_feature("mobile")


## Dev only: `--fog-dusk-at=N` asks the scene's DayNight node to start the night transition after N frames.
func _dev_dusk_at(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame
	var dn: Node = get_tree().root.find_child("DayNight", true, false)
	if dn != null and dn.has_method(&"set_night"):
		dn.call(&"set_night", true, false)
