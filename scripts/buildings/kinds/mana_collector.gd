extends RefCounted
## Mana collector (3x3): stone ring base, glass tank with glowing mana and bubbles, wooden frame,
## pumping piston on top, feed pipe and mana crystals.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.cyl(root, 1.08, 0.36, Mat.stone(), Vector3(0.0, g, 0.0), 0.08, 1.02)
	Parts.cyl(root, 0.98, 0.08, Mat.planks(true), Vector3(0.0, g + 0.34, 0.0), 0.03)
	var tank_y: float = g + 0.42
	var tank_h: float = 1.45
	var r: float = 0.6
	# Liquid then glass (transparent, no shadow).
	Parts.cyl(root, r - 0.06, tank_h - 0.22, Mat.mana_liquid(), Vector3(0.0, tank_y + 0.08, 0.0), 0.05)
	var glass := Parts.cyl(root, r, tank_h, Mat.glass(), Vector3(0.0, tank_y, 0.0), 0.06)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Parts.bubbles(root, Vector3(0.0, tank_y + 0.15, 0.0), Vector3(0.35, 0.02, 0.35), tank_h - 0.5)
	# Metal bands and caps.
	Parts.cyl(root, r + 0.07, 0.18, Mat.metal(), Vector3(0.0, tank_y - 0.02, 0.0), 0.05)
	Parts.cyl(root, r + 0.06, 0.08, Mat.gold(), Vector3(0.0, tank_y + tank_h * 0.5, 0.0), 0.03)
	Parts.cyl(root, r + 0.08, 0.16, Mat.metal(), Vector3(0.0, tank_y + tank_h - 0.08, 0.0), 0.05)
	Parts.mesh(root, Kit.dome(r + 0.04, 0.32, 20, 6), Mat.metal(), Vector3(0.0, tank_y + tank_h + 0.06, 0.0))
	# Wooden frame posts with braces.
	for i in 4:
		var a: float = deg_to_rad(45.0 + 90.0 * i)
		var p := Vector3(cos(a), 0.0, sin(a)) * (r + 0.2)
		Parts.block(root, Vector3(0.16, tank_h + 0.25, 0.16), Mat.wood(), p + Vector3(0.0, g + 0.36, 0.0), 0.04, 0.0, Vector3(0.0, -rad_to_deg(a), 0.0))
		Parts.box(root, Vector3(0.22, 0.1, 0.22), Mat.gold(), p + Vector3(0.0, g + 0.36 + tank_h + 0.28, 0.0), 0.04)
	# Pump: piston bobbing out of the cap, with a gold collar.
	var top_y: float = tank_y + tank_h + 0.32
	Parts.cyl(root, 0.17, 0.14, Mat.gold(), Vector3(0.0, top_y, 0.0), 0.04)
	var piston := Parts.bobber(root, Vector3(0.0, top_y + 0.1, 0.0), Tuning.PISTON_TRAVEL, Tuning.PISTON_SPEED)
	Parts.cyl(piston, 0.07, 0.5, Mat.metal_light(), Vector3.ZERO, 0.02, -1.0, 12)
	Parts.mesh(piston, Kit.cylinder(0.16, 0.12, 0.04, -1.0, 16), Mat.metal(), Vector3(0.0, 0.52, 0.0))
	Parts.mesh(piston, Kit.crystal(0.11, 0.3, 6), Mat.mana_crystal(), Vector3(0.0, 0.58, 0.0))
	# Feed pipe on the +X side going into the ground.
	var pipe_mat: Material = Mat.metal()
	Parts.rod(root, Vector3(r + 0.02, tank_y + 0.25, 0.25), Vector3(1.12, tank_y + 0.25, 0.25), 0.07, pipe_mat)
	Parts.rod(root, Vector3(1.12, tank_y + 0.3, 0.25), Vector3(1.12, g, 0.25), 0.07, pipe_mat)
	Parts.mesh(root, Kit.sphere(0.1, 12, 8), pipe_mat, Vector3(1.12, tank_y + 0.25, 0.25))
	var valve := Parts.pivot(root, Vector3(1.0, tank_y + 0.25, 0.25), Vector3(0.0, 90.0, 0.0))
	Parts.mesh(valve, Kit.torus(0.12, 0.022, 14, 6), Mat.gold(), Vector3(0.0, 0.0, 0.0), Vector3(90.0, 0.0, 0.0))
	Parts.box(valve, Vector3(0.24, 0.03, 0.03), Mat.gold(), Vector3.ZERO, 0.01)
	# Mana crystals around the base.
	var crystals: Array[Vector3] = [Vector3(-0.95, g, 0.85), Vector3(-1.1, g, 0.6), Vector3(0.85, g, -0.95), Vector3(-0.2, g, 1.1)]
	var sizes: Array[float] = [0.42, 0.28, 0.36, 0.22]
	for i in crystals.size():
		Parts.mesh(root, Kit.crystal(sizes[i] * 0.32, sizes[i], 6), Mat.mana_crystal(), crystals[i], Vector3(12.0 * (i % 2 * 2 - 1), 23.0 * i, 8.0))
	Parts.mana_light(root, Vector3(0.0, tank_y + tank_h * 0.5, 0.0))
	return root
