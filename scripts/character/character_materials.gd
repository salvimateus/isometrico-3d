extends RefCounted

## Cached toy-paint materials for the player character.

const PALETTE: Dictionary = {
	&"skin": Color("F09A5C"),
	&"skin_shade": Color("C47A48"),
	&"cheek": Color("F06A5A"),
	&"hair": Color("F2C14E"),
	&"hair_shade": Color("C98F2B"),
	&"leather": Color("8A5530"),
	&"leather_dark": Color("5E3A20"),
	&"fur": Color("A08A70"),
	&"fur_light": Color("E6D6B8"),
	&"metal": Color("B4B2AC"),
	&"metal_dark": Color("4A4F5A"),
	&"metal_edge": Color("EEF2F4"),
	&"steel": Color("B2ACA2"),
	&"gold": Color("FFAE2A"),
	&"horn": Color("F2E6CC"),
	&"wood": Color("A8693A"),
	&"wood_dark": Color("7A4A28"),
	&"paint_red": Color("D8452E"),
	&"tattoo": Color("3E7FD6"),
	&"eye": Color("1E1A22"),
	&"eye_glint": Color("FFFFFF"),
	&"mouth": Color("4A1418"),
	&"star": Color("FFD84A"),
	&"sweat": Color("BFE8FF"),
	&"tongue": Color("D8566A"),
}

const WARM_GLOW: Dictionary = {&"steel": 0.3, &"skin": 0.1, &"hair": 0.12, &"hair_shade": 0.08, &"gold": 0.12, &"cheek": 0.1, &"paint_red": 0.06}

static var _cache: Dictionary = {}


static func get_mat(key: StringName) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE.get(key, Color.MAGENTA)
	mat.roughness = 0.82
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.6
	match key:
		&"eye":
			mat.roughness = 0.25
			mat.rim_enabled = false
		&"eye_glint":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.rim_enabled = false
		&"gold":
			mat.metallic = 0.2
			mat.roughness = 0.45
			mat.metallic_specular = 0.7
		&"metal", &"metal_dark":
			mat.metallic = 0.25
			mat.roughness = 0.5
			mat.metallic_specular = 0.7
		&"skin", &"skin_shade":
			mat.rim = 0.35
		&"hair_grad":
			# Sculpted hair/beard: color comes from the mesh's top-to-bottom vertex gradient.
			mat.albedo_color = Color.WHITE
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.7
			mat.rim = 0.4
			mat.emission_enabled = true
			mat.emission = PALETTE[&"hair"]
			mat.emission_energy_multiplier = 0.22
		&"vcolor":
			# Sculpted fur: color comes from mesh vertex gradient.
			mat.albedo_color = Color.WHITE
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.9
			mat.rim = 0.12
		&"star":
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.emission_enabled = true
			mat.emission = PALETTE[&"star"]
			mat.emission_energy_multiplier = 0.8
			mat.rim_enabled = false
		&"sweat":
			mat.roughness = 0.1
			mat.emission_enabled = true
			mat.emission = PALETTE[&"sweat"]
			mat.emission_energy_multiplier = 0.4
		&"mouth":
			mat.rim_enabled = false
			mat.roughness = 0.9
		&"steel":
			mat.metallic = 0.0
			mat.roughness = 0.55
			mat.rim_enabled = false
		&"metal_edge":
			mat.metallic = 0.3
			mat.roughness = 0.3
			mat.metallic_specular = 0.8
		&"hair", &"hair_shade", &"fur", &"fur_light":
			mat.roughness = 0.95
			mat.rim = 0.4
	if WARM_GLOW.has(key):
		# Keeps warm toy colors from going olive/muddy under the blue sky ambient in shade.
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = WARM_GLOW[key]
	_cache[key] = mat
	return mat


## Head skin with painted cheek blush (mesh-local mask), matching the toy-paint skin material.
static func get_head_skin_material() -> ShaderMaterial:
	if _cache.has(&"_head_skin"):
		return _cache[&"_head_skin"]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/character/skin_blush.gdshader")
	mat.set_shader_parameter(&"skin_color", PALETTE[&"skin"])
	mat.set_shader_parameter(&"blush_color", PALETTE[&"cheek"])
	mat.set_shader_parameter(&"glow", WARM_GLOW[&"skin"])
	_cache[&"_head_skin"] = mat
	return mat


static func get_dust_material() -> StandardMaterial3D:
	if _cache.has(&"_dust"):
		return _cache[&"_dust"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_is_srgb = true
	_cache[&"_dust"] = mat
	return mat


static func get_blob_shadow_material() -> StandardMaterial3D:
	if _cache.has(&"_blob"):
		return _cache[&"_blob"]
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.42))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	grad.add_point(0.55, Color(0.0, 0.0, 0.0, 0.22))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_cache[&"_blob"] = mat
	return mat
