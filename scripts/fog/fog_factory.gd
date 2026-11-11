extends RefCounted

## Entry point: builds a ground-fog field covering `area` (world XZ). Add it to the scene at the identity transform.

const FogField := preload("res://scripts/fog/fog_field.gd")


static func create(area: Rect2) -> Node3D:
	var field: Node3D = FogField.new()
	field.name = "GroundFog"
	field.configure(area)
	return field
