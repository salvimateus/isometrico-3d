extends RefCounted

## Pure layout data and grid math. Cell (0, 0) is the min corner of the playable square.

const GRID_SIZE: int = 22
const HALF: float = GRID_SIZE * 0.5

const FALLBACK_FOOTPRINTS: Dictionary = {
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
}

## Kinds that never block movement and may touch other footprints.
const NON_SOLID_KINDS: Array[StringName] = [&"water_button"]

const WALL_MIN: int = 4
const WALL_MAX: int = 17
const GATE_CELLS: Array[int] = [10]
const PATH_LINE: int = 10

# Pond south of the playable square, crossed by a footbridge on the south path axis.
const POND_LOBES: Array[Vector3] = [Vector3(-2.35, 13.7, 1.95), Vector3(1.3, 13.35, 1.8)]
## Catapult target: deepest open spot of the west pond lobe, clear of the bridge. y is the water surface.
const CATAPULT_TARGET: Vector2 = Vector2(-2.9, 13.75)
const CATAPULT_TARGET_RADIUS: float = 1.0
const CATAPULT_CELL: Vector2i = Vector2i(1, 1)

## Shallow ground depressions (x, z, radius, depth) where flood water pools.
const DEPRESSIONS: Array[Vector4] = [
	# On the flood path: inside the south gate, right outside it, and west of the wall.
	Vector4(-1.9, 4.2, 1.0, 0.28), Vector4(1.0, 4.6, 1.0, 0.26), Vector4(-0.4, 8.2, 1.1, 0.26),
	Vector4(-1.4, 10.8, 1.0, 0.22), Vector4(-7.6, 8.6, 1.2, 0.22),
	Vector4(2.8, 4.3, 1.5, 0.18), Vector4(-4.2, 3.6, 1.3, 0.15), Vector4(4.2, -3.6, 1.4, 0.14),
	Vector4(-9.2, 2.6, 2.0, 0.22), Vector4(8.6, 3.2, 1.8, 0.2), Vector4(-3.6, -8.8, 1.6, 0.15),
	Vector4(3.4, -9.4, 2.2, 0.24), Vector4(-8.6, -3.4, 1.5, 0.12),
]
## Ditches (start, end) with radius and depth at start/end; the east one carries water to the cliff.
const DITCHES: Array = [
	[Vector2(6.8, 0.85), Vector2(13.0, 0.85), 0.6, 0.06, 0.14],
	[Vector2(-1.75, 8.1), Vector2(-1.75, 11.4), 0.5, 0.08, 0.16],
]


static func catapult_center() -> Vector2:
	var c: Vector3 = footprint_center(CATAPULT_CELL, FALLBACK_FOOTPRINTS[&"catapult"])
	return Vector2(c.x, c.z)


## Yaw that turns the catapult's +Z toward the pond target.
static func catapult_yaw() -> float:
	var d: Vector2 = CATAPULT_TARGET - catapult_center()
	return atan2(d.x, d.y)


## Open landing pocket for the catapult arc: no layer-2 colliders within LANDING_RADIUS.
const LANDING_CENTER: Vector2 = Vector2(8.8, 8.8)
const LANDING_RADIUS: float = 2.6
const BRIDGE_CENTER: Vector3 = Vector3(-0.5, 0.0, 13.55)


static func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	# Walled core.
	list.append({"kind": &"town_hall", "cell": Vector2i(9, 9)})
	list.append({"kind": &"gold_storage", "cell": Vector2i(5, 5)})
	list.append({"kind": &"mana_storage", "cell": Vector2i(14, 14)})
	list.append({"kind": &"cannon", "cell": Vector2i(14, 5)})
	list.append({"kind": &"archer_tower", "cell": Vector2i(5, 14)})
	# Outer ring of the village.
	list.append({"kind": &"gold_mine", "cell": Vector2i(6, 0)})
	list.append({"kind": &"mana_collector", "cell": Vector2i(13, 0)})
	list.append({"kind": &"mana_collector", "cell": Vector2i(0, 6)})
	list.append({"kind": &"builder_hut", "cell": Vector2i(0, 14)})
	list.append({"kind": &"cannon", "cell": Vector2i(19, 5)})
	list.append({"kind": &"gold_mine", "cell": Vector2i(19, 13)})
	list.append({"kind": &"barracks", "cell": Vector2i(5, 19)})
	list.append({"kind": &"builder_hut", "cell": Vector2i(0, 17)})
	# Catapult in the north-west corner, front (+Z) turned toward the south-east so the arc crosses the core.
	list.append({"kind": &"catapult", "cell": Vector2i(1, 1), "yaw": catapult_yaw()})
	# Water tower south-east of the south gate, front (+Z) turned to -X: the bucket spills on the open
	# ground right outside the gate, so the wave runs through it into the core.
	list.append({"kind": &"water_tower", "cell": Vector2i(14, 18), "yaw": -PI * 0.5})
	list.append({"kind": &"water_button", "cell": Vector2i(13, 20)})
	return list


static func wall_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(WALL_MIN, WALL_MAX + 1):
		for z: int in range(WALL_MIN, WALL_MAX + 1):
			var on_x_edge: bool = x == WALL_MIN or x == WALL_MAX
			var on_z_edge: bool = z == WALL_MIN or z == WALL_MAX
			if not on_x_edge and not on_z_edge:
				continue
			if on_z_edge and not on_x_edge and GATE_CELLS.has(x):
				continue
			if on_x_edge and not on_z_edge and GATE_CELLS.has(z):
				continue
			cells.append(Vector2i(x, z))
	return cells


static func wall_mask(cell: Vector2i, walls: Dictionary) -> int:
	var mask: int = 0
	if walls.has(cell + Vector2i(1, 0)):
		mask |= 1
	if walls.has(cell + Vector2i(-1, 0)):
		mask |= 2
	if walls.has(cell + Vector2i(0, 1)):
		mask |= 4
	if walls.has(cell + Vector2i(0, -1)):
		mask |= 8
	return mask


## Dirt path cells: one-tile spokes through the gates, the south one running on to the bridge.
static func path_cells() -> Array[Vector2i]:
	var cells: Dictionary = {}
	for i: int in range(0, 9):
		cells[Vector2i(PATH_LINE, i)] = true
		cells[Vector2i(i, PATH_LINE)] = true
	for i: int in range(13, GRID_SIZE + 5):
		cells[Vector2i(PATH_LINE, i)] = true
	for i: int in range(13, GRID_SIZE):
		cells[Vector2i(i, PATH_LINE)] = true
	var out: Array[Vector2i] = []
	for k: Vector2i in cells.keys():
		out.append(k)
	return out


static func cell_min_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x - HALF, 0.0, cell.y - HALF)


static func footprint_center(cell: Vector2i, footprint: Vector2i) -> Vector3:
	return Vector3(cell.x + footprint.x * 0.5 - HALF, 0.0, cell.y + footprint.y * 0.5 - HALF)


static func pond_sdf(p: Vector2) -> float:
	var d: float = 1e9
	for lobe: Vector3 in POND_LOBES:
		d = minf(d, p.distance_to(Vector2(lobe.x, lobe.y)) - lobe.z)
	return d


## Returns a list of human readable problems: overlap, missing corridor, out of bounds.
static func validate(footprint_of: Callable) -> PackedStringArray:
	var problems: PackedStringArray = []
	var rects: Array[Rect2i] = []
	var names: Array[String] = []
	for e: Dictionary in entries():
		var fp: Vector2i = footprint_of.call(e["kind"])
		rects.append(Rect2i(e["cell"], fp))
		names.append(String(e["kind"]))
	for w: Vector2i in wall_cells():
		rects.append(Rect2i(w, Vector2i.ONE))
		names.append("wall")
	var bounds := Rect2i(0, 0, GRID_SIZE, GRID_SIZE)
	for i: int in rects.size():
		if not bounds.encloses(rects[i]):
			problems.append("%s at %s is out of bounds" % [names[i], rects[i].position])
		for j: int in range(i + 1, rects.size()):
			# Buildings keep a 1-tile corridor between them; walls may hug buildings.
			var any_wall: bool = names[i] == "wall" or names[j] == "wall" or NON_SOLID_KINDS.has(StringName(names[i])) or NON_SOLID_KINDS.has(StringName(names[j]))
			var grown: Rect2i = rects[i] if any_wall else rects[i].grow(1)
			if grown.intersects(rects[j]):
				problems.append("%s at %s touches %s at %s" % [names[i], rects[i].position, names[j], rects[j].position])
	return problems
