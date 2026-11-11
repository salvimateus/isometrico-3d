extends RefCounted
## Gold storage (3x3): plank platform with a big iron-strapped chest, lid thrown open on a heap of
## gold, coins spilling out and stacked bars.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.block(root, Vector3(2.44, 0.2, 2.44), Mat.planks(true), Vector3(0.0, g, 0.0), 0.06)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(0.26, 0.26, 0.26), Mat.stone(), Vector3(sx * 1.08, g, sz * 1.08), 0.06)
	var base: float = g + 0.2
	var chest := Parts.pivot(root, Vector3(-0.12, base, -0.05), Vector3.ZERO, "Chest")
	var w: float = 1.75
	var h: float = 0.92
	var d: float = 1.3
	Parts.block(chest, Vector3(w, h, d), Mat.planks(true, Mat.WOOD, Mat.WOOD_DARK, 0.18), Vector3.ZERO, 0.08)
	# Iron straps and gold corner guards.
	for s: float in [-1.0, 1.0]:
		Parts.block(chest, Vector3(0.14, h + 0.04, d + 0.06), Mat.metal(), Vector3(s * w * 0.3, -0.02, 0.0), 0.04)
	Parts.box(chest, Vector3(w + 0.06, 0.1, d + 0.06), Mat.metal(), Vector3(0.0, h - 0.05, 0.0), 0.04)
	Parts.box(chest, Vector3(w + 0.06, 0.1, d + 0.06), Mat.metal(), Vector3(0.0, 0.08, 0.0), 0.04)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(chest, Vector3(0.16, h + 0.04, 0.16), Mat.gold(), Vector3(sx * (w * 0.5 - 0.04), -0.02, sz * (d * 0.5 - 0.04)), 0.05)
	# Carry handles on the sides and a gold strap across the back.
	for s: float in [-1.0, 1.0]:
		Parts.box(chest, Vector3(0.06, 0.12, 0.3), Mat.metal(), Vector3(s * (w * 0.5 + 0.03), h * 0.55, 0.0), 0.02)
		Parts.mesh(chest, Kit.torus(0.11, 0.022, 14, 6), Mat.gold(), Vector3(s * (w * 0.5 + 0.07), h * 0.47, 0.0), Vector3(0.0, 0.0, 90.0))
	Parts.box(chest, Vector3(0.5, 0.1, 0.05), Mat.gold(), Vector3(0.0, h * 0.5, -d * 0.5 - 0.025), 0.02)
	# Lock plate on the front.
	Parts.box(chest, Vector3(0.28, 0.32, 0.06), Mat.gold(), Vector3(0.0, h - 0.24, d * 0.5 + 0.04), 0.04)
	Parts.mesh(chest, Kit.arch(0.08, 0.12, 0.04), Mat.opening(), Vector3(0.0, h - 0.33, d * 0.5 + 0.075))
	# Gold heap filling the chest.
	Parts.gold_heap(chest, Vector3(0.0, h - 0.06, 0.05), 0.78, 0.42, 21, 14)
	# Open lid hinged at the back edge.
	var hinge := Parts.pivot(chest, Vector3(0.0, h, -d * 0.5), Vector3(-100.0, 0.0, 0.0), "Lid")
	Parts.box(hinge, Vector3(w, 0.2, d), Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.18, true), Vector3(0.0, 0.1, d * 0.5), 0.07)
	for s: float in [-1.0, 1.0]:
		Parts.box(hinge, Vector3(0.14, 0.24, d + 0.04), Mat.metal(), Vector3(s * w * 0.3, 0.1, d * 0.5), 0.04)
	Parts.box(hinge, Vector3(w + 0.04, 0.24, 0.12), Mat.gold(), Vector3(0.0, 0.1, d - 0.04), 0.04)
	# Coins spilled over the front and on the platform.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 16:
		var p := Vector3(rng.randf_range(-1.05, 1.05), base + 0.02, rng.randf_range(0.6, 1.1))
		if i < 5:
			p = Vector3(rng.randf_range(0.75, 1.1), base + 0.02, rng.randf_range(-1.0, 0.5))
		Parts.coin(root, p, Vector3(rng.randf_range(-12.0, 12.0), rng.randf() * 360.0, rng.randf_range(-12.0, 12.0)))
	Parts.gold_heap(root, Vector3(0.55, base, 0.78), 0.26, 0.14, 5, 4)
	# Lamp post on the back-right corner.
	Parts.cyl(root, 0.035, 0.85, Mat.wood_dark(), Vector3(1.0, base, -1.0), 0.01, -1.0, 8)
	Parts.box(root, Vector3(0.05, 0.04, 0.2), Mat.wood_dark(), Vector3(1.0, base + 0.84, -0.92), 0.015)
	Parts.lantern(root, Vector3(1.0, base + 0.7, -0.86), 0.0)
	# Stacked gold bars at the front-left.
	var bars := Parts.pivot(root, Vector3(-0.78, base, 0.82), Vector3(0.0, 12.0, 0.0), "Bars")
	var bar := Kit.rounded_box(Vector3(0.34, 0.12, 0.16), 0.035, 0.22)
	for i in 3:
		Parts.mesh(bars, bar, Mat.gold(), Vector3(0.0, 0.06, -0.18 + i * 0.18))
	for i in 2:
		Parts.mesh(bars, bar, Mat.gold(), Vector3(0.0, 0.18, -0.09 + i * 0.18))
	Parts.mesh(bars, bar, Mat.gold(), Vector3(0.0, 0.3, 0.0))
	return root
