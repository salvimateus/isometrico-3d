extends RefCounted
## Gold mine (3x3): rocky mound with a timbered entrance, headframe with a spinning wheel and gears,
## mine cart full of gold on rails.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12, Mat.solid(Mat.DIRT_DARK, 0.95))
	var g: float = 0.12
	_mound(root, g)
	_entrance(root, Vector3(-0.5, g, 0.12))
	_rails(root, Vector3(-0.5, g, 0.0))
	_cart(root, Vector3(-0.5, g + 0.06, 0.82))
	_headframe(root, Vector3(0.62, g, -0.45))
	Parts.gold_heap(root, Vector3(0.62, g, 0.72), 0.42, 0.3, 7, 8)
	_lantern_post(root, Vector3(0.1, g, 0.55))
	_back_props(root, g)
	return root


## Crate of ore and a pickaxe on the back side of the mound.
static func _back_props(root: Node3D, g: float) -> void:
	var crate := Parts.pivot(root, Vector3(0.55, g, -1.05), Vector3(0.0, 18.0, 0.0), "Crate")
	Parts.block(crate, Vector3(0.42, 0.32, 0.36), Mat.planks(true, Mat.WOOD, Mat.WOOD_DARK, 0.1, true), Vector3.ZERO, 0.04)
	Parts.box(crate, Vector3(0.44, 0.05, 0.38), Mat.wood_dark(), Vector3(0.0, 0.3, 0.0), 0.02)
	Parts.gold_heap(crate, Vector3(0.0, 0.32, 0.0), 0.16, 0.1, 11, 3)
	var pick := Parts.pivot(root, Vector3(-1.2, g, 0.45), Vector3(0.0, 70.0, -18.0), "Pickaxe")
	Parts.rod(pick, Vector3.ZERO, Vector3(0.0, 0.62, 0.0), 0.025, Mat.wood(), 6)
	Parts.mesh(pick, Kit.cylinder(0.035, 0.38, 0.0, 0.012, 8), Mat.metal_light(), Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.0, 90.0))


## Faceted boulder whose flat base sits at `base_y`.
static func _rock(root: Node3D, x: float, z: float, base_y: float, size: Vector3, yaw: float, seed_value: int) -> void:
	Parts.mesh(root, Kit.rock(seed_value), Mat.rock(), Vector3(x, base_y + 0.3 * size.y - 0.02, z), Vector3(0.0, yaw, 0.0), size)


## Cluster of faceted gold nuggets half-buried at `pos`, leaning along `normal`.
static func _vein(root: Node3D, pos: Vector3, normal: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var up: Vector3 = normal.normalized()
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var fwd: Vector3 = side.cross(up)
	for i in 4:
		var s: float = rng.randf_range(0.09, 0.16)
		var off: Vector3 = side * rng.randf_range(-0.1, 0.1) + fwd * rng.randf_range(-0.1, 0.1) - up * s * 0.25
		Parts.mesh(root, Kit.rock(500 + seed_value * 7 + i, 3, 5), Mat.gold(), pos + off,
			Vector3(rng.randf() * 50.0, rng.randf() * 360.0, rng.randf() * 50.0), Vector3(s, s * 0.85, s))


static func _mound(root: Node3D, g: float) -> void:
	_rock(root, -0.55, -0.6, g, Vector3(1.45, 1.75, 1.3), 8.0, 1)
	_rock(root, -0.05, -0.85, g, Vector3(0.95, 0.95, 0.9), -20.0, 2)
	_rock(root, -1.0, -0.05, g, Vector3(0.62, 0.8, 0.7), 25.0, 3)
	_rock(root, -0.75, -0.75, g + 1.15, Vector3(0.8, 0.6, 0.75), 40.0, 4)
	_rock(root, 0.08, -0.2, g, Vector3(0.42, 0.36, 0.42), 15.0, 5)
	_rock(root, -1.05, -1.06, g, Vector3(0.5, 0.5, 0.45), 30.0, 6)
	_rock(root, -0.25, -1.12, g, Vector3(0.42, 0.4, 0.38), -12.0, 7)
	_rock(root, 1.08, 0.3, g, Vector3(0.28, 0.24, 0.28), 50.0, 8)
	var veins: Array = [
		[Vector3(0.18, g + 0.62, -0.62), Vector3(1.0, 0.3, 0.6)],
		[Vector3(-0.45, g + 1.38, -0.4), Vector3(0.3, 1.0, 0.5)],
		[Vector3(-1.22, g + 0.62, -0.35), Vector3(-1.0, 0.3, 0.2)],
		[Vector3(-0.7, g + 0.7, -1.28), Vector3(-0.2, 0.3, -1.0)],
		[Vector3(-0.15, g + 0.95, -1.05), Vector3(0.2, 0.6, -1.0)],
		[Vector3(-0.95, g + 1.55, -0.95), Vector3(-0.5, 1.0, -0.5)],
	]
	for i in veins.size():
		_vein(root, veins[i][0], veins[i][1], i + 1)


static func _entrance(root: Node3D, pos: Vector3) -> void:
	var e := Parts.pivot(root, pos, Vector3.ZERO, "Entrance")
	Parts.mesh(e, Kit.arch(0.7, 1.02, 0.2), Mat.opening(), Vector3(0.0, 0.0, -0.02))
	var wood: Material = Mat.wood()
	for s: float in [-1.0, 1.0]:
		Parts.block(e, Vector3(0.14, 1.12, 0.16), wood, Vector3(s * 0.43, 0.0, 0.06), 0.04)
	Parts.box(e, Vector3(1.1, 0.16, 0.2), wood, Vector3(0.0, 1.16, 0.06), 0.05)
	Parts.box(e, Vector3(0.32, 0.12, 0.05), Mat.wood_dark(), Vector3(0.0, 1.32, 0.12), 0.03, Vector3(0.0, 0.0, -6.0))
	Parts.mesh(e, Kit.sphere(0.05, 10, 6), Mat.gold(), Vector3(0.0, 1.32, 0.16))


static func _rails(root: Node3D, pos: Vector3) -> void:
	for i in 5:
		Parts.block(root, Vector3(0.5, 0.05, 0.1), Mat.wood_dark(), pos + Vector3(0.0, 0.0, 0.22 + i * 0.25), 0.02)
	for s: float in [-1.0, 1.0]:
		Parts.block(root, Vector3(0.05, 0.05, 1.22), Mat.metal_light(), pos + Vector3(s * 0.17, 0.04, 0.68), 0.015)


static func _cart(root: Node3D, pos: Vector3) -> void:
	var c := Parts.pivot(root, pos, Vector3.ZERO, "Cart")
	Parts.block(c, Vector3(0.56, 0.34, 0.66), Mat.planks(true, Mat.WOOD, Mat.WOOD_DARK, 0.11, true), Vector3(0.0, 0.1, 0.0), 0.05, -0.12)
	Parts.box(c, Vector3(0.6, 0.06, 0.7), Mat.metal(), Vector3(0.0, 0.42, 0.0), 0.025)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.mesh(c, Kit.cylinder(0.09, 0.06, 0.02, -1.0, 12), Mat.metal(), Vector3(sx * 0.25, 0.1, sz * 0.2), Vector3(0.0, 0.0, 90.0))
	Parts.gold_heap(c, Vector3(0.0, 0.4, 0.0), 0.27, 0.2, 3, 4)


static func _headframe(root: Node3D, pos: Vector3) -> void:
	var h := Parts.pivot(root, pos, Vector3(0.0, 45.0, 0.0), "Headframe")
	var wood: Material = Mat.wood()
	var top_y: float = 1.75
	for s: float in [-1.0, 1.0]:
		Parts.rod(h, Vector3(s * 0.55, 0.0, -0.32), Vector3(s * 0.22, top_y, -0.12), 0.07, wood, 0, true)
		Parts.rod(h, Vector3(s * 0.55, 0.0, 0.08), Vector3(s * 0.22, top_y, -0.12), 0.07, wood, 0, true)
		Parts.rod(h, Vector3(s * 0.45, 0.6, -0.27), Vector3(s * 0.45, 0.6, 0.03), 0.04, Mat.wood_dark(), 0, true)
		Parts.block(h, Vector3(0.22, 0.12, 0.6), Mat.stone_dark(), Vector3(s * 0.55, 0.0, -0.12), 0.04)
	Parts.rod(h, Vector3(-0.42, 0.6, -0.12), Vector3(0.42, 0.6, -0.12), 0.045, Mat.wood_dark(), 0, true)
	Parts.box(h, Vector3(0.62, 0.12, 0.22), Mat.wood_dark(), Vector3(0.0, top_y - 0.02, -0.12), 0.04)
	# Spinning wheel facing the camera (its axle runs along local Z).
	var wheel := Parts.spinner(h, Vector3(0.0, top_y + 0.05, 0.08), Vector3.BACK, Tuning.WHEEL_SPEED)
	Parts.mesh(wheel, Kit.torus(0.48, 0.055, 24, 8), Mat.wood(), Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	Parts.mesh(wheel, Kit.torus(0.48, 0.03, 24, 6), Mat.metal(), Vector3(0.0, 0.0, 0.045), Vector3(90.0, 0.0, 0.0))
	for i in 4:
		Parts.box(wheel, Vector3(0.9, 0.06, 0.05), Mat.wood_dark(), Vector3.ZERO, 0.02, Vector3(0.0, 0.0, 45.0 * i))
	Parts.mesh(wheel, Kit.cylinder(0.1, 0.16, 0.03, -1.0, 14), Mat.gold(), Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	# Small gear meshing below, turning the other way.
	# Axle through a bracket bolted to the leg keeps the gear anchored to the frame.
	Parts.rod(h, Vector3(0.38, 1.05, 0.17), Vector3(0.38, 1.05, -0.12), 0.03, Mat.metal(), 10)
	Parts.box(h, Vector3(0.16, 0.16, 0.1), Mat.wood_dark(), Vector3(0.36, 1.05, -0.06), 0.03)
	var gear := Parts.spinner(h, Vector3(0.38, 1.05, 0.1), Vector3.BACK, -Tuning.GEAR_SPEED)
	Parts.mesh(gear, Kit.gear(10, 0.2, 0.06, 0.08), Mat.metal(), Vector3.ZERO)
	Parts.mesh(gear, Kit.cylinder(0.06, 0.12, 0.02, -1.0, 10), Mat.gold(), Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	# Rope down to the shaft.
	Parts.rod(h, Vector3(-0.47, top_y + 0.05, 0.08), Vector3(-0.47, 0.35, 0.08), 0.015, Mat.solid(Color("d9c38f"), 0.95), 6)
	Parts.box(h, Vector3(0.22, 0.18, 0.22), Mat.wood_dark(), Vector3(-0.47, 0.3, 0.08), 0.04)


static func _lantern_post(root: Node3D, pos: Vector3) -> void:
	Parts.cyl(root, 0.035, 0.75, Mat.wood_dark(), pos, 0.01, -1.0, 8)
	Parts.box(root, Vector3(0.2, 0.04, 0.05), Mat.wood_dark(), pos + Vector3(0.08, 0.72, 0.0), 0.015)
	Parts.box(root, Vector3(0.1, 0.14, 0.1), Mat.lantern(), pos + Vector3(0.15, 0.6, 0.0), 0.025)
	Parts.box(root, Vector3(0.13, 0.03, 0.13), Mat.metal(), pos + Vector3(0.15, 0.68, 0.0), 0.01)
	Parts.night_light(root, pos + Vector3(0.15, 0.6, 0.0))
