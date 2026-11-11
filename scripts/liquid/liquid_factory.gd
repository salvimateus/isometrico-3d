extends RefCounted

## Entry point: builds the liquid field covering `area` (world XZ). Add it at the identity transform,
## then call set_terrain() and attach_tower(). The node joins the group &"liquid_field".

const LiquidField := preload("res://scripts/liquid/liquid_field.gd")


static func create(area: Rect2) -> Node3D:
	var field: Node3D = LiquidField.new()
	field.name = "LiquidField"
	field.call(&"configure", area)
	return field
