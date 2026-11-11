extends StaticBody3D

## Sandbox floor exposing the footstep-surface contract: `surface_at(pos) -> StringName`.

var patches: Array[Dictionary] = []


func surface_at(pos: Vector3) -> StringName:
	for patch: Dictionary in patches:
		var rect: Rect2 = patch["rect"]
		if rect.has_point(Vector2(pos.x, pos.z)):
			return patch["surface"]
	return &"grass"
