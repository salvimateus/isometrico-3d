extends RefCounted

## Small village dressing (barrels, crates, lantern posts, flower beds, picket fences) with bumpable colliders.

const Kit := preload("res://scripts/world/mesh_kit.gd")
const Tuning := preload("res://scripts/tuning.gd")
const Mats := preload("res://scripts/world/world_materials.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const BuildingBody := preload("res://scripts/world/building_body.gd")
const GroundData := preload("res://scripts/world/ground_data.gd")

const C_WOOD := Color("A8693A")
const C_WOOD_LIGHT := Color("C58650")
const C_WOOD_DARK := Color("7A4A28")
const C_METAL := Color("4A4F5A")
const C_SOIL := Color("6B4529")

# kind, world xz, yaw
const PLACEMENTS: Array = [
	[&"lantern", Vector2(-1.75, -7.3), 0.0], [&"lantern", Vector2(0.75, -7.3), 0.0],
	[&"lantern", Vector2(-1.75, 7.3), 0.0],
	[&"lantern", Vector2(-7.3, -1.75), 0.0], [&"lantern", Vector2(-7.3, 0.75), 0.0],
	[&"lantern", Vector2(7.3, -1.75), 0.0], [&"lantern", Vector2(7.3, 0.75), 0.0],
	[&"barrel", Vector2(-2.7, 9.1), 0.3], [&"barrel", Vector2(-2.35, 9.65), 1.1], [&"crate", Vector2(-2.6, 10.3), 0.2],
	[&"crate", Vector2(-1.7, -9.6), 0.5], [&"crate", Vector2(-1.6, -9.0), 0.1], [&"barrel", Vector2(-1.35, -10.4), 0.0],
	[&"barrel", Vector2(9.7, 12.1), 0.7], [&"crate", Vector2(10.2, 12.6), -0.3],
	[&"barrel", Vector2(9.6, -9.5), 0.0], [&"crate", Vector2(9.0, -9.9), 0.4],
	[&"flower_bed", Vector2(-4.5, -2.5), 0.0], [&"flower_bed", Vector2(3.5, 1.5), 0.0],
	[&"flower_bed", Vector2(1.5, -4.5), PI * 0.5], [&"flower_bed", Vector2(-2.5, 4.5), PI * 0.5],
	[&"garden", Vector2(-9.5, 9.5), 0.0],
]

static var _meshes: Dictionary = {}


static func build(parent: Node3D, ground: GroundData) -> void:
	var root := Node3D.new()
	root.name = "VillageProps"
	parent.add_child(root)
	for entry: Array in PLACEMENTS:
		var kind: StringName = entry[0]
		var p: Vector2 = entry[1]
		if ground.blocked_at(p, 0.0) == 2:
			push_warning("[VillageProps] %s at %s overlaps a building" % [kind, p])
			continue
		if p.distance_to(Layout.LANDING_CENTER) < Layout.LANDING_RADIUS + 0.4 or p.distance_to(Layout.CATAPULT_TARGET) < Layout.CATAPULT_TARGET_RADIUS + 0.6:
			push_warning("[VillageProps] %s at %s sits in a catapult landing or target zone" % [kind, p])
			continue
		var slot := Node3D.new()
		slot.position = Vector3(p.x, Shape.ground_height(p), p.y)
		slot.rotation.y = entry[2]
		root.add_child(slot)
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(kind)
		mi.material_override = Mats.vertex_color(&"props", 0.8)
		slot.add_child(mi)
		if kind == &"lantern":
			_add_glow(slot)
		_add_body(slot, kind)


static func _add_body(slot: Node3D, kind: StringName) -> void:
	var size: Vector3
	match kind:
		&"barrel":
			size = Vector3(0.42, 0.6, 0.42)
		&"crate":
			size = Vector3(0.46, 0.46, 0.46)
		&"lantern":
			size = Vector3(0.18, 1.4, 0.18)
		&"flower_bed":
			size = Vector3(1.5, 0.3, 0.6)
		&"garden":
			size = Vector3(1.9, 0.5, 1.9)
	var body := BuildingBody.new()
	body.slot = slot
	body.dust_radius = 0.3
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	slot.add_child(body)


static func _add_glow(slot: Node3D) -> void:
	var bulb := MeshInstance3D.new()
	bulb.mesh = Kit.sphere(0.075, 10, 6)
	var mat: StandardMaterial3D = Mats.solid(Color("FFD27A"), 0.4)
	if not mat.emission_enabled:
		mat.emission_enabled = true
		mat.emission = Color("FFC45A")
		mat.emission_energy_multiplier = 3.0
	bulb.material_override = mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = Vector3(0.22, 1.12, 0)
	slot.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color("FFC46A")
	light.omni_range = Tuning.LANTERN_LIGHT_RANGE
	light.light_energy = 0.0
	light.visible = false
	light.shadow_enabled = false
	light.position = Vector3(0.22, 1.05, 0)
	light.set_meta(&"night_energy", Tuning.LANTERN_LIGHT_ENERGY)
	light.add_to_group(&"night_lights")
	slot.add_child(light)


static func _mesh(kind: StringName) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var kit := Kit.new()
	match kind:
		&"barrel":
			kit.add(Kit.cylinder(0.17, 0.17, 0.52, 12), Transform3D(Basis(), Vector3(0, 0.27, 0)), C_WOOD_DARK, C_WOOD_LIGHT)
			kit.add(Kit.cylinder(0.2, 0.2, 0.3, 12), Transform3D(Basis(), Vector3(0, 0.27, 0)), C_WOOD, C_WOOD_LIGHT)
			for y: float in [0.08, 0.27, 0.46]:
				kit.add(Kit.cylinder(0.205 if y == 0.27 else 0.18, 0.205 if y == 0.27 else 0.18, 0.035, 12), Transform3D(Basis(), Vector3(0, y, 0)), C_METAL, C_METAL)
			kit.add(Kit.cylinder(0.15, 0.15, 0.02, 12), Transform3D(Basis(), Vector3(0, 0.53, 0)), C_WOOD_LIGHT, C_WOOD_LIGHT)
		&"crate":
			kit.add(Kit.box(Vector3(0.42, 0.42, 0.42)), Transform3D(Basis(), Vector3(0, 0.21, 0)), C_WOOD, C_WOOD_LIGHT)
			for s: float in [-1.0, 1.0]:
				kit.add(Kit.box(Vector3(0.46, 0.06, 0.46)), Transform3D(Basis(), Vector3(0, 0.21 + s * 0.18, 0)), C_WOOD_DARK, C_WOOD_DARK)
			kit.add(Kit.box(Vector3(0.05, 0.5, 0.44)), Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0.215, 0.21, 0)), C_WOOD_DARK, C_WOOD_DARK)
			kit.add(Kit.box(Vector3(0.05, 0.5, 0.44)), Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(-0.215, 0.21, 0)), C_WOOD_DARK, C_WOOD_DARK)
		&"lantern":
			kit.add(Kit.cylinder(0.12, 0.15, 0.12, 8), Transform3D(Basis(), Vector3(0, 0.06, 0)), Color("8E877C"), Color("C2BBAE"))
			kit.add(Kit.cylinder(0.04, 0.05, 1.3, 8), Transform3D(Basis(), Vector3(0, 0.7, 0)), C_WOOD_DARK, C_WOOD)
			kit.add(Kit.box(Vector3(0.3, 0.04, 0.04)), Transform3D(Basis(), Vector3(0.12, 1.3, 0)), C_WOOD_DARK, C_WOOD_DARK)
			kit.add(Kit.cylinder(0.01, 0.01, 0.1, 4), Transform3D(Basis(), Vector3(0.22, 1.25, 0)), C_METAL, C_METAL)
			kit.add(Kit.cylinder(0.05, 0.11, 0.08, 6), Transform3D(Basis(), Vector3(0.22, 1.21, 0)), C_METAL, C_METAL)
			kit.add(Kit.cylinder(0.09, 0.07, 0.04, 6), Transform3D(Basis(), Vector3(0.22, 1.03, 0)), C_METAL, C_METAL)
		&"flower_bed":
			kit.add(Kit.box(Vector3(1.4, 0.22, 0.5)), Transform3D(Basis(), Vector3(0, 0.11, 0)), C_WOOD_DARK, C_WOOD)
			kit.add(Kit.box(Vector3(1.28, 0.05, 0.38)), Transform3D(Basis(), Vector3(0, 0.22, 0)), C_SOIL, C_SOIL)
			_flowers(kit, Vector2(1.2, 0.3), 0.24, 14, 7)
		&"garden":
			_fence_square(kit, 1.8)
			kit.add(Kit.box(Vector3(1.3, 0.08, 1.3)), Transform3D(Basis(), Vector3(0, 0.04, 0)), C_SOIL, C_SOIL)
			_flowers(kit, Vector2(1.1, 1.1), 0.08, 22, 11)
	_meshes[kind] = kit.commit()
	return _meshes[kind]


static func _flowers(kit: Kit, area: Vector2, base_y: float, count: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var colors: Array[Color] = [Color("FF8FC1"), Color("FFD54A"), Color("FFFFFF"), Color("C995FF"), Color("FF6B5A")]
	for i: int in count:
		var p := Vector3(rng.randf_range(-area.x, area.x) * 0.5, base_y, rng.randf_range(-area.y, area.y) * 0.5)
		kit.add(Kit.sphere(0.11, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), p + Vector3(0, 0.06, 0)), Color("2F8C3E"), Color("4FB345"))
		var c: Color = colors[rng.randi() % colors.size()]
		kit.add(Kit.sphere(0.055, 6, 4), Transform3D(Basis(), p + Vector3(rng.randf_range(-0.04, 0.04), 0.17, rng.randf_range(-0.04, 0.04))), c.darkened(0.15), c)


static func _fence_square(kit: Kit, size: float) -> void:
	var h: float = size * 0.5
	var posts: int = 5
	for side: int in 4:
		var dir := Vector3.RIGHT if side % 2 == 0 else Vector3.BACK
		var normal := Vector3.BACK if side % 2 == 0 else Vector3.RIGHT
		var sign: float = -1.0 if side < 2 else 1.0
		var start: Vector3 = normal * h * sign - dir * h
		for i: int in posts:
			var p: Vector3 = start + dir * (size * i / float(posts - 1))
			kit.add(Kit.box(Vector3(0.07, 0.42, 0.05)), Transform3D(Basis(), p + Vector3(0, 0.21, 0)), C_WOOD, Color("F0E2C8"))
		for y: float in [0.14, 0.3]:
			var rail_size := Vector3(size, 0.05, 0.03) if side % 2 == 0 else Vector3(0.03, 0.05, size)
			kit.add(Kit.box(rail_size), Transform3D(Basis(), normal * h * sign + Vector3(0, y, 0)), C_WOOD_DARK, C_WOOD)
