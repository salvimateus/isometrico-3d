extends RefCounted

## Entry point: builds a drifting cloud field over `area` (world XZ, include the ocean).
## Add it to the scene at the identity transform. Picks the mobile profile from `quality.gd`.

const CloudField := preload("res://scripts/clouds/cloud_field.gd")
const QUALITY_PATH: String = "res://scripts/quality.gd"


static func create(area: Rect2) -> Node3D:
	var field: Node3D = CloudField.new()
	field.name = "Clouds"
	field.configure(area, 1337, is_mobile())
	return field


## quality.gd decides when present; otherwise the renderer, platform and `--quality=` arg do.
static func is_mobile() -> bool:
	if ResourceLoader.exists(QUALITY_PATH):
		var quality: Resource = load(QUALITY_PATH)
		if quality is GDScript and (quality as GDScript).can_instantiate():
			return bool((quality as GDScript).call(&"is_mobile"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			return arg.trim_prefix("--quality=") == "mobile"
	return OS.has_feature("mobile") or RenderingServer.get_current_rendering_method() == "mobile"
