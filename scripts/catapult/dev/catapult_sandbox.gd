extends Node3D

## Catapult test bed: ground that ends before the far landing zone (counts as ocean), obstacles on the
## nominal landing spot, art-direction lighting, an isometric follow camera with trauma, the real
## catapult/player when they implement the contract, else the proxy/stand-in.
## A stand-in pond (pit with a layer-1 floor, water_body stub, Marker3D in group catapult_target) is the landing target unless --no-pond.
## User args: --auto-mount=<physics frame>, --cam=game|wide|close, --stand-in, --proxy, --seed=<n>, --no-pond, --touch.

const CatapultFactory := preload("res://scripts/catapult/catapult_factory.gd")
const Proxy := preload("res://scripts/catapult/dev/catapult_proxy.gd")
const StandIn := preload("res://scripts/catapult/dev/catapult_stand_in.gd")
const T := preload("res://scripts/catapult/catapult_tuning.gd")
const WaterStub := preload("res://scripts/catapult/dev/catapult_water_stub.gd")

const PLAYER_FACTORY_PATH: String = "res://scripts/character/player_factory.gd"
const CAM_YAW_DEG: float = 45.0
const CAM_PITCH_DEG: float = -45.0
const CAM_FOV: float = 30.0
const CAM_DISTANCES: Dictionary = {"close": 16.0, "game": 30.0, "wide": 52.0}
const GROUND_RECT: Rect2 = Rect2(-18.0, -14.0, 36.0, 34.5)
const PLAYER_START := Vector3(2.4, 0.05, -0.6)
const POND_CENTER := Vector3(6.0, 0.0, 16.0)
const POND_HALF: float = 2.6
const POND_SURFACE_Y: float = -0.08
const POND_DEPTH: float = 0.7
const TRAUMA_DECAY: float = 1.5
const SHAKE_OFFSET: float = 0.9
const SHAKE_ROLL_DEG: float = 2.5

var _player: Node3D
var _catapult: Node3D
var _controller: Node
var _camera: Camera3D
var _cam_distance: float = 30.0
var _cam_focus := Vector3.ZERO
var _trauma: float = 0.0
var _clock: float = 0.0
var _auto_mount: int = -1
var _physics_frame: int = 0
var _mat_cache: Dictionary = {}
var _flight_target := Vector3.INF


func _ready() -> void:
	add_to_group(T.CAMERA_GROUP)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = -1
	var force_stand_in: bool = args.has("--stand-in")
	var force_proxy: bool = args.has("--proxy")
	for arg: String in args:
		if arg.begins_with("--auto-mount="):
			_auto_mount = arg.trim_prefix("--auto-mount=").to_int()
		elif arg.begins_with("--cam="):
			_cam_distance = CAM_DISTANCES.get(arg.trim_prefix("--cam="), _cam_distance)
		elif arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
	_ensure_interact_action()
	_build_environment()
	var with_pond: bool = not args.has("--no-pond")
	_build_ground(with_pond)
	_build_obstacles()
	if with_pond:
		_build_pond()

	_catapult = _create_catapult(force_proxy)
	add_child(_catapult)
	_controller = CatapultFactory.attach(_catapult)
	if seed_value >= 0:
		(_controller.get(&"rng") as RandomNumberGenerator).seed = seed_value
	_controller.connect(&"fired", _on_fired)
	if args.has("--touch"):
		_controller.get_node(^"CatapultPrompt").call(&"set_touch", true)

	_player = _create_player(force_stand_in)
	add_child(_player)
	if _player.has_method(&"teleport"):
		_player.call(&"teleport", PLAYER_START)
	else:
		_player.global_position = PLAYER_START
	if _player.has_signal(&"launch_landed"):
		_player.connect(&"launch_landed", _on_landed)

	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_camera.near = 0.3
	_camera.far = 300.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_cam_focus = _focus_target()
	_place_camera(0.0)


func _on_fired(target: Vector3) -> void:
	_flight_target = target
	print("[CatapultSandbox] fired -> %s" % target)


func _on_landed(pos: Vector3) -> void:
	_flight_target = Vector3.INF
	print("[CatapultSandbox] landed at %s" % pos)
	# Stands in for the WORLD pond ripples.
	for w: Node in get_tree().get_nodes_in_group(&"water_body"):
		if float(w.call(&"surface_height_at", pos)) > -INF:
			w.call(&"splash", pos, 1.0)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	_physics_frame += 1
	if _physics_frame == _auto_mount:
		print("[CatapultSandbox] auto-mount at frame %d -> %s" % [_physics_frame, _controller.call(&"try_mount")])


func _process(delta: float) -> void:
	_clock += delta
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_place_camera(delta)


func _focus_target() -> Vector3:
	var pos: Vector3 = _player.get_global_transform_interpolated().origin
	# Keep the catapult in frame while the player stands by it; follow the player in flight.
	if pos.distance_to(_catapult.global_position) < 4.0:
		var mid: Vector3 = _catapult.global_position.lerp(pos, 0.5)
		return Vector3(mid.x, 0.8, mid.z)
	if _flight_target.is_finite():
		# Frame both the flying body and its landing marker.
		return pos.lerp(_flight_target, 0.45)
	return pos


func _place_camera(delta: float) -> void:
	var target: Vector3 = _focus_target()
	_cam_focus = target if delta <= 0.0 else _cam_focus.lerp(target, 1.0 - exp(-7.0 * delta))
	var y: float = deg_to_rad(CAM_YAW_DEG)
	var pitch: float = deg_to_rad(CAM_PITCH_DEG)
	var dir := Vector3(cos(-pitch) * sin(y), sin(-pitch), cos(-pitch) * cos(y))
	var shake: float = _trauma * _trauma
	var offset := Vector3(
		sin(_clock * 37.0) + sin(_clock * 61.0) * 0.5,
		sin(_clock * 43.0 + 1.7) + sin(_clock * 71.0) * 0.5,
		sin(_clock * 53.0 + 0.6)) * SHAKE_OFFSET * shake * 0.66
	var xf := Transform3D(Basis.looking_at(-dir, Vector3.UP), _cam_focus + dir * _cam_distance + offset)
	xf.basis = xf.basis.rotated(xf.basis.z, deg_to_rad(SHAKE_ROLL_DEG) * shake * sin(_clock * 47.0))
	_camera.global_transform = xf


func _create_catapult(force_proxy: bool) -> Node3D:
	if not force_proxy and ResourceLoader.exists(T.BUILDING_FACTORY_PATH):
		var factory: Script = load(T.BUILDING_FACTORY_PATH) as Script
		var footprints: Variant = factory.get_script_constant_map().get("_FOOTPRINTS", {})
		if footprints is Dictionary and (footprints as Dictionary).has(&"catapult"):
			var real: Node3D = factory.call(&"create", &"catapult") as Node3D
			if real != null and real.has_node(^"ArmPivot/Seat"):
				print("[CatapultSandbox] using building_factory catapult")
				return real
			if real != null:
				real.free()
	print("[CatapultSandbox] using proxy catapult")
	return Proxy.build()


func _create_player(force_stand_in: bool) -> Node3D:
	if not force_stand_in and ResourceLoader.exists(PLAYER_FACTORY_PATH):
		var factory: Script = load(PLAYER_FACTORY_PATH) as Script
		var body: Node3D = factory.call(&"create") as Node3D
		if body != null and body.has_method(&"mount") and body.has_method(&"launch") and body.has_method(&"launch_gravity"):
			print("[CatapultSandbox] using the real player")
			return body
		if body != null:
			body.free()
	print("[CatapultSandbox] using the stand-in player")
	return StandIn.new()


func _ensure_interact_action() -> void:
	if InputMap.has_action(T.INTERACT_ACTION):
		return
	InputMap.add_action(T.INTERACT_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	InputMap.action_add_event(T.INTERACT_ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	InputMap.action_add_event(T.INTERACT_ACTION, pad)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4F9BE8")
	sky_mat.sky_horizon_color = Color("BFE6F5")
	sky_mat.ground_bottom_color = Color("2A8CB0")
	sky_mat.ground_horizon_color = Color("BFE6F5")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# SSAO exists only in Forward+.
	env.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("FFF0D2")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# High, from the screen's top-left-back (camera looks from +X+Z toward the origin).
	sun.look_at_from_position(Vector3(-0.85, 1.05, 0.38) * 30.0, Vector3.ZERO, Vector3.UP)


func _build_ground(with_pond: bool) -> void:
	var ocean := MeshInstance3D.new()
	var sea := PlaneMesh.new()
	sea.size = Vector2(300.0, 300.0)
	ocean.mesh = sea
	ocean.position.y = -0.6
	ocean.material_override = _mat(Color("2A8CB0"))
	add_child(ocean)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = T.GROUND_LAYER
	ground.collision_mask = 0
	add_child(ground)
	var r: Rect2 = GROUND_RECT
	var rects: Array[Rect2] = [r]
	if with_pond:
		# Ground around a rectangular pit for the pond.
		var hole := _pond_rect()
		rects = [
			Rect2(r.position.x, r.position.y, r.size.x, hole.position.y - r.position.y),
			Rect2(r.position.x, hole.end.y, r.size.x, r.end.y - hole.end.y),
			Rect2(r.position.x, hole.position.y, hole.position.x - r.position.x, hole.size.y),
			Rect2(hole.end.x, hole.position.y, r.end.x - hole.end.x, hole.size.y),
		]
	for rect: Rect2 in rects:
		_ground_box(ground, Vector3(rect.get_center().x, -0.5, rect.get_center().y), Vector3(rect.size.x, 1.0, rect.size.y), Color("7CC243"))
	for i: int in 3:
		var patch := BoxMesh.new()
		patch.size = Vector3(2.4 + i, 0.02, 1.8 + i * 0.5)
		var pm := MeshInstance3D.new()
		pm.mesh = patch
		pm.position = Vector3(-6.0 + i * 4.5, 0.01, 4.0 + i * 3.2)
		pm.material_override = _mat(Color("D9B27C"))
		ground.add_child(pm)


func _ground_box(body: StaticBody3D, center: Vector3, size: Vector3, color: Color) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	body.add_child(col)
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = center
	mi.material_override = _mat(color)
	body.add_child(mi)


func _pond_rect() -> Rect2:
	return Rect2(POND_CENTER.x - POND_HALF, POND_CENTER.z - POND_HALF, POND_HALF * 2.0, POND_HALF * 2.0)


## Pit with a layer-1 floor POND_DEPTH under the surface, the water_body stub and the catapult_target marker.
func _build_pond() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "PondFloor"
	floor_body.collision_layer = T.GROUND_LAYER
	floor_body.collision_mask = 0
	add_child(floor_body)
	var floor_top: float = POND_SURFACE_Y - POND_DEPTH
	_ground_box(floor_body, Vector3(POND_CENTER.x, floor_top - 0.25, POND_CENTER.z), Vector3(POND_HALF * 2.0, 0.5, POND_HALF * 2.0), Color("2E6F8E"))
	var water: MeshInstance3D = WaterStub.new(Vector2(POND_HALF * 2.0, POND_HALF * 2.0))
	water.position = Vector3(POND_CENTER.x, POND_SURFACE_Y, POND_CENTER.z)
	add_child(water)
	var marker := Marker3D.new()
	marker.name = "CatapultTarget"
	marker.add_to_group(&"catapult_target")
	marker.set_meta(&"radius", POND_HALF - 0.4)
	marker.position = Vector3(POND_CENTER.x, POND_SURFACE_Y, POND_CENTER.z)
	add_child(marker)


func _build_obstacles() -> void:
	# A hut right on the nominal landing spot and crates around it force the landing search.
	_obstacle(Vector3(0.0, 0.0, 19.5), Vector3(3.2, 2.6, 3.2), Color("C2BBAE"))
	_obstacle(Vector3(0.0, 2.6, 19.5), Vector3(3.6, 0.6, 3.6), Color("D8452E"))
	for pos: Vector3 in [Vector3(3.2, 0.0, 17.0), Vector3(-3.4, 0.0, 16.5), Vector3(-1.5, 0.0, 15.2), Vector3(5.0, 0.0, 6.0), Vector3(-4.5, 0.0, 3.0)]:
		_obstacle(pos, Vector3(1.0, 1.0, 1.0), Color("A8693A"))
	_obstacle(Vector3(-2.0, 0.0, 9.0), Vector3(3.0, 4.0, 3.0), Color("E8DCC4"))
	_obstacle(Vector3(-2.0, 4.0, 9.0), Vector3(3.4, 0.7, 3.4), Color("3E7FD1"))
	_obstacle(Vector3(3.0, 0.0, 11.5), Vector3(2.4, 3.0, 2.4), Color("E8DCC4"))
	_obstacle(Vector3(3.0, 3.0, 11.5), Vector3(2.8, 0.6, 2.8), Color("D8452E"))
	# Catapult base collider, like the world's building bodies.
	_obstacle(Vector3(0.0, 0.0, 0.0), Vector3(2.6, 0.4, 3.0), Color(0, 0, 0, 0), false)


func _obstacle(base: Vector3, size: Vector3, color: Color, visible_mesh: bool = true) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = T.OBSTACLE_LAYER
	body.collision_mask = 0
	body.position = base + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	if not visible_mesh:
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mat_cache[key] = m
	return _mat_cache[key]
