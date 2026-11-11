extends Node3D

## Standalone test bed for the player: grass floor with dirt/wood/stone patches, layer-2 crates,
## a town-hall-sized block for scale, world-like lighting and a follow camera. Physics interpolation is on.
## User args: --sandbox-water, --cam=detail|close|game|far|third|shoulder|front|side|back|tq_front|tq_back|face_track, --sandbox-bump,
## --launch-demo, --sandbox-pond, --sfx-export=<abs dir>, --freeze-at=<seconds>, --no-interp, plus the player's own (--player-demo, --step-log).

const PlayerFactory := preload("res://scripts/character/player_factory.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Ground := preload("res://scripts/character/dev/sandbox_ground.gd")
const Liquid := preload("res://scripts/character/dev/sandbox_liquid.gd")
const Catapult := preload("res://scripts/character/dev/sandbox_catapult.gd")
const Pond := preload("res://scripts/character/dev/sandbox_pond.gd")

const CAM_YAW_DEG: float = 45.0
const CAM_PITCH_DEG: float = -45.0
const CAM_FOV: float = 30.0
const CAM_DISTANCES: Dictionary = {"detail": 4.0, "close": 9.0, "game": 30.0, "far": 60.0}
# Follow modes relative to the player's facing: [distance, height, lateral, fov, look height, orbit deg].
const CAM_FOLLOW: Dictionary = {
	"third": [4.5, 2.0, 0.0, 58.0, 0.7, 0.0],
	"shoulder": [1.6, 1.05, 0.45, 55.0, 0.95, 0.0],
	"front": [2.2, 0.95, 0.0, 40.0, 0.62, 180.0],
	"side": [2.2, 0.9, 0.0, 40.0, 0.55, 90.0],
	"back": [2.2, 1.0, 0.0, 40.0, 0.6, 0.0],
	"tq_front": [2.3, 1.05, 0.0, 40.0, 0.62, 140.0],
	"tq_back": [2.3, 1.1, 0.0, 40.0, 0.62, 40.0],
}

var _player: CharacterBody3D
var _camera: Camera3D
var _cam_mode: String = "close"
var _cam_distance: float = 9.0
var _cam_focus := Vector3.ZERO
var _cam_yaw: float = 0.0
var _mat_cache: Dictionary = {}
var _freeze_at: float = -1.0
var _count_frames: int = 0
var _sim_time: float = 0.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	get_tree().physics_interpolation = not args.has("--no-interp")
	for arg: String in args:
		if arg.begins_with("--cam="):
			_cam_mode = arg.trim_prefix("--cam=")
			_cam_distance = CAM_DISTANCES.get(_cam_mode, _cam_distance)
		elif arg == "--count-meshes":
			_count_frames = 10
		elif arg.begins_with("--freeze-at="):
			_freeze_at = arg.trim_prefix("--freeze-at=").to_float()
		elif arg.begins_with("--sfx-export="):
			var dir: String = arg.trim_prefix("--sfx-export=").trim_prefix("'").trim_suffix("'")
			print("[Sandbox] exported %d sfx samples to %s" % [Sfx.export_samples(dir), dir])
	_build_environment()
	_build_ground()
	_build_obstacles(args.has("--sandbox-bump"))
	if args.has("--sandbox-water"):
		var liquid: Node3D = Liquid.new()
		liquid.name = "Liquid"
		add_child(liquid)
	_player = PlayerFactory.create()
	add_child(_player)
	_player.call(&"teleport", Vector3(0.0, 0.05, 0.0))
	if args.has("--sandbox-pond"):
		_build_pond(Vector3(-8.0, 0.0, 4.0))
	if args.has("--launch-demo"):
		var cat: Node3D = Catapult.new()
		cat.name = "Catapult"
		cat.position = Vector3(1.5, 0.0, 4.0)
		if args.has("--sandbox-water"):
			cat.position = Vector3(-6.0, 0.0, 0.0)
			cat.set(&"throw_dir", Vector3(1.0, 0.0, 0.0))
			cat.set(&"target", Vector3(2.9, 0.0, 0.0))
		add_child(cat)
		cat.set(&"player", _player)
		_player.call(&"teleport", cat.position + Vector3(0.6, 0.05, 1.2))
		if args.has("--step-log"):
			_player.connect(&"launch_landed", func(p: Vector3) -> void: print("[Sandbox] launch_landed %s" % p))
			_player.connect(&"control_restored", func() -> void: print("[Sandbox] control_restored"))
	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_camera.near = 0.05 if CAM_FOLLOW.has(_cam_mode) or _cam_mode == "face_track" else 0.3
	_camera.far = 300.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_cam_focus = _player.global_position
	_cam_yaw = _player_yaw()
	_place_camera(1.0)


func _process(delta: float) -> void:
	if _player != null:
		_place_camera(delta)
		if _count_frames > 0:
			_count_frames -= 1
			if _count_frames == 0:
				_print_mesh_count()


## --count-meshes: prints the player's MeshInstance3D count (total, visible, shadow casters).
func _print_mesh_count() -> void:
	var total: int = 0
	var visible: int = 0
	var casters: int = 0
	for n: Node in _player.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		total += 1
		if mi.is_visible_in_tree():
			visible += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
	print("[Sandbox] player meshes total=%d visible=%d visible_shadow_casters=%d draws~%d" % [total, visible, casters, visible + casters])


## --freeze-at=<s> stops simulated time so screenshots catch an exact moment of the demo.
func _physics_process(delta: float) -> void:
	_sim_time += delta
	if _freeze_at > 0.0 and _sim_time >= _freeze_at:
		Engine.time_scale = 0.0
		_freeze_at = -1.0


## Cuts a hole in the sandbox floor around `center` and drops the pond stand-in into it.
func _build_pond(center: Vector3) -> void:
	var ground: Node = get_node("Ground")
	for child: Node in ground.get_children():
		if child is CollisionShape3D or (child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh):
			child.queue_free()
	var half: Vector2 = Pond.HALF
	var rects: Array[Rect2] = [
		Rect2(-20.0, -20.0, 40.0, center.z - half.y + 20.0),
		Rect2(-20.0, center.z + half.y, 40.0, 20.0 - center.z - half.y),
		Rect2(-20.0, center.z - half.y, center.x - half.x + 20.0, half.y * 2.0),
		Rect2(center.x + half.x, center.z - half.y, 20.0 - center.x - half.x, half.y * 2.0),
	]
	for r: Rect2 in rects:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 1.0, r.size.y)
		cs.shape = box
		cs.position = Vector3(r.get_center().x, -0.5, r.get_center().y)
		ground.add_child(cs)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		mi.material_override = _mat(Color("7CC243"))
		mi.position = Vector3(r.get_center().x, 0.0, r.get_center().y)
		ground.add_child(mi)
	var pond: Node3D = Pond.new()
	pond.name = "Pond"
	pond.position = center
	add_child(pond)


func _player_yaw() -> float:
	return _player.call(&"get_facing_yaw")


func _place_camera(delta: float) -> void:
	var pos: Vector3 = _player.get_global_transform_interpolated().origin
	if _cam_mode == "face_track":
		# Frames the face from the front: stable movement yaw on the ground, the head's real facing while tumbling.
		var yaw_f: float = _player_yaw()
		var fwd_f := Vector3(sin(yaw_f), 0.0, cos(yaw_f))
		var head_node: Node3D = (_player.get(&"rig") as Node3D).find_child("Head", true, false) as Node3D
		var head: Vector3 = pos + Vector3.UP * 0.75
		if head_node != null:
			head = head_node.global_position + Vector3.UP * 0.15
			var face: Vector3 = head_node.global_basis.z.normalized()
			if _player.call(&"is_launched"):
				fwd_f = face
		var side_f := Vector3(fwd_f.z, 0.0, -fwd_f.x)
		var eye_f: Vector3 = head + fwd_f * 2.2 + side_f * 0.5 + Vector3.UP * 0.35
		_camera.fov = 40.0
		_camera.global_transform = Transform3D(Basis.looking_at(head - eye_f, Vector3.UP), eye_f)
		return
	if CAM_FOLLOW.has(_cam_mode):
		var cfg: Array = CAM_FOLLOW[_cam_mode]
		_cam_yaw = lerp_angle(_cam_yaw, _player_yaw(), 1.0 - exp(-3.0 * delta))
		var yaw: float = _cam_yaw + deg_to_rad(cfg[5])
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		_cam_focus = _cam_focus.lerp(pos, 1.0 - exp(-12.0 * delta))
		var eye: Vector3 = _cam_focus - fwd * float(cfg[0]) + Vector3.UP * float(cfg[1]) - right * float(cfg[2])
		var look: Vector3 = _cam_focus + Vector3.UP * float(cfg[4]) - right * float(cfg[2])
		if _cam_mode == "shoulder" or _cam_mode == "third":
			look += fwd * 2.0
		_camera.fov = float(cfg[3])
		_camera.global_transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
		return
	var target := Vector3(pos.x, pos.y + 0.4, pos.z)
	_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-8.0 * delta))
	var y: float = deg_to_rad(CAM_YAW_DEG)
	var pitch: float = deg_to_rad(CAM_PITCH_DEG)
	var dir := Vector3(cos(-pitch) * sin(y), sin(-pitch), cos(-pitch) * cos(y))
	_camera.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), _cam_focus + dir * _cam_distance)


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
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.ssao_enabled = RenderingServer.get_current_rendering_method() != "mobile"
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("FFF0D2")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 1.2
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	sun.look_at_from_position(Vector3(-0.85, 1.05, 0.38) * 30.0, Vector3.ZERO, Vector3.UP)


func _build_ground() -> void:
	var ground: StaticBody3D = Ground.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 1.0, 40.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	ground.add_child(col)
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _mat(Color("7CC243"))
	ground.add_child(mi)

	var patches: Array[Dictionary] = [
		{"surface": &"dirt", "rect": Rect2(-4.4, -1.6, 2.4, 3.2), "color": Color("D9B27C")},
		{"surface": &"wood", "rect": Rect2(2.0, -1.6, 2.4, 3.2), "color": Color("A8693A")},
		{"surface": &"stone", "rect": Rect2(-0.9, -0.9, 1.8, 1.8), "color": Color("C2BBAE")},
	]
	ground.patches = patches
	for p: Dictionary in patches:
		var r: Rect2 = p["rect"]
		var box := BoxMesh.new()
		box.size = Vector3(r.size.x, 0.04, r.size.y)
		var pm := MeshInstance3D.new()
		pm.mesh = box
		pm.material_override = _mat(p["color"])
		pm.position = Vector3(r.get_center().x, 0.0, r.get_center().y)
		ground.add_child(pm)
		if p["surface"] == &"wood":
			for k: int in 6:
				var gap := BoxMesh.new()
				gap.size = Vector3(0.03, 0.045, r.size.y)
				var gm := MeshInstance3D.new()
				gm.mesh = gap
				gm.material_override = _mat(Color("7A4A28"))
				gm.position = Vector3(r.position.x + (k + 0.5) * r.size.x / 6.0, 0.0, r.get_center().y)
				ground.add_child(gm)


func _build_obstacles(bump: bool) -> void:
	var crates: Array[Vector3] = [Vector3(5.5, 0.0, 3.0), Vector3(-5.0, 0.0, 3.5), Vector3(1.0, 0.0, -4.5), Vector3(6.0, 0.0, -2.5)]
	if bump:
		crates.append(Vector3(4.2, 0.0, 0.0))
		crates.append(Vector3(-4.2, 0.0, 0.0))
	for pos: Vector3 in crates:
		_obstacle(pos, Vector3(1.0, 1.0, 1.0), Color("A8693A"))
	_obstacle(Vector3(-7.0, 0.0, -6.5), Vector3(3.0, 4.0, 3.0), Color("C2BBAE"))
	_obstacle(Vector3(-7.0, 4.0, -6.5), Vector3(3.4, 0.6, 3.4), Color("D8452E"))


func _obstacle(base: Vector3, size: Vector3, color: Color) -> void:
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


func _mat(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mat_cache[key] = m
	return _mat_cache[key]
