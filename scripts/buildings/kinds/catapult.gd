extends RefCounted
## Catapult (3x3): wheeled timber base, A-frames with a padded stop bar, torsion skein, long arm with
## a big iron-rimmed wooden bowl, ratchet winch. Front (+Z) is the throw direction.
## Contract for the catapult system: ArmPivot (rotation.x 0 = cocked, bowl low at -Z; up to root meta
## `fire_angle_deg` = released against the stop bar), ArmPivot/Seat (Marker3D, -Z faces the throw),
## Winch (cranks around its local X), CountdownAnchor (Marker3D ~1 above the cocked catapult's top).

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")

const FIRE_ANGLE_DEG: float = 112.0
const AXLE := Vector3(0.0, 1.3, 0.55)
const ARM_LENGTH: float = 1.6
## Cocked arm direction in the YZ plane, measured from +Y toward +Z.
const ARM_REST_DEG: float = -118.0
const BOWL_RADIUS: float = 0.42
const BOWL_DEPTH: float = 0.34
const FRAME_X: float = 0.62
const G: float = 0.06


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), G, Mat.solid(Mat.DIRT_DARK, 0.95))
	_base(root)
	_frames(root)
	_arm(root)
	_winch(root)
	_props(root)
	root.set_meta(&"fire_angle_deg", FIRE_ANGLE_DEG)
	var top: float = Parts.local_aabb(root).end.y
	var anchor := Marker3D.new()
	anchor.name = "CountdownAnchor"
	anchor.position = Vector3(0.0, top + 1.0, 0.0)
	root.add_child(anchor)
	return root


static func _wheel(root: Node3D, pos: Vector3) -> void:
	var w := Parts.pivot(root, pos, Vector3(0.0, 0.0, 90.0), "Wheel")
	Parts.mesh(w, Kit.cylinder(0.34, 0.13, 0.04), Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.12, true), Vector3.ZERO)
	Parts.mesh(w, Kit.torus(0.335, 0.035, 28, 6), Mat.metal(), Vector3(0.0, 0.0, 0.0))
	Parts.mesh(w, Kit.cylinder(0.1, 0.2, 0.03, -1.0, 14), Mat.metal(), Vector3.ZERO)
	Parts.mesh(w, Kit.cylinder(0.05, 0.24, 0.015, -1.0, 10), Mat.gold(), Vector3.ZERO)
	for i in 4:
		Parts.box(w, Vector3(0.05, 0.08, 0.6), Mat.wood_dark(), Vector3(0.0, 0.07 * (1.0 if i < 2 else -1.0), 0.0), 0.015, Vector3(0.0, 45.0 * i, 0.0))


static func _base(root: Node3D) -> void:
	var y_axle: float = G + 0.34
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.82, 0.82]:
			_wheel(root, Vector3(sx * 0.88, y_axle, z))
		Parts.box(root, Vector3(0.2, 0.2, 2.4), Mat.planks(true, Mat.WOOD, Mat.WOOD_DARK, 0.1, true), Vector3(sx * 0.66, y_axle + 0.06, 0.0), 0.05)
		for z2: float in [-0.82, 0.82]:
			Parts.mesh(root, Kit.cylinder(0.04, 0.4, 0.01, -1.0, 10), Mat.metal(), Vector3(sx * 0.78, y_axle, z2), Vector3(0.0, 0.0, 90.0))
	# Low cross beams and a center spine; the cocked bowl rests on the padded spine block.
	for z: float in [-1.12, 0.0, 1.12]:
		Parts.box(root, Vector3(1.5, 0.16, 0.18), Mat.wood_dark(), Vector3(0.0, G + 0.16, z), 0.04)
	Parts.box(root, Vector3(0.2, 0.14, 2.3), Mat.wood_dark(), Vector3(0.0, G + 0.13, 0.0), 0.04)
	var bowl_z: float = AXLE.z + ARM_LENGTH * sin(deg_to_rad(ARM_REST_DEG))
	Parts.box(root, Vector3(0.34, 0.08, 0.34), Mat.solid(Color("8a3a2a"), 0.9), Vector3(0.0, G + 0.24, bowl_z), 0.035)


static func _frames(root: Node3D) -> void:
	var wood: Material = Mat.wood()
	var dark: Material = Mat.wood_dark()
	var rail_y: float = G + 0.5
	var stop_center: Vector3 = _stop_bar_center()
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * FRAME_X
		var axle := Vector3(x, AXLE.y, AXLE.z)
		Parts.rod(root, Vector3(x, rail_y, -0.45), axle, 0.075, wood, 0, true)
		Parts.rod(root, Vector3(x, rail_y, 1.15), axle, 0.075, wood, 0, true)
		Parts.rod(root, Vector3(x, rail_y + 0.35, -0.2), Vector3(x, rail_y + 0.35, 0.95), 0.05, dark, 0, true)
		# Upright carrying the padded stop bar, braced to the front of the rail.
		var up_z: float = stop_center.z + 0.02
		Parts.rod(root, Vector3(x, rail_y, up_z), Vector3(x, stop_center.y + 0.16, up_z), 0.07, wood, 0, true)
		Parts.rod(root, Vector3(x, rail_y, 1.2), Vector3(x, stop_center.y - 0.35, up_z + 0.04), 0.045, dark, 0, true)
		Parts.box(root, Vector3(0.2, 0.2, 0.22), Mat.metal(), axle, 0.04)
	Parts.mesh(root, Kit.cylinder(0.075, FRAME_X * 2.0 + 0.2, 0.02, -1.0, 14), Mat.wood_dark(), stop_center, Vector3(0.0, 0.0, 90.0))
	Parts.mesh(root, Kit.cylinder(0.11, 0.5, 0.05, -1.0, 16), Mat.solid(Color("8a3a2a"), 0.9), stop_center, Vector3(0.0, 0.0, 90.0))
	for s: float in [-1.0, 1.0]:
		Parts.mesh(root, Kit.torus(0.115, 0.018, 16, 6), Mat.solid(Color("d9c38f"), 0.95), stop_center + Vector3(s * 0.2, 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
	# Torsion skein around the axle: thick rope bundle with wraps.
	Parts.mesh(root, Kit.cylinder(0.15, FRAME_X * 2.0 - 0.1, 0.05, -1.0, 16), Mat.solid(Color("c9ae76"), 0.95), AXLE, Vector3(0.0, 0.0, 90.0))
	for i in 5:
		var x2: float = lerpf(-FRAME_X + 0.15, FRAME_X - 0.15, i / 4.0)
		Parts.mesh(root, Kit.torus(0.155, 0.03, 16, 6), Mat.solid(Color("a88a52"), 0.95), AXLE + Vector3(x2, 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
	Parts.mesh(root, Kit.cylinder(0.05, FRAME_X * 2.0 + 0.3, 0.015, -1.0, 12), Mat.metal(), AXLE, Vector3(0.0, 0.0, 90.0))


## Where the released arm meets the stop bar (padded side in front of the arm).
static func _stop_bar_center() -> Vector3:
	var final_deg: float = ARM_REST_DEG + FIRE_ANGLE_DEG
	var a: float = deg_to_rad(final_deg)
	var along := Vector3(0.0, cos(a), sin(a))
	var normal := Vector3(0.0, -sin(a), cos(a))
	return AXLE + along * 1.0 + normal * (0.07 + 0.11)


static func _arm(root: Node3D) -> void:
	var pivot := Parts.pivot(root, AXLE, Vector3.ZERO, "ArmPivot")
	var a: float = deg_to_rad(ARM_REST_DEG)
	var dir := Vector3(0.0, cos(a), sin(a))
	var end: Vector3 = dir * ARM_LENGTH
	Parts.rod(pivot, Vector3.ZERO, end - dir * 0.15, 0.075, Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.15, true), 0, true)
	Parts.mesh(pivot, Kit.cylinder(0.11, 0.24, 0.03, -1.0, 14), Mat.metal(), Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
	for t: float in [0.35, 0.7]:
		Parts.box(pivot, Vector3(0.19, 0.06, 0.19), Mat.metal(), dir * ARM_LENGTH * t, 0.02, Vector3(rad_to_deg(a), 0.0, 0.0))
	# Bowl: open side up while cocked so the rider can hop in.
	var bowl_base: Vector3 = end + Vector3(0.0, -BOWL_DEPTH * 0.55, 0.0)
	var r: float = BOWL_RADIUS
	var d: float = BOWL_DEPTH
	var wall: float = 0.07
	var pts := PackedVector2Array()
	var steps: int = 6
	for k in steps + 1:
		var t2: float = float(k) / steps * PI * 0.5
		pts.append(Vector2(sin(t2) * r, d * (1.0 - cos(t2))))
	pts.append(Vector2(r - wall, d))
	for k2 in range(steps, -1, -1):
		var t3: float = float(k2) / steps * PI * 0.5
		pts.append(Vector2(sin(t3) * (r - wall), wall + (d - wall) * (1.0 - cos(t3))))
	pts[pts.size() - 1] = Vector2(0.0, wall)
	# Bucket groups the bowl, its iron rim and gold band; origin at the bowl's bottom so it can squash.
	var bucket := Parts.pivot(pivot, bowl_base, Vector3.ZERO, "Bucket")
	Parts.mesh(bucket, Kit.lathe(pts, 0, 40.0), Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.14, true), Vector3.ZERO)
	Parts.mesh(bucket, Kit.torus(r - wall * 0.5, 0.045, 0, 8), Mat.metal(), Vector3(0.0, d, 0.0))
	Parts.mesh(bucket, Kit.torus(r * 0.86, 0.035, 0, 6), Mat.gold(), Vector3(0.0, d * 0.45, 0.0))
	Parts.box(pivot, Vector3(0.2, 0.14, 0.3), Mat.metal(), end + Vector3(0.0, -BOWL_DEPTH * 0.45, 0.12), 0.03)
	var seat := Marker3D.new()
	seat.name = "Seat"
	seat.position = bowl_base + Vector3(0.0, wall, 0.0)
	seat.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	pivot.add_child(seat)


static func _winch(root: Node3D) -> void:
	var pos := Vector3(0.98, G + 0.66, -0.35)
	for z: float in [-0.13, 0.13]:
		Parts.block(root, Vector3(0.1, 0.24, 0.08), Mat.wood_dark(), Vector3(0.86, G + 0.5, pos.z + z), 0.025)
	var winch := Parts.pivot(root, pos, Vector3.ZERO, "Winch")
	Parts.mesh(winch, Kit.cylinder(0.1, 0.3, 0.02, -1.0, 14), Mat.solid(Color("c9ae76"), 0.95), Vector3(-0.1, 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
	Parts.mesh(winch, Kit.gear(12, 0.17, 0.05, 0.06), Mat.metal(), Vector3(0.08, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))
	Parts.box(winch, Vector3(0.05, 0.36, 0.06), Mat.metal(), Vector3(0.15, 0.13, 0.0), 0.02)
	Parts.rod(winch, Vector3(0.15, 0.3, 0.0), Vector3(0.3, 0.3, 0.0), 0.03, Mat.wood(), 8)
	Parts.mesh(winch, Kit.sphere(0.045, 10, 6), Mat.gold(), Vector3(0.31, 0.3, 0.0))
	# Pawl that clicks on the ratchet gear (static).
	Parts.box(root, Vector3(0.04, 0.05, 0.22), Mat.metal_light(), pos + Vector3(0.08, 0.2, 0.08), 0.015, Vector3(-30.0, 0.0, 0.0))


static func _props(root: Node3D) -> void:
	var stop: Vector3 = _stop_bar_center()
	Parts.flag(root, Vector3(-FRAME_X, stop.y + 0.2, stop.z + 0.02), 0.6, Mat.CLOTH_RED, Vector2(0.42, 0.26))
	Parts.lantern(root, Vector3(FRAME_X + 0.1, stop.y - 0.55, stop.z + 0.02), 90.0)
	# Ammo stones stacked at the front-left.
	var pile := Parts.pivot(root, Vector3(-1.0, G, 1.0), Vector3.ZERO, "Ammo")
	var spots: Array[Vector3] = [Vector3(-0.12, 0.13, -0.1), Vector3(0.14, 0.13, -0.06), Vector3(0.0, 0.13, 0.14), Vector3(0.02, 0.33, 0.0)]
	for i in spots.size():
		Parts.mesh(pile, Kit.rock(70 + i, 3, 6), Mat.rock(), spots[i], Vector3(0.0, 40.0 * i, 0.0), Vector3(0.3, 0.3, 0.3))
	# Painted target on a stake at the front-right.
	var target := Parts.pivot(root, Vector3(0.98, G, 1.08), Vector3(-8.0, -20.0, 0.0), "Target")
	Parts.rod(target, Vector3(0.0, 0.0, -0.05), Vector3(0.0, 0.62, -0.05), 0.03, Mat.wood_dark(), 8)
	var rings: Array = [[0.27, Mat.solid(Color("f4ecd8"), 0.8)], [0.2, Mat.solid(Mat.CLOTH_RED, 0.7)], [0.13, Mat.solid(Color("f4ecd8"), 0.8)], [0.06, Mat.solid(Mat.CLOTH_RED, 0.7)]]
	for i in rings.size():
		Parts.mesh(target, Kit.cylinder(rings[i][0], 0.04, 0.012, -1.0, 24), rings[i][1], Vector3(0.0, 0.5, 0.0 + i * 0.012), Vector3(90.0, 0.0, 0.0))
