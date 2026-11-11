extends RefCounted

## Instantiates the layout through the BUILDINGS factory (with placeholder fallback)
## and wraps each building in a slot with a pick body for selection.

const Layout := preload("res://scripts/world/base_layout.gd")
const Mats := preload("res://scripts/world/world_materials.gd")
const Kit := preload("res://scripts/world/mesh_kit.gd")
const BuildingBody := preload("res://scripts/world/building_body.gd")

const FACTORY_PATH: String = "res://scripts/buildings/building_factory.gd"
const PICK_LAYER: int = 2
## Layer for pick-only bodies (no physical collision); selection rays use PICK_LAYER and this one.
const PICK_ONLY_LAYER: int = 4
const PICK_MASK: int = (1 << (PICK_LAYER - 1)) | (1 << (PICK_ONLY_LAYER - 1))
const BODY_INSET: float = 0.2
const WALL_BODY_SIZE: float = 0.9

const FALLBACK_NAMES: Dictionary = {
	&"town_hall": "Prefeitura",
	&"gold_mine": "Mina de Ouro",
	&"mana_collector": "Coletor de Mana",
	&"gold_storage": "Depósito de Ouro",
	&"mana_storage": "Depósito de Mana",
	&"cannon": "Canhão",
	&"archer_tower": "Torre de Arqueiras",
	&"barracks": "Quartel",
	&"builder_hut": "Cabana do Construtor",
	&"water_tower": "Caixa d'Água",
	&"water_button": "Botão da Caixa d'Água",
	&"catapult": "Catapulta",
}

const FALLBACK_COLORS: Dictionary = {
	&"town_hall": Color("D8452E"),
	&"gold_mine": Color("FFC93C"),
	&"mana_collector": Color("C24BE0"),
	&"gold_storage": Color("FFC93C"),
	&"mana_storage": Color("C24BE0"),
	&"cannon": Color("4A4F5A"),
	&"archer_tower": Color("3E7FD6"),
	&"barracks": Color("D8452E"),
	&"builder_hut": Color("A8693A"),
	&"water_tower": Color("3E7FD6"),
	&"water_button": Color("D8452E"),
	&"catapult": Color("A8693A"),
}

var factory: Script = null
var buildings: Array[Dictionary] = []
var _factory_kinds: Array = []


func _init(use_factory: bool = true) -> void:
	factory = _load_factory() if use_factory else null
	if factory != null:
		_factory_kinds = factory.call("kinds")


static func _load_factory() -> Script:
	if not ResourceLoader.exists(FACTORY_PATH):
		return null
	var s: Resource = load(FACTORY_PATH)
	if s is GDScript and (s as GDScript).can_instantiate():
		return s
	return null


func has_factory() -> bool:
	return factory != null


func footprint_of(kind: StringName) -> Vector2i:
	if factory != null and _factory_kinds.has(kind):
		var fp: Variant = factory.call("footprint", kind)
		if fp is Vector2i and fp != Vector2i.ZERO:
			return fp
	return Layout.FALLBACK_FOOTPRINTS.get(kind, Vector2i(3, 3))


func display_name(kind: StringName) -> String:
	if factory != null and _factory_kinds.has(kind):
		var n: Variant = factory.call("display_name", kind)
		if n is String and not (n as String).is_empty():
			return n
	return FALLBACK_NAMES.get(kind, String(kind))


func spawn_all(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Buildings"
	parent.add_child(root)
	for e: Dictionary in Layout.entries():
		var kind: StringName = e["kind"]
		var cell: Vector2i = e["cell"]
		var fp: Vector2i = footprint_of(kind)
		var slot := Node3D.new()
		slot.name = "%s_%d_%d" % [kind, cell.x, cell.y]
		slot.position = Layout.footprint_center(cell, fp)
		root.add_child(slot)
		var model: Node3D = _create_model(kind, fp)
		model.rotation.y = float(e.get("yaw", 0.0))
		slot.add_child(model)
		var aabb: AABB = _local_aabb(model, model.transform)
		if aabb.size == Vector3.ZERO:
			aabb = AABB(Vector3(-fp.x * 0.5, 0, -fp.y * 0.5), Vector3(fp.x, 1.5, fp.y))
		var index: int = buildings.size()
		var body := BuildingBody.new()
		body.slot = slot
		body.dust_radius = minf(fp.x, fp.y) * 0.5
		var solid: bool = not Layout.NON_SOLID_KINDS.has(kind)
		body.collision_layer = 1 << ((PICK_LAYER if solid else PICK_ONLY_LAYER) - 1)
		body.collision_mask = 0
		body.set_meta("building_index", index)
		# Pick body doubles as the physics obstacle; clipped so 1-tile corridors stay walkable.
		var limit := Vector3(fp.x * 0.5 - BODY_INSET, 0.0, fp.y * 0.5 - BODY_INSET)
		var lo := Vector3(maxf(aabb.position.x, -limit.x), maxf(aabb.position.y, 0.0), maxf(aabb.position.z, -limit.z))
		var hi := Vector3(minf(aabb.end.x, limit.x), maxf(aabb.end.y, 0.6), minf(aabb.end.z, limit.z))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = hi - lo
		shape.shape = box
		shape.position = (lo + hi) * 0.5
		body.add_child(shape)
		slot.add_child(body)
		buildings.append({"kind": kind, "cell": cell, "footprint": fp, "slot": slot, "model": model, "aabb": aabb, "name": display_name(kind)})
	_spawn_walls(root)


func _create_model(kind: StringName, fp: Vector2i) -> Node3D:
	if factory != null and _factory_kinds.has(kind):
		var node: Variant = factory.call("create", kind)
		if node is Node3D:
			return node
	return _placeholder(kind, fp)


func _spawn_walls(root: Node3D) -> void:
	var walls: Dictionary = {}
	for w: Vector2i in Layout.wall_cells():
		walls[w] = true
	var wall_root := Node3D.new()
	wall_root.name = "Walls"
	root.add_child(wall_root)
	for w: Vector2i in walls.keys():
		var mask: int = Layout.wall_mask(w, walls)
		var node: Node3D = null
		if factory != null:
			var made: Variant = factory.call("create_wall", mask)
			if made is Node3D:
				node = made
		if node == null:
			node = _placeholder_wall(mask)
		var wall_slot := Node3D.new()
		wall_slot.position = Layout.footprint_center(w, Vector2i.ONE)
		wall_root.add_child(wall_slot)
		wall_slot.add_child(node)
		var body := BuildingBody.new()
		body.slot = wall_slot
		body.dust_radius = 0.45
		body.collision_layer = 1 << (PICK_LAYER - 1)
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_BODY_SIZE, 1.2, WALL_BODY_SIZE)
		cs.shape = box
		cs.position.y = 0.6
		body.add_child(cs)
		wall_slot.add_child(body)
	# One mesh per material for the whole ring; per-segment bumps then only puff dust and thud.
	if factory != null and (factory as GDScript).has_method(&"bake_static"):
		for slot: Node in wall_root.get_children():
			slot.set_meta(&"baked", true)
		factory.call(&"bake_static", wall_root)


static func _local_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var has: bool = false
	if node is VisualInstance3D and not (node is Label3D) and not (node is GPUParticles3D) and not (node is CPUParticles3D):
		var box: AABB = xform * (node as VisualInstance3D).get_aabb()
		result = box
		has = true
	for child: Node in node.get_children():
		if child is Node3D:
			var sub: AABB = _local_aabb(child, xform * (child as Node3D).transform)
			if sub.size != Vector3.ZERO:
				result = result.merge(sub) if has else sub
				has = true
	return result


static func _placeholder(kind: StringName, fp: Vector2i) -> Node3D:
	var kit := Kit.new()
	var w: float = fp.x - 0.3
	var d: float = fp.y - 0.3
	var h: float = 1.0 + fp.x * 0.2
	var roof: Color = FALLBACK_COLORS.get(kind, Color.WHITE)
	if Layout.NON_SOLID_KINDS.has(kind):
		kit.add(Kit.cylinder(0.3, 0.36, 0.12, 16), Transform3D(Basis(), Vector3(0, 0.06, 0)), Color("8E877C"), Color("C2BBAE"))
		kit.add(Kit.cylinder(0.2, 0.22, 0.1, 16), Transform3D(Basis(), Vector3(0, 0.17, 0)), roof.darkened(0.25), roof)
		var button := MeshInstance3D.new()
		button.mesh = kit.commit()
		button.material_override = Mats.vertex_color(&"placeholder", 0.8)
		var holder := Node3D.new()
		holder.add_child(button)
		return holder
	kit.add(Kit.box(Vector3(w, 0.2, d)), Transform3D(Basis(), Vector3(0, 0.1, 0)), Color("8E877C"), Color("C2BBAE"))
	kit.add(Kit.box(Vector3(w - 0.3, h, d - 0.3)), Transform3D(Basis(), Vector3(0, 0.2 + h * 0.5, 0)), Color("D9B27C"), Color("F1D9AE"))
	var prism := PrismMesh.new()
	prism.size = Vector3(w - 0.1, h * 0.7, d - 0.1)
	kit.add(prism, Transform3D(Basis(), Vector3(0, 0.2 + h + h * 0.35, 0)), roof.darkened(0.25), roof)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.material_override = Mats.vertex_color(&"placeholder", 0.8)
	var root := Node3D.new()
	root.add_child(mi)
	return root


static func _placeholder_wall(mask: int) -> Node3D:
	var kit := Kit.new()
	var c0 := Color("8E877C")
	var c1 := Color("C2BBAE")
	kit.add(Kit.box(Vector3(0.5, 0.8, 0.5)), Transform3D(Basis(), Vector3(0, 0.4, 0)), c0, c1)
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	for bit: int in 4:
		if mask & (1 << bit):
			var d: Vector3 = dirs[bit]
			var size := Vector3(0.5, 0.62, 0.36) if absf(d.x) > 0.5 else Vector3(0.36, 0.62, 0.5)
			kit.add(Kit.box(size), Transform3D(Basis(), d * 0.25 + Vector3(0, 0.31, 0)), c0, c1)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.material_override = Mats.vertex_color(&"placeholder", 0.8)
	var root := Node3D.new()
	root.add_child(mi)
	return root
