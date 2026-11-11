extends RefCounted
## Town hall (4x4): stone plinth, half-timbered hall, hip roof with dormers, cupola with flag, corner turrets.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(3.66, 3.66), 0.14)
	var y: float = 0.14
	# Plinth.
	Parts.block(root, Vector3(3.1, 0.95, 3.1), Mat.stone(), Vector3(0.0, y, 0.0), 0.12, 0.05)
	y += 0.95
	Parts.block(root, Vector3(2.98, 0.09, 2.98), Mat.gold(), Vector3(0.0, y - 0.02, 0.0), 0.04)
	y += 0.07
	# Hall body.
	var body_h: float = 1.2
	var half: float = 1.22
	Parts.block(root, Vector3(half * 2.0, body_h, half * 2.0), Mat.plaster(), Vector3(0.0, y, 0.0), 0.06)
	_timber(root, y, body_h, half)
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		var offset: float = 0.88 if yaw == 0.0 else 0.6
		var width: float = 0.32 if yaw == 0.0 else 0.36
		for s: float in [-1.0, 1.0]:
			Parts.window(root, _on_face(yaw, half + 0.02, s * offset, y + 0.5), yaw, Vector2(width, 0.46), true)
	_portal(root)
	_back_entrance(root)
	y += body_h
	# Main hip roof.
	var roof_y: float = y - 0.02
	Parts.roof(root, Kit.hip_roof(3.08, 3.08, 1.25, 0.7, 0.16), Mat.roof_red(), Vector3(0.0, roof_y, 0.0))
	Parts.mesh(root, Kit.cylinder(0.08, 0.8, 0.03, -1.0, 12), Mat.roof(Mat.ROOF_RED_SHADOW, Mat.ROOF_RED_SHADOW.darkened(0.2)), Vector3(0.0, roof_y + 1.41, 0.0), Vector3(90.0, 0.0, 0.0))
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		_dormer(root, _on_face(yaw, 0.95, 0.0, roof_y + 0.42), yaw)
	# Cupola.
	var cy: float = roof_y + 1.3
	Parts.block(root, Vector3(0.82, 0.62, 0.82), Mat.plaster(), Vector3(0.0, cy, 0.0), 0.05)
	_timber(root, cy, 0.62, 0.41, 0.11)
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		Parts.window(root, _on_face(yaw, 0.43, 0.0, cy + 0.33), yaw, Vector2(0.24, 0.3), true)
	Parts.roof(root, Kit.hip_roof(1.12, 1.12, 0.8, 0.0, 0.1), Mat.roof_red(), Vector3(0.0, cy + 0.6, 0.0))
	Parts.mesh(root, Kit.sphere(0.09, 12, 8), Mat.gold(), Vector3(0.0, cy + 1.52, 0.0))
	Parts.flag(root, Vector3(0.0, cy + 1.55, 0.0), 0.75, Mat.CLOTH_RED, Vector2(0.6, 0.36))
	# Corner turrets on the screen-left and screen-right corners.
	_turret(root, Vector3(-1.36, 0.14, 1.36))
	_turret(root, Vector3(1.36, 0.14, -1.36))
	return root


## Stone entrance portal sized for ~1 unit tall villagers: 1.2 tall door, crest and a small gable roof
## kept narrow and low so it clears the hall windows and the main eave.
static func _portal(root: Node3D) -> void:
	var p := Parts.pivot(root, Vector3(0.0, 0.14, 1.42), Vector3.ZERO, "Portal")
	var top: float = 1.36
	Parts.block(p, Vector3(1.02, top, 0.46), Mat.stone(), Vector3.ZERO, 0.08)
	Parts.block(p, Vector3(1.1, 0.08, 0.52), Mat.gold(), Vector3(0.0, top - 0.06, 0.0), 0.035)
	Parts.mesh(p, Kit.prism(1.0, 0.18, 0.36), Mat.stone(), Vector3(0.0, top, 0.06))
	Parts.roof(p, Kit.gable_roof(1.14, 0.46, 0.2, 0.09), Mat.roof_red(), Vector3(0.0, top - 0.02, 0.1))
	Parts.mesh(p, Kit.sphere(0.055, 10, 6), Mat.gold(), Vector3(0.0, top + 0.29, 0.32))
	Parts.door(p, Vector3(0.0, 0.0, 0.24), 0.0, Vector2(0.72, 1.2))
	Parts.mesh(p, Kit.cylinder(0.1, 0.04, 0.015, -1.0, 20), Mat.gold(), Vector3(0.0, top + 0.07, 0.25), Vector3(90.0, 0.0, 0.0))
	Parts.mesh(p, Kit.cylinder(0.065, 0.03, 0.012, -1.0, 16), Mat.solid(Mat.CLOTH_RED, 0.7), Vector3(0.0, top + 0.07, 0.27), Vector3(90.0, 0.0, 0.0))
	Parts.block(p, Vector3(1.0, 0.1, 0.24), Mat.stone_dark(), Vector3(0.0, -0.04, 0.32), 0.04)
	for s: float in [-1.0, 1.0]:
		Parts.lantern(p, Vector3(s * 0.64, 0.95, 0.12))


static func _timber(root: Node3D, y: float, h: float, half: float, t: float = 0.16) -> void:
	var wood: Material = Mat.wood_dark()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(t, h + 0.02, t), wood, Vector3(sx * half, y - 0.01, sz * half), t * 0.3)
	var span: float = half * 2.0 + t
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(span, t * 0.85, t * 0.7), wood, Vector3(0.0, y + h - t * 0.4, s * half), t * 0.25)
		Parts.box(root, Vector3(t * 0.7, t * 0.85, span), wood, Vector3(s * half, y + h - t * 0.4, 0.0), t * 0.25)
		Parts.box(root, Vector3(span, t * 0.7, t * 0.6), wood, Vector3(0.0, y + t * 0.3, s * half), t * 0.25)
		Parts.box(root, Vector3(t * 0.6, t * 0.7, span), wood, Vector3(s * half, y + t * 0.3, 0.0), t * 0.25)
	if half > 0.8:
		# Middle posts between the windows on every face.
		for s: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(t * 0.8, h, t * 0.6), wood, Vector3(0.0, y, s * (half + 0.02)), t * 0.25)
			Parts.block(root, Vector3(t * 0.6, h, t * 0.8), wood, Vector3(s * (half + 0.02), y, 0.0), t * 0.25)


static func _dormer(root: Node3D, pos: Vector3, yaw: float) -> void:
	var d := Parts.pivot(root, pos, Vector3(0.0, yaw, 0.0), "Dormer")
	Parts.block(d, Vector3(0.72, 0.5, 0.9), Mat.plaster(), Vector3(0.0, 0.0, -0.1), 0.04)
	Parts.mesh(d, Kit.prism(0.72, 0.3, 0.86), Mat.plaster(), Vector3(0.0, 0.5, -0.1))
	Parts.window(d, Vector3(0.0, 0.27, 0.36), 0.0, Vector2(0.28, 0.32), true)
	Parts.roof(d, Kit.gable_roof(1.0, 1.04, 0.36, 0.1), Mat.roof_red(), Vector3(0.0, 0.48, -0.08))
	Parts.mesh(d, Kit.sphere(0.06, 10, 6), Mat.gold(), Vector3(0.0, 0.96, 0.44))


static func _turret(root: Node3D, base: Vector3) -> void:
	var t := Parts.pivot(root, base, Vector3.ZERO, "Turret")
	var h: float = 2.55
	Parts.cyl(t, 0.46, 0.3, Mat.stone_dark(), Vector3.ZERO, 0.08)
	Parts.cyl(t, 0.42, h, Mat.stone(), Vector3(0.0, 0.2, 0.0), 0.06, 0.38)
	Parts.cyl(t, 0.44, 0.1, Mat.gold(), Vector3(0.0, h + 0.05, 0.0), 0.03)
	Parts.cyl(t, 0.47, 0.18, Mat.stone(), Vector3(0.0, h + 0.13, 0.0), 0.05)
	var out := Vector3(base.x, 0.0, base.z).normalized()
	for face: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]:
		if face.dot(out) < 0.1:
			continue
		var yaw: float = rad_to_deg(atan2(face.x, face.z))
		Parts.window(t, face * 0.39 + Vector3(0.0, 1.7, 0.0), yaw, Vector2(0.16, 0.28), true)
		Parts.window(t, face * 0.4 + Vector3(0.0, 0.75, 0.0), yaw, Vector2(0.12, 0.2), true, Mat.stone_dark())
	Parts.cone_roof(t, 0.56, 1.0, Mat.roof_red(), Vector3(0.0, h + 0.3, 0.0))
	Parts.mesh(t, Kit.sphere(0.07, 10, 6), Mat.gold(), Vector3(0.0, h + 1.32, 0.0))


## Point on the wall facing `yaw_deg` (0 = +Z, 90 = +X), `along` to the wall's right, at height `y`.
static func _on_face(yaw_deg: float, dist: float, along: float, y: float) -> Vector3:
	var a: float = deg_to_rad(yaw_deg)
	var out := Vector3(sin(a), 0.0, cos(a))
	var right := Vector3(cos(a), 0.0, -sin(a))
	return out * dist + right * along + Vector3(0.0, y, 0.0)


## Service door, step and barrels on the back (-Z) of the plinth.
static func _back_entrance(root: Node3D) -> void:
	Parts.door(root, Vector3(0.0, 0.14, -1.53), 180.0, Vector2(0.56, 0.9))
	Parts.block(root, Vector3(0.8, 0.09, 0.2), Mat.stone_dark(), Vector3(0.0, 0.14, -1.66), 0.035)
	Parts.box(root, Vector3(0.9, 0.06, 0.24), Mat.wood_dark(), Vector3(0.0, 1.12, -1.62), 0.025)
	Parts.lantern(root, Vector3(0.45, 0.88, -1.58), 180.0)
	for p: Vector3 in [Vector3(0.72, 0.14, -1.66), Vector3(-0.7, 0.14, -1.68)]:
		Parts.cyl(root, 0.16, 0.38, Mat.planks(false, Mat.WOOD, Mat.WOOD_DARK, 0.09), p, 0.04, 0.14)
		Parts.cyl(root, 0.165, 0.04, Mat.metal(), p + Vector3(0.0, 0.07, 0.0), 0.01)
		Parts.cyl(root, 0.155, 0.04, Mat.metal(), p + Vector3(0.0, 0.29, 0.0), 0.01)
