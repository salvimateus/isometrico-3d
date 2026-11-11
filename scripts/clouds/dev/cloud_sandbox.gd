extends Node3D

## Cloud test bed: green ground, reference cube at the origin, art-direction sun and sky.
## User args: --cam=iso|far|shoulder|top, --dist=<iso distance>, --pitch=<shoulder pitch deg>,
## --yaw=<shoulder heading deg>, --night=<0..1>, --night-ramp, --cross (a cloud on the iso sightline),
## --suppress-at=<frame>, --release-at=<frame>, --disable-at=<frame>, --enable-at=<frame>, --seed=<n>, --bench (GPU time with and without clouds), --no-clouds.

const CloudFactory := preload("res://scripts/clouds/cloud_factory.gd")
const GROUND_SHADER_PATH: String = "res://shaders/clouds/sandbox_ground.gdshader"

const AREA := Rect2(-110.0, -110.0, 220.0, 220.0)
const DAY_DIR := Vector3(-0.85, 1.05, 0.38)
const NIGHT_DIR := Vector3(0.55, 0.85, -0.6)
const BENCH_PHASE_FRAMES: int = 900
const BENCH_WARMUP_FRAMES: int = 300

var _camera: Camera3D
var _clouds: Node3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _night: float = 0.0
var _night_ramp: bool = false
var _night_clock: float = 0.0
var _frame: int = 0
var _suppress_at: int = -1
var _release_at: int = -1
var _disable_at: int = -1
var _enable_at: int = -1

var _bench: bool = false
var _bench_frame: int = 0
var _bench_phase: int = 0
var _bench_gpu: float = 0.0
var _bench_samples: int = 0
var _bench_start_usec: int = 0
var _bench_results: Array[String] = []


func _ready() -> void:
	Engine.max_fps = 60
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cam_mode: String = "iso"
	var dist: float = 30.0
	var pitch: float = 6.0
	var yaw: float = 200.0
	for arg: String in args:
		if arg.begins_with("--cam="):
			cam_mode = arg.trim_prefix("--cam=")
		elif arg.begins_with("--dist="):
			dist = arg.trim_prefix("--dist=").to_float()
		elif arg.begins_with("--pitch="):
			pitch = arg.trim_prefix("--pitch=").to_float()
		elif arg.begins_with("--yaw="):
			yaw = arg.trim_prefix("--yaw=").to_float()
		elif arg.begins_with("--suppress-at="):
			_suppress_at = arg.trim_prefix("--suppress-at=").to_int()
		elif arg.begins_with("--disable-at="):
			_disable_at = arg.trim_prefix("--disable-at=").to_int()
		elif arg.begins_with("--enable-at="):
			_enable_at = arg.trim_prefix("--enable-at=").to_int()
		elif arg.begins_with("--release-at="):
			_release_at = arg.trim_prefix("--release-at=").to_int()
		elif arg.begins_with("--night="):
			_night = clampf(arg.trim_prefix("--night=").to_float(), 0.0, 1.0)
	if cam_mode == "far":
		dist = 76.0
	_night_ramp = args.has("--night-ramp")
	_bench = args.has("--bench")

	# The game declares these in project.godot; the sandbox registers them at runtime before any shader compiles.
	if not ProjectSettings.has_setting("shader_globals/cloud_shadow_map"):
		RenderingServer.global_shader_parameter_add(&"cloud_shadow_map", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null)
		RenderingServer.global_shader_parameter_add(&"cloud_shadow_rect", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.0, 0.0, 1.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"player_position", Vector3(0.0, 0.5, 0.0))

	_build_environment()
	_build_ground()

	_camera = Camera3D.new()
	_camera.near = 0.05 if cam_mode == "shoulder" else 0.5
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()
	_place_camera(cam_mode, dist, pitch, yaw)

	if not args.has("--no-clouds"):
		_clouds = CloudFactory.create(AREA)
		_clouds.set(&"publish_shadow_global", true)
		for arg: String in args:
			if arg.begins_with("--seed="):
				_clouds.call(&"configure", AREA, arg.trim_prefix("--seed=").to_int(), CloudFactory.is_mobile())
		add_child(_clouds)
		if args.has("--cross"):
			_clouds.call(&"spawn_crosser", 0.0, true)
	_set_night(_night)

	if _bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_frame += 1
	if _clouds != null:
		if _frame == _suppress_at:
			_clouds.call(&"set_suppressed", true)
		if _frame == _release_at:
			_clouds.call(&"set_suppressed", false)
		if _frame == _disable_at:
			_clouds.call(&"set_enabled", false)
		if _frame == _enable_at:
			_clouds.call(&"set_enabled", true)
	if _night_ramp:
		_night_clock += delta
		_set_night(smoothstep(1.0, 4.0, _night_clock))
	if _bench:
		_bench_tick()


func _place_camera(mode: String, dist: float, pitch_deg: float, yaw_deg: float) -> void:
	if mode == "top":
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = AREA.size.y
		_camera.far = 400.0
		_camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0.0, 150.0, 0.0))
		return
	if mode == "shoulder":
		_camera.fov = 57.0
		var heading := Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))
		var right := Vector3(-heading.z, 0.0, heading.x)
		var pos: Vector3 = -heading * 1.5 + right * 1.0 + Vector3.UP * 1.0
		var look_dir: Vector3 = (heading * cos(deg_to_rad(pitch_deg)) + Vector3.UP * sin(deg_to_rad(pitch_deg))).normalized()
		_camera.global_transform = Transform3D(Basis.looking_at(look_dir, Vector3.UP), pos)
		return
	_camera.fov = 30.0
	var yaw: float = deg_to_rad(45.0)
	var pitch: float = deg_to_rad(-45.0)
	var dir := Vector3(cos(-pitch) * sin(yaw), sin(-pitch), cos(-pitch) * cos(yaw))
	_camera.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3(0.0, 0.4, 0.0) + dir * dist)


## Alternates clouds on/off phases (after a warmup so GPU clocks settle) and prints the averages.
func _bench_tick() -> void:
	_bench_frame += 1
	if _bench_frame == BENCH_WARMUP_FRAMES:
		_bench_start_usec = Time.get_ticks_usec()
	if _bench_frame > BENCH_WARMUP_FRAMES and _bench_frame <= BENCH_PHASE_FRAMES:
		_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_bench_samples += 1
	if _bench_frame < BENCH_PHASE_FRAMES:
		return
	var on: bool = _bench_phase % 2 == 0
	var wall_ms: float = (Time.get_ticks_usec() - _bench_start_usec) / 1000.0 / maxi(_bench_samples, 1)
	_bench_results.append("%s: frame GPU %.3f ms, wall %.3f ms/frame" % ["clouds on " if on else "clouds off", _bench_gpu / maxi(_bench_samples, 1), wall_ms])
	_bench_frame = 0
	_bench_gpu = 0.0
	_bench_samples = 0
	_bench_phase += 1
	if _clouds == null or _bench_phase >= 4:
		for line: String in _bench_results:
			print("[CloudBench] ", line)
		get_tree().quit()
		return
	_clouds.call(&"set_enabled", not on)


func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color("4F9BE8")
	_sky_mat.sky_horizon_color = Color("BFE6F5")
	_sky_mat.sky_curve = 0.12
	_sky_mat.ground_bottom_color = Color("2A8CB0")
	_sky_mat.ground_horizon_color = Color("BFE6F5")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.45
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 0.95
	_env.tonemap_white = 6.0
	_env.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_hdr_threshold = 2.2
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = Color("BFE3F2")
	_env.fog_depth_begin = 105.0
	_env.fog_depth_end = 260.0
	_env.fog_depth_curve = 1.4
	_env.fog_density = 0.6
	_env.fog_sky_affect = 0.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.05
	_env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Color("FFF0D2")
	_sun.light_energy = 1.5
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)


func _build_ground() -> void:
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = load(GROUND_SHADER_PATH)
	var plane := PlaneMesh.new()
	plane.size = Vector2(AREA.size.x * 2.0, AREA.size.y * 2.0)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = ground_mat
	add_child(ground)
	var cube_mat := StandardMaterial3D.new()
	cube_mat.albedo_color = Color("D8452E")
	cube_mat.roughness = 0.8
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	cube.mesh = box
	cube.material_override = cube_mat
	cube.position = Vector3(0.0, 0.5, 0.0)
	add_child(cube)


func _set_night(amount: float) -> void:
	_night = amount
	_sun.look_at_from_position(DAY_DIR.lerp(NIGHT_DIR, amount).normalized() * 30.0, Vector3.ZERO, Vector3.UP)
	_sun.light_color = Color("FFF0D2").lerp(Color("9DB4FF"), amount)
	_sun.light_energy = lerpf(1.5, 0.35, amount)
	_sky_mat.sky_top_color = Color("4F9BE8").lerp(Color("0B1A2E"), amount)
	_sky_mat.sky_horizon_color = Color("BFE6F5").lerp(Color("24455A"), amount)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color("2A8CB0").lerp(Color("0A1426"), amount)
	_env.ambient_light_energy = lerpf(0.45, 0.3, amount)
	_env.fog_light_color = Color("BFE3F2").lerp(Color("1C3346"), amount)
	if _clouds != null:
		_clouds.call(&"set_night", amount)
