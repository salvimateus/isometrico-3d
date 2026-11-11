extends RefCounted
## Barracks (3x3): stone footing, plank hall under a red gable roof, smoking chimney, arched door,
## painted shields, crossed spears and a weapon rack.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.block(root, Vector3(2.5, 0.26, 2.0), Mat.stone(), Vector3(0.0, g, -0.2), 0.08, 0.03)
	var y: float = g + 0.26
	var hw: float = 1.08
	var hd: float = 0.8
	var body_h: float = 1.18
	var cz: float = -0.2
	Parts.block(root, Vector3(hw * 2.0, body_h, hd * 2.0), Mat.planks(true), Vector3(0.0, y, cz), 0.05)
	var dark: Material = Mat.wood_dark()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Parts.block(root, Vector3(0.18, body_h + 0.02, 0.18), dark, Vector3(sx * hw, y - 0.01, cz + sz * hd), 0.05)
	for s: float in [-1.0, 1.0]:
		Parts.box(root, Vector3(hw * 2.0 + 0.16, 0.14, 0.12), dark, Vector3(0.0, y + body_h - 0.06, cz + s * hd), 0.04)
	# Gable walls (plaster) at the X ends; ridge runs along X.
	var roof_h: float = 0.88
	for s: float in [-1.0, 1.0]:
		Parts.mesh(root, Kit.prism(hd * 2.0, roof_h - 0.05, 0.1), Mat.plaster(), Vector3(s * (hw - 0.02), y + body_h, cz), Vector3(0.0, 90.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Parts.window(root, Vector3(s * (hw + 0.05), y + body_h + 0.3, cz), 90.0 * s, Vector2(0.26, 0.26), true)
	Parts.roof(root, Kit.gable_roof(hd * 2.0 + 0.5, hw * 2.0 + 0.4, roof_h, 0.13), Mat.roof_red(), Vector3(0.0, y + body_h - 0.06, cz), Vector3(0.0, 90.0, 0.0))
	Parts.mesh(root, Kit.cylinder(0.08, hw * 2.0 + 0.5, 0.03, -1.0, 12), Mat.roof(Mat.ROOF_RED_SHADOW, Mat.ROOF_RED_SHADOW.darkened(0.2)), Vector3(0.0, y + body_h - 0.06 + roof_h + 0.12, cz), Vector3(0.0, 0.0, 90.0))
	for s: float in [-1.0, 1.0]:
		Parts.mesh(root, Kit.sphere(0.08, 10, 6), Mat.gold(), Vector3(s * (hw + 0.27), y + body_h + roof_h + 0.07, cz))
	# Chimney through the back slope with smoke.
	var ch := Vector3(-0.55, y + 0.5, cz - 0.35)
	Parts.block(root, Vector3(0.36, 1.35, 0.36), Mat.stone(), ch, 0.06, 0.08)
	Parts.block(root, Vector3(0.42, 0.12, 0.42), Mat.stone_dark(), ch + Vector3(0.0, 1.32, 0.0), 0.04)
	Parts.smoke(root, ch + Vector3(0.0, 1.48, 0.0), Tuning.SMOKE_AMOUNT)
	# Front: door, windows, shields.
	var front: float = cz + hd + 0.04
	Parts.door(root, Vector3(0.0, y, front), 0.0, Vector2(0.58, 1.0))
	Parts.block(root, Vector3(0.84, 0.13, 0.3), Mat.stone_dark(), Vector3(0.0, g, front + 0.2), 0.04)
	for s: float in [-1.0, 1.0]:
		_shield(root, Vector3(s * 0.7, y + 0.66, front + 0.02), Mat.CLOTH_BLUE if s < 0.0 else Mat.CLOTH_RED)
	for s: float in [-1.0, 1.0]:
		for z: float in [0.35, -0.35]:
			Parts.window(root, Vector3(s * (hw + 0.05), y + 0.62, cz + z), 90.0 * s, Vector2(0.32, 0.36))
	# Back wall: windows, a small service hatch, and a lantern.
	var back: float = cz - hd - 0.04
	for x: float in [-0.62, 0.62]:
		Parts.window(root, Vector3(x, y + 0.62, back), 180.0, Vector2(0.34, 0.38))
	Parts.door(root, Vector3(0.0, y, back), 180.0, Vector2(0.44, 0.78))
	Parts.lantern(root, Vector3(-0.36, y + 0.86, back - 0.06), 180.0)
	Parts.lantern(root, Vector3(0.4, y + 0.98, front + 0.06), 0.0)
	# Weapon rack in front of the right side.
	_rack(root, Vector3(0.82, g, 1.08))
	return root


static func _shield(root: Node3D, pos: Vector3, color: Color) -> void:
	Parts.mesh(root, Kit.shield(0.42, 0.5, 0.06), Mat.gold(), pos)
	Parts.mesh(root, Kit.shield(0.34, 0.42, 0.06), Mat.solid(color, 0.65), pos + Vector3(0.0, 0.01, 0.025))
	Parts.mesh(root, Kit.dome(0.07, 0.05, 12, 4), Mat.metal_light(), pos + Vector3(0.0, 0.03, 0.055), Vector3(90.0, 0.0, 0.0))


static func _rack(root: Node3D, pos: Vector3) -> void:
	var r := Parts.pivot(root, pos, Vector3(0.0, -10.0, 0.0), "Rack")
	var dark: Material = Mat.wood_dark()
	for s: float in [-1.0, 1.0]:
		Parts.block(r, Vector3(0.08, 0.6, 0.08), dark, Vector3(s * 0.32, 0.0, 0.0), 0.02)
	Parts.box(r, Vector3(0.76, 0.07, 0.1), dark, Vector3(0.0, 0.5, 0.0), 0.02)
	Parts.box(r, Vector3(0.76, 0.06, 0.1), dark, Vector3(0.0, 0.12, 0.0), 0.02)
	for i in 3:
		var x: float = -0.18 + i * 0.18
		Parts.rod(r, Vector3(x, 0.02, 0.06), Vector3(x + 0.02, 0.95, -0.05), 0.022, Mat.wood(), 6)
		Parts.mesh(r, Kit.cone(0.045, 0.16, 6), Mat.metal_light(), Vector3(x + 0.02, 0.94, -0.05), Vector3(-6.0, 0.0, -1.0))
