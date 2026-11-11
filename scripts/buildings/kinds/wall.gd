extends RefCounted
## Wall tile (1x1): chunky stone post plus a connector arm toward each neighbor in the bitmask.

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Parts = preload("res://scripts/buildings/parts.gd")

const _DIRS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]


static func build(neighbors: int) -> Node3D:
	var root := Node3D.new()
	var post_h: float = 0.86
	Parts.block(root, Vector3(0.56, 0.12, 0.56), Mat.stone_dark(), Vector3.ZERO, 0.05)
	Parts.block(root, Vector3(0.46, post_h - 0.12, 0.46), Mat.stone(), Vector3(0.0, 0.1, 0.0), 0.07, 0.06)
	Parts.block(root, Vector3(0.52, 0.12, 0.52), Mat.stone_dark(), Vector3(0.0, post_h - 0.04, 0.0), 0.05)
	Parts.mesh(root, Kit.hip_roof(0.34, 0.34, 0.16, 0.0, 0.04), Mat.stone_dark(), Vector3(0.0, post_h + 0.08, 0.0))
	for i in 4:
		if neighbors & (1 << i) == 0:
			continue
		var dir: Vector3 = _DIRS[i]
		var along_x: bool = absf(dir.x) > 0.5
		var length: float = 0.52
		var size := Vector3(length, 0.6, 0.32) if along_x else Vector3(0.32, 0.6, length)
		var center: Vector3 = dir * (0.5 - length * 0.5 + 0.02)
		Parts.block(root, size, Mat.stone(), center, 0.05)
		var cap := Vector3(length, 0.08, 0.38) if along_x else Vector3(0.38, 0.08, length)
		Parts.block(root, cap, Mat.stone_dark(), center + Vector3(0.0, 0.58, 0.0), 0.035)
	return root
