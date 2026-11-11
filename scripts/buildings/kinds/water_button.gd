extends RefCounted
## Water tower button (1x1): low mushroom button (total height <= 0.2) on a stone and metal base,
## yellow/black hazard ring on the ground. ButtonCap moves down ~0.06 when pressed (driven externally).

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")

const RING_SEGMENTS: int = 14


static func build() -> Node3D:
	var root := Node3D.new()
	_hazard_ring(root, 0.33, 0.45)
	Parts.cyl(root, 0.31, 0.06, Mat.stone_dark(), Vector3.ZERO, 0.025, 0.29)
	Parts.cyl(root, 0.25, 0.04, Mat.metal(), Vector3(0.0, 0.055, 0.0), 0.015, 0.23)
	for i in 4:
		var a: float = TAU * (i + 0.5) / 4.0
		Parts.mesh(root, Kit.dome(0.025, 0.02, 8, 3), Mat.gold(), Vector3(cos(a) * 0.2, 0.093, sin(a) * 0.2))
	var cap := Parts.pivot(root, Vector3(0.0, 0.09, 0.0), Vector3.ZERO, "ButtonCap")
	Parts.cyl(cap, 0.1, 0.05, Mat.metal_light(), Vector3.ZERO, 0.015)
	Parts.mesh(cap, Kit.dome(0.21, 0.07, 0, 0), Mat.button_red(), Vector3(0.0, 0.035, 0.0))
	Parts.mesh(cap, Kit.cylinder(0.21, 0.025, 0.012), Mat.button_red(), Vector3(0.0, 0.035, 0.0))
	for spot: Vector2 in [Vector2(0.07, 0.04), Vector2(-0.08, -0.05), Vector2(-0.02, 0.09), Vector2(0.1, -0.1)]:
		var k: float = spot.length() / 0.21
		var y: float = 0.035 + 0.07 * sqrt(maxf(0.0, 1.0 - k * k)) - 0.006
		Parts.mesh(cap, Kit.dome(0.03, 0.012, 10, 3), Mat.solid(Color("fff4e0"), 0.4), Vector3(spot.x, y, spot.y))
	return root


## Flat ring of alternating yellow/black sectors lying on the ground.
static func _hazard_ring(root: Node3D, inner: float, outer: float) -> void:
	var arc: float = TAU / RING_SEGMENTS
	var pts := PackedVector2Array()
	var steps: int = 4
	for k in steps + 1:
		var a: float = arc * k / steps
		pts.append(Vector2(cos(a), sin(a)) * outer)
	for k in range(steps, -1, -1):
		var a2: float = arc * k / steps
		pts.append(Vector2(cos(a2), sin(a2)) * inner)
	var sector := Kit.extrude(pts, 0.016, "hazard_sector_%d" % RING_SEGMENTS)
	var yellow: Material = Mat.solid(Color("ffc61a"), 0.6)
	var black: Material = Mat.solid(Color("23232a"), 0.7)
	for i in RING_SEGMENTS:
		Parts.mesh(root, sector, yellow if i % 2 == 0 else black, Vector3(0.0, 0.008, 0.0), Vector3(-90.0, rad_to_deg(arc * i), 0.0))
