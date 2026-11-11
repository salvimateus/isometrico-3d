extends RefCounted
## Builder hut (2x2): cozy cottage with a steep blue gable roof, round window, little chimney,
## tools leaning on the wall and a plank stack.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(1.68, 1.68), 0.1)
	var g: float = 0.1
	Parts.block(root, Vector3(1.36, 0.14, 1.3), Mat.stone(), Vector3(-0.05, g, -0.06), 0.05, 0.03)
	var y: float = g + 0.14
	var cx: float = -0.05
	var cz: float = -0.08
	var hw: float = 0.52
	var hd: float = 0.5
	var body_h: float = 0.92
	Parts.block(root, Vector3(hw * 2.0, body_h, hd * 2.0), Mat.plaster(), Vector3(cx, y, cz), 0.05)
	var dark: Material = Mat.wood_dark()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(0.13, body_h + 0.02, 0.13), dark, Vector3(cx + sx * hw, y - 0.01, cz + sz * hd), 0.04)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(0.1, 0.1, hd * 2.0 + 0.1), dark, Vector3(cx + s * hw, y + body_h - 0.04, cz), 0.03)
	# Gable faces front (+Z): ridge along Z.
	var roof_h: float = 0.72
	Parts.mesh(root, Kit.prism(hw * 2.0, roof_h - 0.04, hd * 2.0 - 0.02), Mat.plaster(), Vector3(cx, y + body_h, cz))
	Parts.roof(root, Kit.gable_roof(hw * 2.0 + 0.36, hd * 2.0 + 0.34, roof_h, 0.11), Mat.roof_blue(), Vector3(cx, y + body_h - 0.05, cz))
	Parts.mesh(root, Kit.cylinder(0.065, hd * 2.0 + 0.4, 0.025, -1.0, 12), Mat.roof(Mat.ROOF_BLUE_SHADOW, Mat.ROOF_BLUE_SHADOW.darkened(0.2)), Vector3(cx, y + body_h - 0.05 + roof_h + 0.1, cz), Vector3(90.0, 0.0, 0.0))
	# Round attic window in the gable, door below.
	var front: float = cz + hd + 0.03
	var attic := Parts.pivot(root, Vector3(cx, y + body_h + 0.24, front), Vector3.ZERO)
	Parts.mesh(attic, Kit.cylinder(0.15, 0.05, 0.015, -1.0, 16), dark, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	Parts.mesh(attic, Kit.cylinder(0.11, 0.05, 0.01, -1.0, 16), Mat.window_glow(), Vector3(0.0, 0.0, 0.012), Vector3(90.0, 0.0, 0.0))
	Parts.door(root, Vector3(cx, y, front), 0.0, Vector2(0.44, 0.8), Mat.wood_dark())
	Parts.block(root, Vector3(0.56, 0.08, 0.2), Mat.stone_dark(), Vector3(cx, g, front + 0.12), 0.03)
	Parts.window(root, Vector3(cx + hw + 0.04, y + 0.52, cz), 90.0, Vector2(0.26, 0.3))
	Parts.lantern(root, Vector3(cx - 0.36, y + 0.78, front + 0.05), 0.0)
	Parts.window(root, Vector3(cx - hw - 0.04, y + 0.52, cz), -90.0, Vector2(0.26, 0.3))
	Parts.window(root, Vector3(cx + 0.18, y + 0.52, cz - hd - 0.04), 180.0, Vector2(0.24, 0.28))
	var back_attic := Parts.pivot(root, Vector3(cx, y + body_h + 0.24, cz - hd - 0.03), Vector3(0.0, 180.0, 0.0))
	Parts.mesh(back_attic, Kit.cylinder(0.13, 0.05, 0.015, -1.0, 16), dark, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	for i in 3:
		Parts.box(back_attic, Vector3(0.18, 0.025, 0.03), dark, Vector3(0.0, -0.06 + i * 0.06, 0.03), 0.01)
	Parts.mesh(back_attic, Kit.cylinder(0.1, 0.04, 0.01, -1.0, 16), Mat.opening(), Vector3(0.0, 0.0, 0.01), Vector3(90.0, 0.0, 0.0))
	# Firewood under the back-left eave.
	for i in 3:
		Parts.mesh(root, Kit.cylinder(0.06, 0.34, 0.015, -1.0, 10), Mat.wood(), Vector3(cx - 0.3 + i * 0.12, g + 0.2, cz - hd - 0.13), Vector3(0.0, 90.0, 90.0))
	for i in 2:
		Parts.mesh(root, Kit.cylinder(0.06, 0.34, 0.015, -1.0, 10), Mat.wood(), Vector3(cx - 0.24 + i * 0.12, g + 0.3, cz - hd - 0.13), Vector3(0.0, 90.0, 90.0))
	# Chimney on the back slope.
	var ch := Vector3(cx - 0.28, y + 0.6, cz - 0.25)
	Parts.block(root, Vector3(0.22, 0.95, 0.22), Mat.stone(), ch, 0.04, 0.06)
	Parts.block(root, Vector3(0.27, 0.08, 0.27), Mat.stone_dark(), ch + Vector3(0.0, 0.93, 0.0), 0.03)
	Parts.smoke(root, ch + Vector3(0.0, 1.03, 0.0), Tuning.SMOKE_AMOUNT_SMALL, 0.08)
	# Tools leaning on the +X wall.
	_hammer(root, Vector3(cx + hw + 0.14, g + 0.25, cz + 0.32))
	_shovel(root, Vector3(cx + hw + 0.14, g + 0.25, cz - 0.32))
	# Plank stack in the front-right corner.
	var stack := Parts.pivot(root, Vector3(0.52, g, 0.62), Vector3(0.0, -20.0, 0.0), "Planks")
	for i in 3:
		Parts.block(stack, Vector3(0.48, 0.06, 0.12), Mat.wood(), Vector3(0.0, i * 0.065, -0.07 + (i % 2) * 0.03), 0.02)
		Parts.block(stack, Vector3(0.48, 0.06, 0.12), Mat.wood(), Vector3(0.0, i * 0.065, 0.07 + (i % 2) * 0.03), 0.02)
	# Swinging sign over the door.
	var board := Parts.swayer(root, Vector3(cx + 0.38, y + 0.84, front + 0.08), Vector3.RIGHT, Tuning.SIGN_SWAY_DEG, Tuning.SIGN_SWAY_SPEED)
	Parts.box(board, Vector3(0.03, 0.12, 0.03), dark, Vector3(0.0, -0.06, 0.0), 0.01)
	Parts.box(board, Vector3(0.24, 0.16, 0.04), Mat.wood(), Vector3(0.0, -0.18, 0.0), 0.02)
	Parts.box(board, Vector3(0.1, 0.06, 0.02), Mat.gold(), Vector3(0.0, -0.18, 0.025), 0.01)
	return root


static func _hammer(root: Node3D, base: Vector3) -> void:
	var top: Vector3 = base + Vector3(-0.1, 0.5, 0.0)
	Parts.rod(root, base, top, 0.025, Mat.wood(), 6)
	Parts.box(root, Vector3(0.08, 0.08, 0.2), Mat.metal(), top, 0.02, Vector3(0.0, 0.0, 11.0))


static func _shovel(root: Node3D, base: Vector3) -> void:
	var top: Vector3 = base + Vector3(-0.1, 0.6, 0.0)
	Parts.rod(root, base + Vector3(0.0, 0.15, 0.0), top, 0.022, Mat.wood(), 6)
	Parts.box(root, Vector3(0.03, 0.22, 0.16), Mat.metal_light(), base + Vector3(0.0, 0.06, 0.0), 0.02, Vector3(0.0, 0.0, 10.0))
	Parts.box(root, Vector3(0.04, 0.04, 0.12), Mat.wood_dark(), top, 0.015)
