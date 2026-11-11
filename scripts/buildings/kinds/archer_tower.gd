extends RefCounted
## Archer tower (3x3): tapered stone base, tall timber frame with braces and ladder, crenellated
## lookout deck under a pointed roof, pennants waving at the corners.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.block(root, Vector3(2.3, 0.95, 2.3), Mat.stone(), Vector3(0.0, g, 0.0), 0.12, 0.14)
	Parts.block(root, Vector3(2.02, 0.1, 2.02), Mat.stone_dark(), Vector3(0.0, g + 0.92, 0.0), 0.04)
	var y0: float = g + 1.0
	var deck_y: float = y0 + 1.45
	var leg: float = 0.66
	var wood: Material = Mat.wood()
	var dark: Material = Mat.wood_dark()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.rod(root, Vector3(sx * 0.82, y0, sz * 0.82), Vector3(sx * leg, deck_y, sz * leg), 0.1, wood, 0, true)
			Parts.block(root, Vector3(0.3, 0.12, 0.3), Mat.metal(), Vector3(sx * 0.82, y0 - 0.02, sz * 0.82), 0.04)
	# X braces on every face and a mid ring beam.
	var mid: float = y0 + 0.75
	for side: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			Parts.rod(root, Vector3(-0.76 * s, y0 + 0.1, 0.78 * side), Vector3(0.7 * s, deck_y - 0.1, 0.7 * side), 0.05, dark, 0, true)
			Parts.rod(root, Vector3(0.78 * side, y0 + 0.1, -0.76 * s), Vector3(0.7 * side, deck_y - 0.1, 0.7 * s), 0.05, dark, 0, true)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(1.6, 0.1, 0.1), dark, Vector3(0.0, mid, s * 0.75), 0.03)
		Parts.box(root, Vector3(0.1, 0.1, 1.6), dark, Vector3(s * 0.75, mid, 0.0), 0.03)
	# Ladder on the front.
	for s: float in [-1.0, 1.0]:
		Parts.rod(root, Vector3(s * 0.17, g, 1.2), Vector3(s * 0.17, deck_y, 0.86), 0.035, wood, 0, true)
	for i in 8:
		var t: float = (i + 0.6) / 8.6
		var p: Vector3 = Vector3(0.0, g, 1.2).lerp(Vector3(0.0, deck_y, 0.86), t)
		Parts.box(root, Vector3(0.34, 0.035, 0.05), dark, p, 0.012)
	# Deck and crenellated parapet.
	Parts.block(root, Vector3(2.0, 0.18, 2.0), Mat.planks(true), Vector3(0.0, deck_y, 0.0), 0.05)
	Parts.box(root, Vector3(2.06, 0.08, 2.06), dark, Vector3(0.0, deck_y + 0.02, 0.0), 0.03)
	var top: float = deck_y + 0.18
	for s: float in [-1.0, 1.0]:
		Parts.block(root, Vector3(1.96, 0.26, 0.12), Mat.planks(false), Vector3(0.0, top, s * 0.92), 0.03)
		Parts.block(root, Vector3(0.12, 0.26, 1.96), Mat.planks(false), Vector3(s * 0.92, top, 0.0), 0.03)
	for i in 4:
		var x: float = -0.72 + i * 0.48
		for s: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(0.26, 0.2, 0.16), dark, Vector3(x, top + 0.24, s * 0.92), 0.04)
			Parts.block(root, Vector3(0.16, 0.2, 0.26), dark, Vector3(s * 0.92, top + 0.24, x), 0.04)
	# Roof posts and roof.
	var roof_y: float = top + 1.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(0.12, roof_y - top, 0.12), wood, Vector3(sx * 0.82, top, sz * 0.82), 0.03)
	Parts.roof(root, Kit.hip_roof(2.3, 2.3, 1.15, 0.0, 0.12), Mat.roof_blue(), Vector3(0.0, roof_y, 0.0))
	Parts.mesh(root, Kit.sphere(0.09, 12, 8), Mat.gold(), Vector3(0.0, roof_y + 1.3, 0.0))
	Parts.flag(root, Vector3(0.0, roof_y + 1.32, 0.0), 0.55, Mat.CLOTH_RED, Vector2(0.42, 0.26))
	# Pennants on the front corners.
	Parts.flag(root, Vector3(-0.92, top + 0.44, 0.92), 0.5, Mat.CLOTH_BLUE, Vector2(0.3, 0.18), Mat.wood_dark())
	Parts.flag(root, Vector3(0.92, top + 0.44, -0.92), 0.5, Mat.CLOTH_BLUE, Vector2(0.3, 0.18), Mat.wood_dark())
	Parts.lantern(root, Vector3(0.0, top + 0.12, 0.99), 0.0)
	# Quiver with arrows on the deck.
	Parts.cyl(root, 0.09, 0.3, Mat.solid(Mat.CLOTH_RED, 0.8), Vector3(0.45, top, 0.45), 0.02)
	for i in 3:
		Parts.rod(root, Vector3(0.43 + i * 0.03, top + 0.25, 0.45), Vector3(0.4 + i * 0.05, top + 0.5, 0.42 + i * 0.02), 0.012, Mat.solid(Color("f2ead8"), 0.8), 6)
	return root
