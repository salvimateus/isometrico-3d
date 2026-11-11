extends RefCounted
## Public entry point for buildings. Every `create*` call returns a new, independent tree with its
## origin at the footprint center on the ground (y = 0), front facing +Z, idle animation included.

const TownHall = preload("res://scripts/buildings/kinds/town_hall.gd")
const GoldMine = preload("res://scripts/buildings/kinds/gold_mine.gd")
const ManaCollector = preload("res://scripts/buildings/kinds/mana_collector.gd")
const GoldStorage = preload("res://scripts/buildings/kinds/gold_storage.gd")
const ManaStorage = preload("res://scripts/buildings/kinds/mana_storage.gd")
const Cannon = preload("res://scripts/buildings/kinds/cannon.gd")
const ArcherTower = preload("res://scripts/buildings/kinds/archer_tower.gd")
const Barracks = preload("res://scripts/buildings/kinds/barracks.gd")
const BuilderHut = preload("res://scripts/buildings/kinds/builder_hut.gd")
const WaterTower = preload("res://scripts/buildings/kinds/water_tower.gd")
const WaterButton = preload("res://scripts/buildings/kinds/water_button.gd")
const Catapult = preload("res://scripts/buildings/kinds/catapult.gd")
const Wall = preload("res://scripts/buildings/kinds/wall.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const MeshBaker = preload("res://scripts/buildings/mesh_baker.gd")
const NightLight = preload("res://scripts/buildings/anim/night_light.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")

const _FOOTPRINTS: Dictionary = {
	&"town_hall": Vector2i(4, 4),
	&"gold_mine": Vector2i(3, 3),
	&"mana_collector": Vector2i(3, 3),
	&"gold_storage": Vector2i(3, 3),
	&"mana_storage": Vector2i(3, 3),
	&"cannon": Vector2i(3, 3),
	&"archer_tower": Vector2i(3, 3),
	&"barracks": Vector2i(3, 3),
	&"builder_hut": Vector2i(2, 2),
	&"water_tower": Vector2i(3, 3),
	&"water_button": Vector2i(1, 1),
	&"catapult": Vector2i(3, 3),
	&"wall": Vector2i(1, 1),
}

const _NAMES: Dictionary = {
	&"town_hall": "Centro da Vila",
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
	&"wall": "Muro",
}


static func kinds() -> Array[StringName]:
	var out: Array[StringName] = [
		&"town_hall", &"gold_mine", &"mana_collector", &"gold_storage", &"mana_storage",
		&"cannon", &"archer_tower", &"barracks", &"builder_hut", &"water_tower", &"water_button", &"catapult",
	]
	return out


static func footprint(kind: StringName) -> Vector2i:
	if not _FOOTPRINTS.has(kind):
		push_error("building_factory: unknown kind '%s'" % kind)
		return Vector2i.ONE
	return _FOOTPRINTS[kind]


static func display_name(kind: StringName) -> String:
	return _NAMES.get(kind, String(kind))


## `bake` merges the static meshes into one MeshInstance3D per material (see bake_static).
static func create(kind: StringName, bake: bool = true) -> Node3D:
	var node: Node3D
	match kind:
		&"town_hall":
			node = TownHall.build()
		&"gold_mine":
			node = GoldMine.build()
		&"mana_collector":
			node = ManaCollector.build()
		&"gold_storage":
			node = GoldStorage.build()
		&"mana_storage":
			node = ManaStorage.build()
		&"cannon":
			node = Cannon.build()
		&"archer_tower":
			node = ArcherTower.build()
		&"barracks":
			node = Barracks.build()
		&"builder_hut":
			node = BuilderHut.build()
		&"water_tower":
			node = WaterTower.build()
		&"water_button":
			node = WaterButton.build()
		&"catapult":
			node = Catapult.build()
		&"wall":
			node = Wall.build(0)
		_:
			push_error("building_factory: unknown kind '%s'" % kind)
			node = Node3D.new()
	node.name = String(kind).to_pascal_case()
	if bake:
		MeshBaker.bake_static(node)
	return node


## Day/night blend for every building: 0 = day, 1 = night. Cheap enough to call every frame.
## Updates the shared emissive materials and switches the warm lamps (group `building_night_lights`).
static func set_night(tree: SceneTree, amount: float) -> void:
	Mat.set_night(amount)
	for n: Node in tree.get_nodes_in_group(NightLight.GROUP):
		n.call(&"apply_night", Mat.night_amount)


## Turns every building light on or off (warm night lamps and mana glow lights). Lights created
## later follow the last value. On the mobile tier no lights exist, so this is a no-op there.
static func set_lights_enabled(tree: SceneTree, on: bool) -> void:
	Tuning.lights_enabled = on
	for group: StringName in [NightLight.GROUP, Tuning.MANA_LIGHT_GROUP]:
		for n: Node in tree.get_nodes_in_group(group):
			n.call(&"set_enabled", on)


## Wall tile connected by bitmask: bit0 = +X, bit1 = -X, bit2 = +Z, bit3 = -Z.
static func create_wall(neighbors: int, bake: bool = true) -> Node3D:
	var node: Node3D = Wall.build(neighbors & 0xF)
	node.name = "Wall"
	if bake:
		MeshBaker.bake_static(node)
	return node


## Merges every static MeshInstance3D under `root` into one mesh per material, under a "Baked" node.
## Keeps scripted (animated) subtrees, contract nodes, particles, lights, halos and meshes whose
## shader depends on the instance position (flags, mana, rocks). Safe to call on any tree, repeatedly.
static func bake_static(root: Node3D) -> void:
	MeshBaker.bake_static(root)
