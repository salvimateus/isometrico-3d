extends RefCounted
## Mana storage (3x3): stone drum base, timber cradle with iron hoops holding a big glass orb of
## rippling mana, crowned by a metal cap.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.cyl(root, 1.12, 0.42, Mat.stone(), Vector3(0.0, g, 0.0), 0.09, 1.04)
	Parts.cyl(root, 1.06, 0.08, Mat.gold(), Vector3(0.0, g + 0.4, 0.0), 0.03)
	Parts.cyl(root, 0.72, 0.18, Mat.metal(), Vector3(0.0, g + 0.46, 0.0), 0.06, 0.6)
	var orb_r: float = 0.92
	var cy: float = g + 0.5 + orb_r * 0.92
	Parts.mesh(root, Kit.sphere(orb_r - 0.07), Mat.mana_liquid(), Vector3(0.0, cy, 0.0))
	var glass := Parts.mesh(root, Kit.sphere(orb_r), Mat.glass(), Vector3(0.0, cy, 0.0))
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Parts.bubbles(root, Vector3(0.0, cy - orb_r * 0.55, 0.0), Vector3(0.35, 0.02, 0.35), orb_r * 1.1)
	# Equator hoop and a vertical hoop.
	Parts.mesh(root, Kit.torus(orb_r + 0.03, 0.06, 32, 8), Mat.metal(), Vector3(0.0, cy, 0.0))
	Parts.mesh(root, Kit.torus(orb_r + 0.03, 0.04, 32, 6), Mat.metal(), Vector3(0.0, cy, 0.0), Vector3(90.0, 45.0, 0.0))
	# Timber cradle legs from the base up to the hoop.
	for i in 4:
		var a: float = deg_to_rad(45.0 + 90.0 * i)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var foot: Vector3 = dir * 1.0 + Vector3(0.0, g + 0.42, 0.0)
		var top: Vector3 = dir * (orb_r + 0.06) + Vector3(0.0, cy + 0.05, 0.0)
		Parts.rod(root, foot, top, 0.085, Mat.wood(), 0, true)
		Parts.box(root, Vector3(0.24, 0.12, 0.24), Mat.gold(), top + Vector3(0.0, 0.02, 0.0), 0.04)
		Parts.block(root, Vector3(0.26, 0.14, 0.26), Mat.stone_dark(), foot - Vector3(0.0, 0.04, 0.0), 0.05)
	# Cap with gold finial.
	var top_y: float = cy + orb_r - 0.12
	Parts.mesh(root, Kit.dome(0.42, 0.26, 20, 6), Mat.metal(), Vector3(0.0, top_y, 0.0))
	Parts.cyl(root, 0.44, 0.08, Mat.gold(), Vector3(0.0, top_y - 0.02, 0.0), 0.03)
	Parts.cyl(root, 0.06, 0.24, Mat.metal_light(), Vector3(0.0, top_y + 0.22, 0.0), 0.02, -1.0, 10)
	var gem := Parts.animated(root, Parts.SPIN, {"axis": Vector3.UP, "speed": 0.8}, Vector3(0.0, top_y + 0.45, 0.0))
	Parts.mesh(gem, Kit.crystal(0.12, 0.34, 6), Mat.mana_crystal(), Vector3(0.0, 0.0, 0.0))
	Parts.mana_light(root, Vector3(0.0, cy, 0.0))
	return root
