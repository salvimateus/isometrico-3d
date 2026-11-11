extends Node3D

## Fog test bed: ground with a path and a pond, crates and a house as obstacles, art-direction lighting,
## a perturber: the real player with --player-demo (walks and runs), else a stand-in dummy that also jumps.
## User args: --cam=game|close|tps|tpslow|top, --perturber=dummy|player|both, --dummy-mode=cycle|walk|run|jump|idle,
## --fog-debug, --no-fog, --bench, --cam-static, --night=<0..1>, --night-ramp (day -> night over 3 s).

const FogFactory := preload("res://scripts/fog/fog_factory.gd")
const Dummy := preload("res://scripts/fog/dev/fog_dummy.gd")
const Agitator := preload("res://scripts/fog/fog_agitator.gd")
const PLAYER_FACTORY_PATH: String = "res://scripts/character/player_factory.gd"

const AREA := Rect2(-17.0, -17.0, 34.0, 34.0)
const CAM_YAW_DEG: float = 45.0
const CAM_PITCH_DEG: float = -45.0
const BENCH_PHASE_FRAMES: int = 240
const DUMMY_CENTER := Vector3(6.0, 0.0, 6.5)

var _camera: Camera3D
var _cam_mode: String = "game"
var _cam_static: bool = false
var _focus := Vector3.ZERO
var _target: Node3D
var _fog: Node3D
var _heading := Vector3(0.0, 0.0, -1.0)
var _mat_cache: Dictionary = {}
var _boxes: Array[Rect2] = []

var _bench: bool = false
var _bench_frame: int = 0
var _bench_phase: int = 0
var _bench_gpu: float = 0.0
var _bench_sim: float = 0.0
var _bench_samples: int = 0
var _bench_results: Array[String] = []
var _night: float = 0.0
var _toggle_clock: float = 0.0
var _night_ramp: bool = false
var _night_clock: float = 0.0
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D


func _ready() -> void:
	Engine.max_fps = 60
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var perturber: String = "player" if args.has("--player-demo") else "dummy"
	var dummy_mode: String = "cycle"
	for arg: String in args:
		if arg.begins_with("--cam="):
			_cam_mode = arg.trim_prefix("--cam=")
		elif arg.begins_with("--perturber="):
			perturber = arg.trim_prefix("--perturber=")
		elif arg.begins_with("--night="):
			_night = clampf(arg.trim_prefix("--night=").to_float(), 0.0, 1.0)
		elif arg.begins_with("--dummy-mode="):
			dummy_mode = arg.trim_prefix("--dummy-mode=")
	_cam_static = args.has("--cam-static")
	_bench = args.has("--bench")
	_night_ramp = args.has("--night-ramp")
	_build_environment()
	_build_ground()
	_build_obstacles()

	if not args.has("--no-fog"):
		_fog = FogFactory.create(AREA)
		add_child(_fog)
		_fog.set_obstacles(_obstacle_mask())
		_fog.set_base_density(_base_mask())
		if args.has("--fog-debug"):
			_fog.set_debug_view(true)

	if perturber == "player" or perturber == "both":
		var player: Node3D = _spawn_player()
		if player != null:
			_target = player
	if perturber == "dummy" or perturber == "both" or _target == null:
		var dummy: CharacterBody3D = Dummy.new()
		dummy.mode = dummy_mode
		add_child(dummy)
		dummy.center = DUMMY_CENTER
		dummy.global_position = DUMMY_CENTER + Vector3(0.0, 0.05, 0.0)
		if _target == null:
			_target = dummy

	_set_night(_night)
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 300.0
	add_child(_camera)
	_camera.make_current()
	_focus = _target.global_position
	_place_camera(1.0)
	if _bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_stack_fog.call_deferred()


func _process(delta: float) -> void:
	_place_camera(delta)
	if _fog != null and OS.get_cmdline_user_args().has("--toggle-test"):
		# set_enabled check: off at 2 s, back on at 3.5 s.
		_toggle_clock += delta
		_fog.set_enabled(not (_toggle_clock > 2.0 and _toggle_clock < 3.5))
	if _night_ramp:
		_night_clock += delta
		_set_night(smoothstep(1.0, 4.0, _night_clock))
	if _bench:
		_bench_tick()


func _spawn_player() -> Node3D:
	if not ResourceLoader.exists(PLAYER_FACTORY_PATH):
		return null
	var factory: Script = load(PLAYER_FACTORY_PATH)
	var body: Node3D = factory.call(&"create")
	if body == null:
		return null
	add_child(body)
	body.global_position = DUMMY_CENTER + Vector3(0.0, 0.05, 0.0)
	body.add_child(Agitator.new())
	return body


func _place_camera(delta: float) -> void:
	var target_pos: Vector3 = _target.global_position
	var hv := Vector3.ZERO
	var body := _target as CharacterBody3D
	if body != null:
		hv = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if hv.length() > 0.5:
		_heading = _heading.slerp(hv.normalized(), 1.0 - exp(-3.0 * delta)).normalized()
	if _cam_mode == "tps" or _cam_mode == "tpslow":
		# Over-the-shoulder: close behind, slightly right, at or inside the fog top.
		_camera.fov = 58.0
		var height: float = 1.05 if _cam_mode == "tps" else 0.55
		var right := Vector3(-_heading.z, 0.0, _heading.x)
		var flat_target := Vector3(target_pos.x, 0.0, target_pos.z)
		var pos: Vector3 = flat_target - _heading * 1.6 + right * 0.45 + Vector3.UP * height
		var look: Vector3 = flat_target + _heading * 4.0 + Vector3.UP * (0.55 if _cam_mode == "tps" else 0.45)
		_camera.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
		return
	var distances: Dictionary = {"game": 30.0, "close": 11.0, "top": 26.0}
	var distance: float = distances.get(_cam_mode, 30.0)
	var pitch_deg: float = -80.0 if _cam_mode == "top" else CAM_PITCH_DEG
	_camera.fov = 30.0
	if not _cam_static:
		var flat := Vector3(target_pos.x, 0.4, target_pos.z)
		_focus = _focus.lerp(flat, 1.0 - exp(-4.0 * delta))
	var yaw: float = deg_to_rad(CAM_YAW_DEG)
	var pitch: float = deg_to_rad(pitch_deg)
	var dir := Vector3(cos(-pitch) * sin(yaw), sin(-pitch), cos(-pitch) * cos(yaw))
	var focus: Vector3 = DUMMY_CENTER + Vector3(0.0, 0.4, 0.0) if _cam_static else _focus
	_camera.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), focus + dir * distance)


var _alt_on: float = 0.0
var _alt_off: float = 0.0
var _alt_n_on: int = 0
var _alt_n_off: int = 0


## `--bench-alt`: toggles the fog volumes every 8 frames for 1600 frames, so both states see the same
## GPU clocks and background load; reports the mean viewport GPU time difference.
func _bench_alt_tick() -> void:
	_bench_frame += 1
	var on: bool = (_bench_frame / 8) % 2 == 0
	var settle: bool = _bench_frame % 8 < 2
	if _bench_frame > 120 and not settle:
		var t: float = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if on:
			_alt_on += t
			_alt_n_on += 1
		else:
			_alt_off += t
			_alt_n_off += 1
	for child: Node in _fog.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = on
	if _bench_frame >= 1600:
		var stack: int = _fog.get_child_count()
		var on_ms: float = _alt_on / maxi(_alt_n_on, 1)
		var off_ms: float = _alt_off / maxi(_alt_n_off, 1)
		print("[FogBench] alt: on %.3f ms, off %.3f ms, fog render per pass %.3f ms (stack %d), sim batch %.3f ms" % [on_ms, off_ms, (on_ms - off_ms) / stack, stack, float(_fog.get(&"last_sim_gpu_ms"))])
		get_tree().quit()


func _bench_tick() -> void:
	if OS.get_cmdline_user_args().has("--bench-alt"):
		_bench_alt_tick()
		return
	_bench_frame += 1
	if _bench_frame > 60 and _bench_frame <= BENCH_PHASE_FRAMES:
		_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_bench_samples += 1
		if _fog != null:
			_bench_sim += float(_fog.get(&"last_sim_gpu_ms"))
	if _bench_frame < BENCH_PHASE_FRAMES:
		return
	var labels: Array[String] = ["fog on (sim + render)", "sim only (render hidden)", "fog off"]
	_bench_results.append("%s: viewport GPU %.3f ms, sim GPU per batch (avg) %.3f ms" % [labels[_bench_phase], _bench_gpu / maxi(_bench_samples, 1), _bench_sim / maxi(_bench_samples, 1)])
	_bench_frame = 0
	_bench_gpu = 0.0
	_bench_sim = 0.0
	_bench_samples = 0
	_bench_phase += 1
	if _fog == null or _bench_phase >= 3:
		for line: String in _bench_results:
			print("[FogBench] ", line)
		get_tree().quit()
		return
	for child: Node in _fog.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
	if _bench_phase == 2:
		_fog.process_mode = Node.PROCESS_MODE_DISABLED


## Bench only: `--bench-stack=N` draws the fog volume N times so its cost dominates the frame
## (keeps GPU clocks up and makes per-pass cost measurable as delta / N).
func _stack_fog() -> void:
	if _fog == null:
		return
	var n: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-stack="):
			n = maxi(1, arg.trim_prefix("--bench-stack=").to_int())
	var src := _fog.get_node(^"FogVolume") as MeshInstance3D
	for i: int in n - 1:
		var copy := MeshInstance3D.new()
		copy.mesh = src.mesh
		copy.material_override = src.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.transform = src.transform
		_fog.add_child(copy)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	_sky_mat = sky_mat
	sky_mat.sky_top_color = Color("4F9BE8")
	sky_mat.sky_horizon_color = Color("BFE6F5")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color("2A8CB0")
	sky_mat.ground_horizon_color = Color("BFE6F5")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.6
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 2.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Color("FFF0D2")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 1.2
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	sun.look_at_from_position(Vector3(-0.85, 1.05, 0.38) * 30.0, Vector3.ZERO, Vector3.UP)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	var shape := BoxShape3D.new()
	shape.size = Vector3(44.0, 1.0, 44.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	ground.add_child(col)
	var plane := PlaneMesh.new()
	plane.size = Vector2(44.0, 44.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _mat(Color("7CC243"))
	ground.add_child(mi)
	# Dirt paths (thin fog) and a pond (thick fog).
	for r: Rect2 in [Rect2(-17.0, -0.9, 34.0, 1.8), Rect2(-0.9, -17.0, 1.8, 13.0)]:
		_flat_patch(r, Color("D9B27C"), 0.01)
	var pond := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.2
	disc.bottom_radius = 3.2
	disc.height = 0.02
	pond.mesh = disc
	pond.material_override = _mat(Color("3FA7D6"))
	pond.position = Vector3(-8.0, 0.012, 7.0)
	add_child(pond)


func _flat_patch(r: Rect2, color: Color, y: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(r.size.x, 0.02, r.size.y)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _mat(color)
	mi.position = Vector3(r.get_center().x, y, r.get_center().y)
	add_child(mi)


func _build_obstacles() -> void:
	for p: Vector3 in [Vector3(4.5, 0.0, 3.2), Vector3(-4.8, 0.0, 3.4), Vector3(1.2, 0.0, -4.2), Vector3(6.2, 0.0, -2.6)]:
		_box(p, Vector3(1.0, 1.0, 1.0), Color("A8693A"))
	# A house for legibility at play distance.
	_box(Vector3(-7.5, 0.0, -6.5), Vector3(3.0, 2.6, 3.0), Color("F2E4C8"))
	_box(Vector3(-7.5, 2.6, -6.5), Vector3(3.5, 0.7, 3.5), Color("D8452E"), false)
	_box(Vector3(12.5, 0.0, 12.0), Vector3(2.2, 3.4, 2.2), Color("C2BBAE"))
	for t: Vector3 in [Vector3(-10.5, 0.0, 10.0), Vector3(-5.0, 0.0, 10.5), Vector3(-11.0, 0.0, 4.0)]:
		_tree(t)


func _box(base: Vector3, size: Vector3, color: Color, solid_mask: bool = true) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = base + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)
	if solid_mask:
		_boxes.append(Rect2(base.x - size.x * 0.5, base.z - size.z * 0.5, size.x, size.z))


func _tree(base: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.24
	cyl.height = 1.2
	trunk.mesh = cyl
	trunk.material_override = _mat(Color("7A4A28"))
	trunk.position = base + Vector3(0.0, 0.6, 0.0)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.2
	sph.height = 2.2
	crown.mesh = sph
	crown.material_override = _mat(Color("3E9E3A"))
	crown.position = base + Vector3(0.0, 2.0, 0.0)
	add_child(crown)
	_boxes.append(Rect2(base.x - 0.3, base.z - 0.3, 0.6, 0.6))


func _to_px(r: Rect2, res: int) -> Rect2i:
	var s: float = res / AREA.size.x
	var p := Vector2((r.position.x - AREA.position.x) * s, (r.position.y - AREA.position.y) * s)
	return Rect2i(Vector2i(p.round()), Vector2i((r.size * s).round()))


func _obstacle_mask() -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_L8)
	for r: Rect2 in _boxes:
		img.fill_rect(_to_px(r, 256), Color.WHITE)
	return img


func _base_mask() -> Image:
	var res: int = 64
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09 * AREA.size.x / res
	noise.fractal_octaves = 3
	noise.seed = 11
	var img: Image = noise.get_image(res, res, false, false, true)
	img.convert(Image.FORMAT_L8)
	# Thick near the pond and trees, thin on the paths.
	img.fill_rect(_to_px(Rect2(-12.0, 3.0, 8.0, 8.0), res), Color(0.95, 0.95, 0.95))
	img.fill_rect(_to_px(Rect2(-12.0, 9.0, 9.0, 4.0), res), Color(0.85, 0.85, 0.85))
	img.fill_rect(_to_px(Rect2(0.5, 2.0, 12.0, 9.5), res), Color(0.9, 0.9, 0.9))
	img.fill_rect(_to_px(Rect2(-17.0, -1.2, 34.0, 2.4), res), Color(0.12, 0.12, 0.12))
	img.fill_rect(_to_px(Rect2(-1.2, -17.0, 2.4, 13.0), res), Color(0.12, 0.12, 0.12))
	img.resize(28, 28, Image.INTERPOLATE_BILINEAR)
	img.resize(64, 64, Image.INTERPOLATE_CUBIC)
	# Re-sharpen paths a bit after the blur.
	img.resize(res, res, Image.INTERPOLATE_BILINEAR)
	return img


func _mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mat_cache[key] = m
	return _mat_cache[key]


## Approximate moonlight: cold weak key light, low and long shadows, dark blue sky and ambient.
func _set_night(amount: float) -> void:
	_night = amount
	var day_dir := Vector3(-0.85, 1.05, 0.38)
	var night_dir := Vector3(-0.9, 0.5, -0.55)
	_sun.look_at_from_position(day_dir.lerp(night_dir, amount).normalized() * 30.0, Vector3.ZERO, Vector3.UP)
	_sun.light_color = Color("FFF0D2").lerp(Color("9DB4FF"), amount)
	_sun.light_energy = lerpf(1.5, 0.35, amount)
	_sky_mat.sky_top_color = Color("4F9BE8").lerp(Color("0B1430"), amount)
	_sky_mat.sky_horizon_color = Color("BFE6F5").lerp(Color("2A3A5E"), amount)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color("2A8CB0").lerp(Color("0A1426"), amount)
	_env.ambient_light_energy = lerpf(0.45, 0.3, amount)
	if _fog != null:
		_fog.set_night(amount)
