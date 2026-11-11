extends Node3D

## Test bed for the liquid field: slope, pond, cliff drain edge, crates and a gated wall, the water tower
## (BUILDINGS model when available, named proxies otherwise), a wading dummy or the real player.
## User args: --cam=iso|shoulder|edge|top, --focus=x,z, --dist=<d>, --night=<0..1>, --auto-trigger=<frame>,
## --seq=<name>:<f1>,<f2>,... (saves _shots/liquid/<name>_<frame>.png and quits), --player-demo, --no-dummy,
## --bench (prints GPU timings), --no-liquid. Keys: T triggers, N toggles night.

const LiquidFactory := preload("res://scripts/liquid/liquid_factory.gd")
const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const SHOT_DIR: String = "C:/dev/isometrico-3d/_shots/liquid/"
const GROUND_SHADER_CODE: String = """
shader_type spatial;
render_mode cull_back, diffuse_burley;
global uniform sampler2D liquid_wetness_map : filter_linear, repeat_disable;
global uniform vec4 liquid_area;
uniform vec3 grass : source_color = vec3(0.49, 0.76, 0.26);
uniform vec3 grass_dark : source_color = vec3(0.38, 0.64, 0.2);
uniform vec3 dirt : source_color = vec3(0.71, 0.55, 0.34);
uniform vec3 rock : source_color = vec3(0.55, 0.52, 0.48);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 cell = floor(wp.xz);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(grass, grass_dark, checker * 0.3);
	float path = smoothstep(0.9, 0.6, abs(wp.x + 2.2 + sin(wp.z * 0.4) * 0.6));
	col = mix(col, dirt, path * step(-9.0, wp.z));
	col = mix(col, dirt * 0.9, smoothstep(-0.12, -0.3, wp.y));
	col = mix(col, rock, smoothstep(0.55, 0.35, wn.y));
	vec2 uv = (wp.xz - liquid_area.xy) / liquid_area.zw;
	float wet = 0.0;
	if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		wet = texture(liquid_wetness_map, uv).r;
	}
	wet = smoothstep(0.0, 0.6, wet);
	col *= mix(1.0, 0.55, wet);
	col = mix(col, col * vec3(0.92, 0.97, 1.03), wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.28, wet);
	SPECULAR = mix(0.25, 0.55, wet);
}
"""

var _field: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dummy: Node3D
var _player: Node3D
var _night: float = 0.0
var _frame: int = 0
var _auto_trigger: int = -1
var _seq_name: String = ""
var _seq_frames: Array[int] = []
var _cam_mode: String = "iso"
var _focus := Vector3(-3.0, 0.0, -1.0)
var _dist: float = 30.0
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _bench: bool = false
var _bench_sim: Array[float] = []
var _bench_frame: Array[float] = []
var _area := Rect2(-16.0, -16.0, 32.0, 32.0)
var _dummy_t: float = 0.0
var _fx_demo: int = -1
var _world_mode: bool = false
var _ditch_test: int = -1
var _world_half: float = 0.0


func _ready() -> void:
	add_to_group(&"camera_rig")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--cam="):
			_cam_mode = arg.trim_prefix("--cam=")
		elif arg.begins_with("--night="):
			_night = clampf(arg.trim_prefix("--night=").to_float(), 0.0, 1.0)
		elif arg.begins_with("--auto-trigger="):
			_auto_trigger = arg.trim_prefix("--auto-trigger=").to_int()
		elif arg.begins_with("--focus="):
			var parts: PackedStringArray = arg.trim_prefix("--focus=").split(",")
			if parts.size() >= 2:
				_focus = Vector3(parts[0].to_float(), 0.0, parts[1].to_float())
		elif arg.begins_with("--fx-demo="):
			_fx_demo = arg.trim_prefix("--fx-demo=").to_int()
		elif arg.begins_with("--world-area="):
			_world_half = arg.trim_prefix("--world-area=").to_float()
		elif arg.begins_with("--ditch-test="):
			_ditch_test = arg.trim_prefix("--ditch-test=").to_int()
		elif arg.begins_with("--dist="):
			_dist = arg.trim_prefix("--dist=").to_float()
		elif arg.begins_with("--seq="):
			var spec: PackedStringArray = arg.trim_prefix("--seq=").split(":")
			_seq_name = spec[0]
			if spec.size() > 1:
				for f: String in spec[1].split(","):
					_seq_frames.append(f.to_int())
	_bench = args.has("--bench")
	if args.has("--world"):
		# Probe the real map: main.tscn reads its own args (e.g. --liquid-trigger=<frame>).
		add_child(load("res://scenes/main.tscn").instantiate())
		_world_mode = true
		return
	_noise.frequency = 1.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	# The game declares these in project.godot; the sandbox registers them before any shader compiles.
	if not ProjectSettings.has_setting("shader_globals/liquid_wetness_map"):
		RenderingServer.global_shader_parameter_add(&"liquid_wetness_map", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null)
		RenderingServer.global_shader_parameter_add(&"liquid_area", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(_area.position.x, _area.position.y, _area.size.x, _area.size.y))
		Engine.set_meta(&"liquid_globals_registered", true)

	_build_environment()
	_build_ground()
	var solids: Array[Rect2] = _build_obstacles()
	var parts: Array[Node3D] = _build_tower()

	if not args.has("--no-liquid"):
		_field = LiquidFactory.create(_area)
		add_child(_field)
		_field.call(&"set_terrain", _height_image(), _solid_image(solids), _drain_image())
		_field.call(&"attach_tower", parts[0], parts[1])
		_field.call(&"set_night", _night)

	if args.has("--player-demo") and ResourceLoader.exists("res://scripts/character/player_factory.gd"):
		var pf: Script = load("res://scripts/character/player_factory.gd")
		_player = pf.call(&"create")
		add_child(_player)
		_player.call(&"teleport", Vector3(-2.2, 0.1, 5.0))
	elif not args.has("--no-dummy"):
		_dummy = MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.25
		cap.height = 1.0
		_dummy.mesh = cap
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color("D8452E")
		_dummy.material_override = dm
		add_child(_dummy)

	_camera = Camera3D.new()
	_camera.far = 300.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_apply_night()


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_T and _field != null:
			_field.call(&"trigger")
		elif key.keycode == KEY_N:
			_night = 1.0 - _night
			_apply_night()


func _process(delta: float) -> void:
	_frame += 1
	if _world_mode:
		if _field == null:
			_field = get_tree().get_first_node_in_group(&"liquid_field") as Node3D
		if _frame == 3 and _world_half > 0.0 and _field != null:
			_swap_world_field()
		if _frame == 5 and _cam_mode == "world_iso":
			var ic := Camera3D.new()
			ic.fov = 30.0
			add_child(ic)
			var d: Vector3 = Basis(Vector3.UP, deg_to_rad(45.0)) * Basis(Vector3.RIGHT, deg_to_rad(-45.0)) * Vector3(0.0, 0.0, 1.0)
			ic.look_at_from_position(_focus + d * _dist, _focus, Vector3.UP)
			ic.make_current()
		if _frame == 5 and _cam_mode == "world_edge":
			var ec := Camera3D.new()
			ec.fov = 40.0
			add_child(ec)
			ec.look_at_from_position(Vector3(_focus.x + 10.0, 5.0, _focus.z + 9.0), Vector3(_focus.x, -1.0, _focus.z), Vector3.UP)
			ec.make_current()
		if _frame == 5 and _cam_mode == "top":
			var cam := Camera3D.new()
			cam.fov = 50.0
			add_child(cam)
			cam.look_at_from_position(Vector3(_focus.x, _dist, _focus.z + 0.01), _focus, Vector3.UP)
			cam.make_current()
		if _frame == 5 and _dist < 29.0 and _cam_mode != "top":
			var rig: Node = get_tree().get_first_node_in_group(&"camera_rig")
			if rig != null and rig.has_method(&"focus_on"):
				rig.call(&"focus_on", _focus, _dist, true)
		if _field != null and _frame % 120 == 0 and _frame >= 360 and OS.get_cmdline_user_args().has("--dep-probe"):
			var line: String = ""
			for c: Vector2 in [Vector2(-1.9, 4.2), Vector2(1.0, 4.6), Vector2(-0.4, 8.2), Vector2(-1.4, 10.8), Vector2(-7.6, 8.6)]:
				line += "%.3f " % float(_field.call(&"depth_at", Vector3(c.x, 0.0, c.y)))
			print("[LiquidWorld] deps f%d %s" % [_frame, line])
		if _field != null and _frame == 10 and OS.get_cmdline_user_args().has("--dep-probe"):
			var gb: PackedByteArray = _field.call(&"_encode_basins", _field.get(&"_drain_bytes"))
			var rs: Vector2i = _field.get(&"res")
			var ar: Rect2 = _field.get(&"area")
			var cl: float = _field.get(&"cell")
			for c: Vector2 in [Vector2(-1.9, 4.2), Vector2(1.0, 4.6), Vector2(-0.4, 8.2), Vector2(-1.4, 10.8), Vector2(-7.6, 8.6)]:
				var i: int = int((c.x - ar.position.x) / cl)
				var j: int = int((c.y - ar.position.y) / cl)
				print("[LiquidWorld] dep %s h %.3f basin %d solid %s" % [c, float(_field.call(&"ground_height", c.x, c.y)), gb[j * rs.x + i], str(_field.call(&"is_solid", c.x, c.y))])
		if _field != null and _ditch_test > 0 and _frame == 10:
			var line: String = ""
			for i: int in 24:
				var x: float = 6.0 + i * 0.5
				line += "%.1f:%.2f%s " % [x, float(_field.call(&"ground_height", x, 0.85)), "S" if bool(_field.call(&"is_solid", x, 0.85)) else ""]
			print("[LiquidWorld] ditch ", line)
			var db: PackedByteArray = _field.get(&"_drain_bytes")
			var rs: Vector2i = _field.get(&"res")
			var row: int = int((0.85 - (_field.get(&"area") as Rect2).position.y) / float(_field.get(&"cell")))
			var tail: String = ""
			for i: int in range(rs.x - 8, rs.x):
				tail += str(db[row * rs.x + i] > 0) + " "
			print("[LiquidWorld] drain row tail ", tail, " lips ", (_field.get(&"_lips") as Dictionary).size())
		if _field != null and _ditch_test > 0 and _frame >= _ditch_test and _frame < _ditch_test + 180:
			var dp := Vector3(7.4, 0.0, 0.85)
			dp.y = float(_field.call(&"ground_height", dp.x, dp.z))
			_field.call(&"add_water", dp, 2.5 / 60.0, Vector3(1.0, 0.0, 0.0), 0.5, 0.0)
		if _field != null and _frame % 60 == 0:
			print("[LiquidWorld] frame %d phase %d vol %.2f drain %.3f max depth %.3f fall at %s" % [_frame, int(_field.get(&"phase")), float(_field.get(&"total_volume")), float(_field.get(&"drained_rate")), float(_field.call(&"max_depth")), str(_field.get(&"_fall_center"))])
		if _seq_frames.has(_frame):
			_save_shot(_frame, _frame == _seq_frames.max())
		return
	if _frame == _auto_trigger and _field != null:
		_field.call(&"trigger")
	if _fx_demo > 0 and _frame == _fx_demo:
		var wfx: Node3D = load("res://scripts/liquid/water_fx.gd").get_or_create(get_tree())
		wfx.call(&"set_night", _night)
		var sy: float = _ground(6.0, -2.0) + 0.02
		wfx.call(&"splash", Vector3(6.0, sy, -2.0), 1.0, sy)
		wfx.call(&"squirt", Vector3(3.0, sy + 1.2, -4.0), Vector3(1.0, 0.6, 0.3), 1.5, sy)
		wfx.call(&"ripple_spray", Vector3(4.0, sy, 0.0), 1.0, sy)
		if _dummy != null:
			wfx.call(&"drip_trail", _dummy, 2.0)
	_update_dummy(delta)
	_update_camera(delta)
	if _bench and (_frame < 150 or _frame > 450):
		pass
	elif _bench:
		_bench_sim.append(float(_field.get(&"last_sim_gpu_ms")) if _field != null else 0.0)
		_bench_frame.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		if _frame % 15 == 0 and _field != null:
			print("[LiquidBench] frame %d phase %d sim %.3f ms frame %.3f ms vol %.2f drain %.2f max depth %.2f" % [_frame, int(_field.get(&"phase")), _bench_sim[-1], _bench_frame[-1], float(_field.get(&"total_volume")), float(_field.get(&"drained_rate")), float(_field.call(&"max_depth"))])
	if _seq_frames.has(_frame):
		_save_shot(_frame, _frame == _seq_frames.max())


## Probe only: rebuilds the real map's field over a larger square area (the WORLD's own terrain builder).
func _swap_world_field() -> void:
	var main: Node = get_child(0)
	var old: Node3D = _field
	var tower_seq: Node = old.get_node_or_null("WaterTowerSequence")
	var tower: Node3D = tower_seq.get(&"_tower") if tower_seq != null else null
	var button: Node3D = tower_seq.get(&"_button") if tower_seq != null else null
	if button != null and button.get_node_or_null("LiquidButtonTrigger") != null:
		button.get_node("LiquidButtonTrigger").free()
	old.remove_from_group(&"liquid_field")
	old.queue_free()
	var area := Rect2(-_world_half, -_world_half, _world_half * 2.0, _world_half * 2.0)
	_field = LiquidFactory.create(area)
	main.add_child(_field)
	var images: Array[Image] = load("res://scripts/world/liquid_terrain.gd").build(area, main.get(&"spawner").get(&"buildings"))
	if OS.get_cmdline_user_args().has("--carve-ditch"):
		# Simulates the WORLD fix: the east ditch continues through the edge lip down to the drain.
		var img: Image = images[0]
		for y: int in img.get_height():
			for x: int in img.get_width():
				var p := area.position + Vector2((x + 0.5) / img.get_width() * area.size.x, (y + 0.5) / img.get_height() * area.size.y)
				if p.x > 6.2 and absf(p.y - 8.5) < 0.9 and images[2].get_pixel(x, y).r < 0.5:
					var t: float = 1.0 - absf(p.y - 8.5) / 0.9
					var u: float = clampf((p.x - 6.2) / 11.8, 0.0, 1.0)
					var d: float = lerpf(0.2, 0.45, u) * t * t * (3.0 - 2.0 * t)
					img.set_pixel(x, y, Color(minf(img.get_pixel(x, y).r, -d), 0, 0))
	_field.call(&"set_terrain", images[0], images[1], images[2])
	if tower != null and OS.get_cmdline_user_args().has("--east-pour"):
		tower.rotation.y = PI * 0.5
	if tower != null:
		_field.call(&"attach_tower", tower, button)
	main.set(&"liquid", _field)
	print("[LiquidWorld] field rebuilt over ", area)


func _save_shot(frame: int, last: bool) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = SHOT_DIR + "%s_%04d.png" % [_seq_name, frame]
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png(path)
	print("[LiquidSandbox] saved ", path)
	if last:
		if _bench and not _bench_sim.is_empty():
			var smax: float = 0.0
			var ssum: float = 0.0
			for v: float in _bench_sim:
				smax = maxf(smax, v)
				ssum += v
			var fmax: float = 0.0
			var fsum: float = 0.0
			for v: float in _bench_frame:
				fmax = maxf(fmax, v)
				fsum += v
			print("[LiquidBench] sim avg %.3f max %.3f ms | frame gpu avg %.3f max %.3f ms" % [ssum / _bench_sim.size(), smax, fsum / _bench_frame.size(), fmax])
		get_tree().quit()


# --- Camera -------------------------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 0.9)
	var shake: float = _trauma * _trauma
	var t: float = Time.get_ticks_msec() / 1000.0
	var jitter := Vector3(_noise.get_noise_2d(t * 25.0, 0.0), _noise.get_noise_2d(0.0, t * 25.0), _noise.get_noise_2d(t * 25.0, 50.0)) * shake
	match _cam_mode:
		"shoulder":
			_camera.fov = 58.0
			var eye := Vector3(-0.6, 1.1, 6.4)
			_camera.look_at_from_position(eye + jitter * 0.12, Vector3(-4.0, 0.55, -2.0), Vector3.UP)
		"shoulder_tower":
			_camera.fov = 58.0
			_camera.look_at_from_position(Vector3(-4.6, 1.15, -1.8) + jitter * 0.12, Vector3(-8.6, 1.4, -7.5), Vector3.UP)
		"edge":
			_camera.fov = 30.0
			_camera.look_at_from_position(Vector3(24.0, 9.0, 3.0) + jitter * 0.5, Vector3(12.5, -1.5, 3.0), Vector3.UP)
		"face":
			_camera.fov = 55.0
			_camera.look_at_from_position(Vector3(3.6, 1.15, 0.6) + jitter * 0.12, Vector3(6.0, 1.0, -2.0), Vector3.UP)
		"top":
			_camera.fov = 40.0
			_camera.look_at_from_position(Vector3(0.0, 46.0, 0.01), Vector3.ZERO, Vector3.UP)
		_:
			_camera.fov = 30.0
			var dir: Vector3 = Basis(Vector3.UP, deg_to_rad(45.0)) * Basis(Vector3.RIGHT, deg_to_rad(-45.0)) * Vector3(0.0, 0.0, 1.0)
			_camera.look_at_from_position(_focus + dir * _dist + jitter * 0.6, _focus + jitter * 0.2, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, jitter.x * 0.03)


func _update_dummy(delta: float) -> void:
	if _dummy == null or _field == null:
		return
	_dummy_t += delta
	var a: float = _dummy_t * 0.7
	var p := Vector3(-2.2 + sin(a) * 1.6, 0.0, 4.0 + sin(a * 2.0) * 1.2)
	var prev: Vector3 = _dummy.position - Vector3(0.0, 0.5, 0.0)
	p.y = _ground(p.x, p.z)
	_dummy.position = p + Vector3(0.0, 0.5, 0.0)
	var vel: Vector3 = (p - prev) / maxf(delta, 1e-4)
	_field.call(&"add_disturbance", p, vel, 0.45)


# --- World --------------------------------------------------------------------------------------

func _ground(x: float, z: float) -> float:
	var s: float = clampf((-(x + z) - 2.0) / 16.0, 0.0, 1.0)
	var h: float = 0.75 * s * s * (3.0 - 2.0 * s)
	var pd: float = Vector2(x - 5.0, z - 6.0).length()
	var pt: float = clampf((3.4 - pd) / 2.2, 0.0, 1.0)
	h -= 0.6 * pt * pt * (3.0 - 2.0 * pt)
	h += (sin(x * 0.9 + 1.3) * cos(z * 0.7 - 0.4)) * 0.03
	var rim: float = maxf(-14.2 - x, -14.2 - z)
	if rim > 0.0:
		h += minf(rim * 2.0, 1.5)
	var edge: float = maxf(x - 12.5, z - 12.5)
	if edge > 0.0:
		h -= minf(edge * 9.0, 3.6)
	return h


func _height_image() -> Image:
	var n: int = 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RF)
	for j: int in n:
		for i: int in n:
			var x: float = _area.position.x + (i + 0.5) * _area.size.x / n
			var z: float = _area.position.y + (j + 0.5) * _area.size.y / n
			img.set_pixel(i, j, Color(_ground(x, z), 0, 0))
	return img


func _drain_image() -> Image:
	var n: int = 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_L8)
	for j: int in n:
		for i: int in n:
			var x: float = _area.position.x + (i + 0.5) * _area.size.x / n
			var z: float = _area.position.y + (j + 0.5) * _area.size.y / n
			img.set_pixel(i, j, Color.WHITE if x > 12.6 or z > 12.6 else Color.BLACK)
	return img


func _solid_image(rects: Array[Rect2]) -> Image:
	var n: int = 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	var px: float = n / _area.size.x
	for r: Rect2 in rects:
		var x0: int = floori((r.position.x - _area.position.x) * px)
		var z0: int = floori((r.position.y - _area.position.y) * px)
		var x1: int = ceili((r.end.x - _area.position.x) * px)
		var z1: int = ceili((r.end.y - _area.position.y) * px)
		img.fill_rect(Rect2i(x0, z0, x1 - x0, z1 - z0), Color.WHITE)
	return img


func _build_ground() -> void:
	var n: int = 220
	var size: float = 40.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step: float = size / n
	for j: int in n + 1:
		for i: int in n + 1:
			var x: float = -size * 0.5 + i * step
			var z: float = -size * 0.5 + j * step
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, _ground(x, z), z))
	for j: int in n:
		for i: int in n:
			var a: int = j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = GROUND_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var hn: int = 161
	hm.map_width = hn
	hm.map_depth = hn
	var data := PackedFloat32Array()
	data.resize(hn * hn)
	for j: int in hn:
		for i: int in hn:
			data[j * hn + i] = _ground(-20.0 + i * 0.25, -20.0 + j * 0.25)
	hm.map_data = data
	shape.shape = hm
	shape.scale = Vector3(0.25, 1.0, 0.25)
	body.add_child(shape)
	add_child(body)

	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ocean.mesh = pm
	ocean.position = Vector3(0.0, -3.25, 0.0)
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.12, 0.5, 0.68, 0.9)
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.roughness = 0.08
	ocean.material_override = om
	add_child(ocean)


func _box(pos: Vector3, size: Vector3, color: Color) -> Rect2:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.position = pos + Vector3(0.0, size.y * 0.5 - 0.3, 0.0)
	return Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)


func _build_obstacles() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var stone := Color("9A938A")
	var wood := Color("A9743F")
	rects.append(_box(Vector3(-4.6, _ground(-4.6, -4.0), -4.0), Vector3(2.2, 1.8, 2.2), wood))
	rects.append(_box(Vector3(1.2, _ground(1.2, -6.5), -6.5), Vector3(1.6, 1.2, 1.6), wood))
	rects.append(_box(Vector3(-8.5, _ground(-8.5, -1.5), -1.5), Vector3(1.2, 1.0, 1.2), wood))
	# Wall along z = 2 with a gate between x = -3.2 and -1.2.
	rects.append(_box(Vector3(-8.1, 0.15, 2.0), Vector3(9.8, 1.3, 0.7), stone))
	rects.append(_box(Vector3(3.9, 0.0, 2.0), Vector3(10.2, 1.3, 0.7), stone))
	return rects


func _build_tower() -> Array[Node3D]:
	var tower: Node3D
	var button: Node3D
	var factory_path: String = "res://scripts/buildings/building_factory.gd"
	if ResourceLoader.exists(factory_path) and FileAccess.get_file_as_string(factory_path).contains("&\"water_tower\""):
		var bf: Script = load(factory_path)
		tower = bf.call(&"create", &"water_tower")
		button = bf.call(&"create", &"water_button")
	else:
		tower = _proxy_tower()
		button = _proxy_button()
	add_child(tower)
	tower.position = Vector3(-9.0, _ground(-9.0, -9.0), -9.0)
	add_child(button)
	button.position = Vector3(-12.0, _ground(-12.0, -5.5), -5.5)
	return [tower, button]


func _proxy_tower() -> Node3D:
	var root := Node3D.new()
	root.name = "WaterTowerProxy"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("8B5A2B")
	wood.roughness = 0.9
	for c: Vector2 in [Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(-1.1, 1.1), Vector2(1.1, 1.1)]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.28, 3.0, 0.28)
		leg.mesh = lm
		leg.material_override = wood
		leg.position = Vector3(c.x, 1.5, c.y)
		root.add_child(leg)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.8, 0.2, 2.8)
	deck.mesh = dm
	deck.material_override = wood
	deck.position = Vector3(0.0, 3.0, 0.0)
	root.add_child(deck)
	var pivot := Node3D.new()
	pivot.name = "TankPivot"
	pivot.position = Vector3(0.0, 3.1, 1.15)
	root.add_child(pivot)
	var tank := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 1.05
	tm.bottom_radius = 0.95
	tm.height = 1.5
	tm.cap_top = false
	tank.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("B98A52")
	tmat.roughness = 0.8
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tank.material_override = tmat
	tank.position = Vector3(0.0, 0.75, -1.05)
	pivot.add_child(tank)
	for y: float in [0.25, 1.3]:
		var band := MeshInstance3D.new()
		var bm := TorusMesh.new()
		bm.inner_radius = 0.97 + y * 0.06
		bm.outer_radius = 1.07 + y * 0.06
		band.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color("5A5550")
		bmat.metallic = 0.6
		band.material_override = bmat
		band.position = Vector3(0.0, y, -1.05)
		pivot.add_child(band)
	var fill := MeshInstance3D.new()
	fill.name = "FillSurface"
	var fm := CylinderMesh.new()
	fm.top_radius = 1.0
	fm.bottom_radius = 1.0
	fm.height = 0.02
	fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.65, 0.8)
	fmat.roughness = 0.05
	fill.material_override = fmat
	fill.position = Vector3(0.0, 1.38, -1.05)
	pivot.add_child(fill)
	var pour := Marker3D.new()
	pour.name = "PourPoint"
	pour.position = Vector3(0.0, 1.5, -0.05)
	pivot.add_child(pour)
	return root


func _proxy_button() -> Node3D:
	var root := Node3D.new()
	root.name = "WaterButtonProxy"
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.42
	bm.bottom_radius = 0.48
	bm.height = 0.12
	base.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6E6A64")
	base.material_override = gm
	base.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(base)
	var cap := MeshInstance3D.new()
	cap.name = "ButtonCap"
	var sm := SphereMesh.new()
	sm.radius = 0.34
	sm.height = 0.3
	sm.is_hemisphere = true
	cap.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("D8452E")
	cm.roughness = 0.4
	cap.material_override = cm
	cap.position = Vector3(0.0, 0.12, 0.0)
	root.add_child(cap)
	return root


func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.45
	_env.ambient_light_color = Color("D9D3C6")
	_env.ambient_light_energy = 0.5
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 0.95
	_env.tonemap_white = 6.0
	_env.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.ssao_radius = 1.1
	_env.ssao_intensity = 1.6
	_env.ssao_power = 1.6
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_hdr_threshold = 2.2
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color("FFF0D2")
	_sun.light_energy = 1.55
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3(-0.85, 1.05, 0.38) * 30.0, Vector3.ZERO, Vector3.UP)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("9DB4FF")
	_moon.shadow_enabled = true
	add_child(_moon)
	_moon.look_at_from_position(Vector3(0.55, 0.85, -0.6) * 30.0, Vector3.ZERO, Vector3.UP)


func _apply_night() -> void:
	var t: float = _night
	_sun.light_energy = 1.55 * (1.0 - t)
	_sun.visible = t < 0.99
	_moon.light_energy = 0.95 * t
	_moon.visible = t > 0.01
	_env.ambient_light_color = Color("D9D3C6").lerp(Color("2D5A70"), t)
	_env.ambient_light_energy = lerpf(0.5, 0.9, t)
	_env.ambient_light_sky_contribution = lerpf(0.45, 0.15, t)
	_env.adjustment_enabled = true
	_env.adjustment_saturation = lerpf(1.05, 0.72, t)
	_moon.light_energy = 0.6 * t
	_env.tonemap_exposure = lerpf(0.95, 1.2, t)
	_env.glow_hdr_threshold = lerpf(2.2, 0.9, t)
	_sky_mat.sky_top_color = Color("3C8CE6").lerp(Color("0B1A2E"), t)
	_sky_mat.sky_horizon_color = Color("C7E6F2").lerp(Color("24455A"), t)
	_sky_mat.ground_horizon_color = Color("C7E6F2").lerp(Color("24455A"), t)
	_sky_mat.ground_bottom_color = Color("2A7FA8").lerp(Color("081420"), t)
	if _field != null:
		_field.call(&"set_night", t)
