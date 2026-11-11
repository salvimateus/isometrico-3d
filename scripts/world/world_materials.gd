extends RefCounted

## Shared, cached materials for world rendering. One instance per look.

const Tuning := preload("res://scripts/tuning.gd")

static var _cache: Dictionary = {}


static func foliage(key: StringName, sway_amount: float, sway_height: float, two_sided: bool = false) -> ShaderMaterial:
	var cache_key: String = "foliage_%s" % key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world/foliage_two_sided.gdshader" if two_sided else "res://shaders/world/foliage.gdshader")
	mat.set_shader_parameter("sway_amount", sway_amount)
	mat.set_shader_parameter("sway_height", sway_height)
	mat.set_shader_parameter("wind_strength", Tuning.WIND_STRENGTH)
	mat.set_shader_parameter("wind_speed", Tuning.WIND_SPEED)
	mat.set_shader_parameter("camera_fade_near", Tuning.FOLIAGE_CAMERA_FADE_NEAR)
	mat.set_shader_parameter("camera_fade_far", Tuning.FOLIAGE_CAMERA_FADE_FAR)
	_cache[cache_key] = mat
	return mat


static func vertex_color(key: StringName, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var cache_key: String = "vc_%s" % key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	mat.metallic = metallic
	_cache[cache_key] = mat
	return mat


static func solid(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var cache_key: String = "solid_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	_cache[cache_key] = mat
	return mat


static func shader(path: String) -> ShaderMaterial:
	var cache_key: String = "shader_%s" % path
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	_cache[cache_key] = mat
	return mat
