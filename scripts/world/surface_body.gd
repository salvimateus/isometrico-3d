extends StaticBody3D

## Static collider that reports the walking surface under a point (used for footstep sounds).

const GroundData := preload("res://scripts/world/ground_data.gd")

var fixed_surface: StringName = &""
var ground: GroundData = null


func surface_at(pos: Vector3) -> StringName:
	if fixed_surface != &"":
		return fixed_surface
	if ground != null and ground.dirt_at(Vector2(pos.x, pos.z)):
		return &"dirt"
	return &"grass"
