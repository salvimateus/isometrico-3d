extends Node3D
## Dev gallery: every kind plus a wall run, lit like the game. `-- --focus=<kind>` or `--focus=walls` for close-ups.

const Factory = preload("res://scripts/buildings/building_factory.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Kit = preload("res://scripts/buildings/mesh_kit.gd")

const FOV: float = 30.0
const YAW_DEG: float = 45.0
const PITCH_DEG: float = -45.0

const WALL_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
	Vector2i(4, 1), Vector2i(4, 2), Vector2i(2, 1), Vector2i(2, 2), Vector2i(6, 1),
]


var _orbit_deg: float = 0.0
var _low: bool = false
var _night: bool = false
var _tip: float = 0.0
var _fire: float = 0.0


func _ready() -> void:
	var focus: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--focus="):
			focus = arg.trim_prefix("--focus=")
		elif arg.begins_with("--orbit="):
			_orbit_deg = arg.trim_prefix("--orbit=").to_float()
		elif arg.begins_with("--low="):
			_low = arg.trim_prefix("--low=").to_int() != 0
		elif arg.begins_with("--fire="):
			_fire = clampf(arg.trim_prefix("--fire=").to_float(), 0.0, 1.0)
		elif arg.begins_with("--tip="):
			_tip = clampf(arg.trim_prefix("--tip=").to_float(), 0.0, 1.0)
		elif arg.begins_with("--night="):
			_night = arg.trim_prefix("--night=").to_int() != 0
	_setup_lighting()
	_add_ground()
	Factory.set_night(get_tree(), 1.0 if _night else 0.0)
	if focus.is_empty():
		_layout_all()
	elif focus == "walls":
		_add_walls(Vector3(-3.0, 0.0, -1.0))
		if _low:
			_add_low_camera(Vector3(-1.0, 0.6, 0.0), 3.5)
		else:
			_add_camera(Vector3(0.0, 0.3, 0.0), 13.0)
	else:
		var kind := StringName(focus)
		var node: Node3D = Factory.create(kind)
		add_child(node)
		_apply_tip(node)
		_add_tile_marker(Vector3.ZERO, Factory.footprint(kind))
		var fp: Vector2i = Factory.footprint(kind)
		var box: AABB = _visual_aabb(node)
		var height: float = box.end.y
		if _low:
			_add_low_camera(Vector3(0.0, minf(0.5 + fp.x * 0.25, height * 0.45), 0.0), fp.x * 0.5)
		else:
			_add_camera(Vector3(0.0, height * 0.42, 0.0), maxf(2.2 * fp.x + 4.0, height * 2.6 + 2.0))


func _layout_all() -> void:
	var right := Vector3(1.0, 0.0, -1.0).normalized()
	var down := Vector3(1.0, 0.0, 1.0).normalized()
	var rows: Array = [
		[&"archer_tower", &"town_hall", &"cannon"],
		[&"gold_mine", &"gold_storage", &"barracks"],
		[&"mana_collector", &"mana_storage", &"builder_hut"],
		[&"water_button", &"water_tower", &"catapult"],
	]
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			if row[c] == null:
				continue
			var kind: StringName = row[c]
			var pos: Vector3 = right * (c - 1) * 5.4 + down * ((r - 1) * 5.4 + (2.5 if r == 3 else 0.0))
			var node: Node3D = Factory.create(kind)
			node.position = pos
			add_child(node)
			_apply_tip(node)
			_add_tile_marker(pos, Factory.footprint(kind))
	_add_walls(down * 16.0 + right * -3.5)
	_add_camera(down * 5.5, 44.0)


func _visual_aabb(node: Node) -> AABB:
	var box := AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Tips the water tower tub: 0 = resting, 1 = 110 degrees toward +Z.
func _apply_tip(node: Node3D) -> void:
	var pivot := node.find_child("TankPivot", true, false) as Node3D
	if pivot != null:
		pivot.rotation.x = deg_to_rad(110.0 * _tip)
	var arm := node.find_child("ArmPivot", true, false) as Node3D
	if arm != null:
		arm.rotation.x = deg_to_rad(float(node.get_meta(&"fire_angle_deg", 110.0)) * _fire)


func _add_walls(origin: Vector3) -> void:
	var cells: Dictionary = {}
	for c: Vector2i in WALL_CELLS:
		cells[c] = true
	for c: Vector2i in WALL_CELLS:
		var mask: int = 0
		if cells.has(c + Vector2i(1, 0)):
			mask |= 1
		if cells.has(c + Vector2i(-1, 0)):
			mask |= 2
		if cells.has(c + Vector2i(0, 1)):
			mask |= 4
		if cells.has(c + Vector2i(0, -1)):
			mask |= 8
		var w: Node3D = Factory.create_wall(mask)
		w.position = origin + Vector3(c.x, 0.0, c.y)
		add_child(w)


func _add_tile_marker(pos: Vector3, fp: Vector2i) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(fp.x, fp.y) - Vector2(0.06, 0.06)
	mi.mesh = pm
	mi.material_override = Mat.solid(Mat.GRASS_DARK, 1.0)
	mi.position = pos + Vector3(0.0, 0.004, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	mi.mesh = pm
	mi.material_override = Mat.solid(Color("3f6a3a") if _night else Mat.GRASS, 1.0)
	add_child(mi)


func _add_camera(target: Vector3, distance: float) -> void:
	var cam := Camera3D.new()
	cam.fov = FOV
	var yaw: float = deg_to_rad(YAW_DEG + _orbit_deg)
	var pitch: float = deg_to_rad(PITCH_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	cam.position = target + dir * distance
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true


## Over-the-shoulder view: eye ~1.3 units high, ~2.5 units from the building's edge.
func _add_low_camera(target: Vector3, half_extent: float) -> void:
	var cam := Camera3D.new()
	cam.fov = 60.0
	var yaw: float = deg_to_rad(YAW_DEG + _orbit_deg)
	var horizontal := Vector3(sin(yaw), 0.0, cos(yaw))
	cam.position = Vector3(0.0, 1.3, 0.0) + horizontal * (half_extent + 2.5)
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d2")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 1.2
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Light travels toward screen right-down: arrives from -X (screen left-back) and slightly +Z.
	var travel := Vector3(1.5, -2.1, -0.55).normalized()
	sun.basis = Basis.looking_at(travel, Vector3.UP)
	if _night:
		sun.light_color = Color("8fa6ff")
		sun.light_energy = 0.32
		sun.basis = Basis.looking_at(Vector3(1.2, -2.0, -0.9).normalized(), Vector3.UP)
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4f8fe0")
	sky_mat.sky_horizon_color = Color("bfe0f5")
	sky_mat.ground_horizon_color = Color("bfe0f5")
	sky_mat.ground_bottom_color = Color("6a9a4a")
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("dfe8f2")
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# SSAO exists only on Forward+ / Compatibility.
	env.ssao_enabled = RenderingServer.get_current_rendering_method() != "mobile"
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	if _night:
		sky_mat.sky_top_color = Color("0b1430")
		sky_mat.sky_horizon_color = Color("27365e")
		sky_mat.ground_horizon_color = Color("27365e")
		sky_mat.ground_bottom_color = Color("0d1a14")
		env.ambient_light_color = Color("3b4f8a")
		env.ambient_light_sky_contribution = 0.4
		env.ambient_light_energy = 0.5
		env.glow_intensity = 0.9
		env.glow_hdr_threshold = 0.9
		env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
