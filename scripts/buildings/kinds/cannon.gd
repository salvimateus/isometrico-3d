extends RefCounted
## Cannon (3x3): stone drum with a plank deck, rotating wooden carriage and a chunky dark-iron barrel
## with gold bands that slowly scans for targets. Cannonball stack on the side.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")
const SCAN = preload("res://scripts/buildings/anim/scan.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	Parts.footing(root, Vector2(2.66, 2.66), 0.12)
	var g: float = 0.12
	Parts.cyl(root, 1.2, 0.5, Mat.stone(), Vector3(0.0, g, 0.0), 0.1, 1.12)
	Parts.cyl(root, 1.1, 0.07, Mat.stone_dark(), Vector3(0.0, g + 0.48, 0.0), 0.03)
	Parts.cyl(root, 0.98, 0.1, Mat.planks(true), Vector3(0.0, g + 0.52, 0.0), 0.04)
	var deck: float = g + 0.62
	var turret := Parts.animated(root, SCAN, {}, Vector3(0.0, deck, 0.0), Vector3.ZERO, "Turret")
	Parts.cyl(turret, 0.78, 0.12, Mat.wood_dark(), Vector3.ZERO, 0.04)
	Parts.cyl(turret, 0.8, 0.05, Mat.metal(), Vector3(0.0, 0.03, 0.0), 0.02)
	for s: float in [-1.0, 1.0]:
		var cheek := Parts.pivot(turret, Vector3(s * 0.36, 0.12, 0.0))
		Parts.mesh(cheek, Kit.extrude(PackedVector2Array([
			Vector2(-0.5, 0.0), Vector2(0.45, 0.0), Vector2(0.45, 0.22), Vector2(0.15, 0.62), Vector2(-0.2, 0.62), Vector2(-0.5, 0.3)
		]), 0.16, "cannon_cheek"), Mat.wood(), Vector3.ZERO, Vector3(0.0, -90.0, 0.0))
		Parts.mesh(cheek, Kit.cylinder(0.09, 0.04, 0.015, -1.0, 12), Mat.gold(), Vector3(s * 0.09, 0.5, 0.0), Vector3(0.0, 0.0, 90.0))
		for z: float in [-0.3, 0.3]:
			Parts.mesh(cheek, Kit.cylinder(0.05, 0.06, 0.015, -1.0, 8), Mat.metal(), Vector3(s * 0.09, 0.12, z), Vector3(0.0, 0.0, 90.0))
	Parts.box(turret, Vector3(0.6, 0.12, 0.6), Mat.wood_dark(), Vector3(0.0, 0.18, -0.12), 0.04)
	# Barrel: lathe profile along +Y, tipped forward to point at +Z with slight elevation.
	var barrel := Parts.pivot(turret, Vector3(0.0, 0.62, 0.0), Vector3(78.0, 0.0, 0.0), "Barrel")
	var profile := PackedVector2Array([
		Vector2(0.0, -0.62), Vector2(0.1, -0.6), Vector2(0.14, -0.55), Vector2(0.28, -0.5), Vector2(0.33, -0.42),
		Vector2(0.33, -0.2), Vector2(0.29, -0.15), Vector2(0.27, 0.55), Vector2(0.3, 0.62), Vector2(0.33, 0.72),
		Vector2(0.32, 0.8), Vector2(0.2, 0.82), Vector2(0.17, 0.74), Vector2(0.0, 0.74),
	])
	Parts.mesh(barrel, Kit.lathe(profile, 24, 40.0), Mat.metal(), Vector3.ZERO)
	Parts.mesh(barrel, Kit.sphere(0.1, 12, 8), Mat.metal(), Vector3(0.0, -0.66, 0.0))
	Parts.mesh(barrel, Kit.cylinder(0.17, 0.02, 0.0, -1.0, 16), Mat.opening(), Vector3(0.0, 0.75, 0.0))
	Parts.mesh(barrel, Kit.cylinder(0.3, 0.08, 0.03), Mat.gold(), Vector3(0.0, 0.2, 0.0))
	Parts.mesh(barrel, Kit.cylinder(0.345, 0.07, 0.025), Mat.gold(), Vector3(0.0, -0.3, 0.0))
	Parts.mesh(barrel, Kit.cylinder(0.335, 0.06, 0.025), Mat.gold(), Vector3(0.0, 0.68, 0.0))
	Parts.mesh(barrel, Kit.cylinder(0.05, 0.75, 0.0, -1.0, 12), Mat.metal(), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
	# Cannonballs stacked on the deck edge.
	var balls := Parts.pivot(root, Vector3(0.78, deck - 0.02, 0.62), Vector3.ZERO, "Balls")
	var ball := Kit.sphere(0.11, 14, 8)
	for p: Vector3 in [Vector3(-0.11, 0.11, -0.065), Vector3(0.11, 0.11, -0.065), Vector3(0.0, 0.11, 0.125), Vector3(0.0, 0.29, 0.0)]:
		Parts.mesh(balls, ball, Mat.metal(), p)
	Parts.cyl(root, 0.3, 0.05, Mat.wood_dark(), Vector3(0.78, deck - 0.06, 0.62), 0.02)
	return root
