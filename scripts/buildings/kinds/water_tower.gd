extends RefCounted
## Water tower (3x3): stone base, tall braced timber frame with ladder, deck with a giant iron-hooped
## wooden tub hinged on its front-bottom edge so it can dump forward (+Z).
## Contract for the liquid system: TankPivot (rotate +X up to ~110 deg to tip toward +Z),
## TankPivot/PourPoint (Marker3D on the pouring rim), TankPivot/FillSurface (water disc, height and
## visibility driven externally).

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")

const TUB_RADIUS_BOTTOM: float = 0.8
const TUB_RADIUS_TOP: float = 1.1
const TUB_HEIGHT: float = 1.42
const TUB_WALL: float = 0.08
## Tub center sits this far behind the hinge (hinge is on the tub's front-bottom edge).
const TUB_BACK_OFFSET: float = 0.8
## Hinge on the deck's front edge; the deck stops there so the tub swings clear when tipping.
const HINGE_Z: float = 0.85
const DECK_BACK: float = -1.05


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.block(root, Vector3(2.4, 1.1, 2.4), Mat.stone(), Vector3(0.0, g, 0.0), 0.12, 0.14)
	Parts.block(root, Vector3(2.1, 0.1, 2.1), Mat.stone_dark(), Vector3(0.0, g + 1.06, 0.0), 0.04)
	var y0: float = g + 1.14
	var deck_y: float = y0 + 3.35
	_frame(root, y0, deck_y)
	_ladder(root, g, deck_y)
	_deck(root, deck_y)
	var deck_top: float = deck_y + 0.2
	_gantry(root, deck_top)
	_tub(root, deck_top)
	_sign(root, g)
	Parts.lantern(root, Vector3(-0.62, g + 0.85, 1.12), 0.0)
	Parts.lantern(root, Vector3(-0.98, deck_top + 0.3, HINGE_Z - 0.02), 0.0)
	return root


static func _frame(root: Node3D, y0: float, deck_y: float) -> void:
	var wood: Material = Mat.wood()
	var dark: Material = Mat.wood_dark()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.rod(root, Vector3(sx * 0.86, y0, sz * 0.86), Vector3(sx * 0.72, deck_y, sz * 0.72), 0.11, wood, 0, true)
			Parts.block(root, Vector3(0.32, 0.12, 0.32), Mat.metal(), Vector3(sx * 0.86, y0 - 0.02, sz * 0.86), 0.04)
	var mid: float = (y0 + deck_y) * 0.5
	for side: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			for band: int in 2:
				var ya: float = lerpf(y0, deck_y, band * 0.5) + 0.1
				var yb: float = lerpf(y0, deck_y, (band + 1) * 0.5) - 0.1
				var ra: float = lerpf(0.84, 0.72, band * 0.5)
				var rb: float = lerpf(0.84, 0.72, (band + 1) * 0.5)
				Parts.rod(root, Vector3(-ra * s, ya, ra * side), Vector3(rb * s, yb, rb * side), 0.05, dark, 0, true)
				Parts.rod(root, Vector3(ra * side, ya, -ra * s), Vector3(rb * side, yb, rb * s), 0.05, dark, 0, true)
		var r: float = 0.79
		Parts.box(root, Vector3(1.7, 0.12, 0.12), dark, Vector3(0.0, mid, side * r), 0.035)
		Parts.box(root, Vector3(0.12, 0.12, 1.7), dark, Vector3(side * r, mid, 0.0), 0.035)
	# Feed pipe running up the back leg.
	Parts.rod(root, Vector3(-0.55, y0, -0.95), Vector3(-0.5, deck_y, -0.8), 0.06, Mat.metal(), 12)
	for t: float in [0.25, 0.6, 0.9]:
		Parts.box(root, Vector3(0.18, 0.06, 0.18), Mat.metal_light(), Vector3(-0.55, y0, -0.95).lerp(Vector3(-0.5, deck_y, -0.8), t), 0.02)


static func _ladder(root: Node3D, g: float, deck_y: float) -> void:
	var a := Vector3(1.28, g, 0.0)
	var b := Vector3(1.0, deck_y + 0.25, 0.0)
	for s: float in [-1.0, 1.0]:
		Parts.rod(root, a + Vector3(0.0, 0.0, s * 0.18), b + Vector3(0.0, 0.0, s * 0.18), 0.035, Mat.wood(), 0, true)
	var rungs: int = 14
	for i in rungs:
		var p: Vector3 = a.lerp(b, (i + 0.6) / (rungs + 0.4))
		Parts.box(root, Vector3(0.05, 0.035, 0.36), Mat.wood_dark(), p, 0.012)


static func _deck(root: Node3D, deck_y: float) -> void:
	var depth: float = HINGE_Z - DECK_BACK
	var cz: float = (HINGE_Z + DECK_BACK) * 0.5
	Parts.block(root, Vector3(2.1, 0.2, depth), Mat.planks(true), Vector3(0.0, deck_y, cz), 0.05)
	Parts.box(root, Vector3(2.16, 0.08, depth + 0.06), Mat.wood_dark(), Vector3(0.0, deck_y + 0.02, cz), 0.03)
	var top: float = deck_y + 0.2
	# The tub fills the deck, so only stout corner posts with gold caps frame it.
	for x: float in [-0.98, 0.98]:
		for z: float in [DECK_BACK + 0.07, HINGE_Z - 0.07]:
			Parts.block(root, Vector3(0.13, 0.32, 0.13), Mat.wood_dark(), Vector3(x, top, z), 0.035)
			Parts.mesh(root, Kit.sphere(0.06, 10, 6), Mat.gold(), Vector3(x, top + 0.36, z))


## Small crane arm on the back rail with a solid pulley wheel and a rope down to a stone counterweight.
static func _gantry(root: Node3D, deck_top: float) -> void:
	var wood: Material = Mat.wood()
	var post_h: float = 1.15
	var base := Vector3(0.98, deck_top + 0.3, DECK_BACK + 0.07)
	Parts.block(root, Vector3(0.16, post_h, 0.16), wood, base, 0.04)
	Parts.box(root, Vector3(0.22, 0.08, 0.22), Mat.metal(), base + Vector3(0.0, post_h - 0.02, 0.0), 0.025)
	var tip := base + Vector3(0.0, post_h + 0.12, -0.15)
	Parts.rod(root, base + Vector3(0.0, post_h - 0.05, 0.12), tip, 0.06, Mat.wood_dark(), 0, true)
	Parts.rod(root, base + Vector3(0.0, post_h * 0.55, 0.0), tip + Vector3(0.0, -0.08, 0.1), 0.035, Mat.wood_dark(), 0, true)
	var wheel := Parts.pivot(root, tip + Vector3(0.0, -0.14, 0.0), Vector3(0.0, 0.0, 90.0), "Pulley")
	Parts.mesh(wheel, Kit.cylinder(0.15, 0.07, 0.02, -1.0, 20), Mat.metal(), Vector3.ZERO)
	Parts.mesh(wheel, Kit.cylinder(0.06, 0.1, 0.02, -1.0, 12), Mat.gold(), Vector3.ZERO)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(0.03, 0.22, 0.06), Mat.metal(), tip + Vector3(s * 0.06, -0.08, 0.0), 0.01)
	var rope: Material = Mat.solid(Color("d9c38f"), 0.95)
	var drop_x: float = tip.x
	var drop_z: float = tip.z
	var weight_y: float = deck_top - 0.7
	Parts.rod(root, Vector3(drop_x, tip.y - 0.14, drop_z), Vector3(drop_x, weight_y + 0.2, drop_z), 0.018, rope, 6)
	Parts.rod(root, Vector3(drop_x, tip.y - 0.02, tip.z + 0.1), base + Vector3(0.0, 0.45, -0.09), 0.018, rope, 6)
	Parts.box(root, Vector3(0.08, 0.05, 0.05), Mat.metal(), base + Vector3(0.0, 0.45, -0.1), 0.01)
	Parts.box(root, Vector3(0.36, 0.38, 0.32), Mat.stone_dark(), Vector3(drop_x, weight_y, drop_z), 0.06)
	Parts.box(root, Vector3(0.4, 0.06, 0.36), Mat.metal(), Vector3(drop_x, weight_y + 0.11, drop_z), 0.02)
	Parts.box(root, Vector3(0.4, 0.06, 0.36), Mat.metal(), Vector3(drop_x, weight_y - 0.11, drop_z), 0.02)


## Tub on its front-bottom hinge. Everything that tips lives under TankPivot.
static func _tub(root: Node3D, deck_top: float) -> void:
	var hinge_y: float = deck_top + 0.12
	var hinge_z: float = HINGE_Z
	# Fixed hinge blocks and the chocks the tub rests on.
	for s: float in [-1.0, 1.0]:
		Parts.block(root, Vector3(0.18, 0.2, 0.26), Mat.metal(), Vector3(s * 0.95, deck_top, hinge_z - 0.04), 0.035)
		Parts.block(root, Vector3(0.18, 0.12, 1.5), Mat.wood_dark(), Vector3(s * 0.42, deck_top, hinge_z - TUB_BACK_OFFSET), 0.03)
	var pivot := Parts.pivot(root, Vector3(0.0, hinge_y, hinge_z), Vector3.ZERO, "TankPivot")
	Parts.mesh(pivot, Kit.cylinder(0.06, 2.0, 0.015, -1.0, 14), Mat.metal(), Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
	for s: float in [-1.0, 1.0]:
		Parts.mesh(pivot, Kit.cylinder(0.11, 0.08, 0.02, -1.0, 14), Mat.gold(), Vector3(s * 1.0, 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
	var c := Vector3(0.0, 0.0, -TUB_BACK_OFFSET)
	var rb: float = TUB_RADIUS_BOTTOM
	var rt: float = TUB_RADIUS_TOP
	var h: float = TUB_HEIGHT
	var w: float = TUB_WALL
	var profile := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(rb - 0.04, 0.0), Vector2(rb, 0.04), Vector2(rt, h - 0.04), Vector2(rt - 0.015, h),
		Vector2(rt - w, h), Vector2(rb - w + 0.02, w + 0.05), Vector2(0.0, w + 0.05),
	])
	Parts.mesh(pivot, Kit.lathe(profile, 0, 40.0), Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.17, true), c)
	# Thick iron hoops following the taper, plus a gold rim band.
	for t: float in [0.1, 0.48, 0.84]:
		var r: float = lerpf(rb, rt, t) + 0.035
		Parts.mesh(pivot, Kit.torus(r, 0.06, 0, 8), Mat.metal(), c + Vector3(0.0, h * t, 0.0))
	Parts.mesh(pivot, Kit.torus(rt - w * 0.5, 0.06, 0, 8), Mat.gold(), c + Vector3(0.0, h, 0.0))
	# Big side handles: a ring on each flank tied down to the axle ends by iron straps.
	for s: float in [-1.0, 1.0]:
		var side_r: float = lerpf(rb, rt, 0.48)
		Parts.box(pivot, Vector3(0.1, 0.34, 0.4), Mat.metal(), c + Vector3(s * (side_r + 0.06), h * 0.48, 0.0), 0.04)
		Parts.mesh(pivot, Kit.torus(0.2, 0.045, 18, 8), Mat.gold(), c + Vector3(s * (side_r + 0.13), h * 0.48 + 0.2, 0.0), Vector3(0.0, 0.0, 90.0))
		Parts.rod(pivot, c + Vector3(s * (side_r + 0.08), h * 0.48 - 0.12, 0.12), Vector3(s * 1.0, 0.0, 0.0), 0.045, Mat.metal(), 10)
		Parts.rod(pivot, c + Vector3(s * (rb + 0.05), 0.12, -0.3), Vector3(s * 1.0, 0.0, 0.0), 0.04, Mat.metal(), 10)
	# Marked pouring lip on the front rim.
	var lip := Parts.pivot(pivot, c + Vector3(0.0, h - 0.03, rt - 0.15), Vector3(-12.0, 0.0, 0.0), "Lip")
	Parts.box(lip, Vector3(0.72, 0.07, 0.24), Mat.metal(), Vector3(0.0, 0.0, 0.06), 0.03)
	Parts.box(lip, Vector3(0.76, 0.05, 0.05), Mat.gold(), Vector3(0.0, 0.03, 0.17), 0.02)
	for x: float in [-0.38, 0.38]:
		Parts.box(lip, Vector3(0.06, 0.14, 0.22), Mat.metal(), Vector3(x, 0.05, 0.06), 0.02)
	var pour := Marker3D.new()
	pour.name = "PourPoint"
	pour.position = c + Vector3(0.0, h - 0.02, rt + 0.06)
	pivot.add_child(pour)
	# Unit disc scaled to the inner wall radius at its height. Metadata lets the liquid system keep it
	# fitting the tapered wall when it moves the surface (local Y inside TankPivot).
	var y_low: float = w + 0.06
	var y_high: float = h - 0.06
	var r_low: float = rb - w + 0.015
	var r_high: float = rt - w - 0.005
	var fill_y: float = h - 0.14
	var fill_r: float = lerpf(r_low, r_high, (fill_y - y_low) / (y_high - y_low))
	var fill := Parts.mesh(pivot, Kit.cylinder(1.0, 0.03, 0.0, -1.0, 0), Mat.water(), c + Vector3(0.0, fill_y, 0.0), Vector3.ZERO, Vector3(fill_r, 1.0, fill_r))
	fill.name = "FillSurface"
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.set_meta(&"y_empty", y_low)
	fill.set_meta(&"y_full", y_high)
	fill.set_meta(&"radius_empty", r_low)
	fill.set_meta(&"radius_full", r_high)


## Wooden sign with a painted water drop on the front of the stone base.
static func _sign(root: Node3D, g: float) -> void:
	var sg := Parts.pivot(root, Vector3(0.18, g + 0.62, 1.2), Vector3(-6.0, 0.0, 0.0), "Sign")
	Parts.box(sg, Vector3(0.62, 0.62, 0.07), Mat.planks(true, Mat.WOOD, Mat.WOOD_DARK, 0.15, true), Vector3.ZERO, 0.04)
	Parts.box(sg, Vector3(0.68, 0.06, 0.09), Mat.wood_dark(), Vector3(0.0, 0.31, 0.0), 0.02)
	Parts.box(sg, Vector3(0.68, 0.06, 0.09), Mat.wood_dark(), Vector3(0.0, -0.31, 0.0), 0.02)
	var outline := PackedVector2Array([Vector2(0.0, 0.24)])
	var steps: int = 16
	for i in steps + 1:
		var ang: float = deg_to_rad(lerpf(60.0, -240.0, float(i) / steps))
		outline.append(Vector2(cos(ang), sin(ang)) * 0.15 + Vector2(0.0, -0.05))
	Parts.mesh(sg, Kit.extrude(outline, 0.03, "water_drop"), Mat.solid(Mat.WATER, 0.4), Vector3(0.0, 0.0, 0.045))
	Parts.mesh(sg, Kit.sphere(0.03, 8, 5), Mat.solid(Color("e8fbff"), 0.3), Vector3(-0.05, 0.0, 0.065))
