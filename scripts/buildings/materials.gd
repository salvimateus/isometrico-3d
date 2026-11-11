extends RefCounted
## Building palette and cached materials: one material per color/type, shared by every mesh.

const Tuning = preload("res://scripts/buildings/building_tuning.gd")
const STONE_SHADER: Shader = preload("res://shaders/buildings/stone_blocks.gdshader")
const WOOD_SHADER: Shader = preload("res://shaders/buildings/wood_planks.gdshader")
const ROOF_SHADER: Shader = preload("res://shaders/buildings/roof_tiles.gdshader")
const MANA_SHADER: Shader = preload("res://shaders/buildings/mana_liquid.gdshader")
const GLASS_SHADER: Shader = preload("res://shaders/buildings/glass.gdshader")
const FLAG_SHADER: Shader = preload("res://shaders/buildings/flag.gdshader")
const ROCK_SHADER: Shader = preload("res://shaders/buildings/rock.gdshader")
const HALO_SHADER: Shader = preload("res://shaders/buildings/glow_halo.gdshader")
const PAINT_SHADER: Shader = preload("res://shaders/buildings/building_paint.gdshader")
const PALETTE_SIZE: int = 256

const GRASS := Color("7cc243")
const GRASS_LIGHT := Color("97d65a")
const GRASS_DARK := Color("5fa834")
const DIRT := Color("d9b27c")
const DIRT_DARK := Color("b98a52")
const STONE := Color("c2bbae")
const STONE_DARK := Color("8e877c")
const WOOD := Color("a8693a")
const WOOD_DARK := Color("7a4a28")
const WOOD_DEEP := Color("4e2e18")
const ROOF_RED := Color("d8452e")
const ROOF_RED_SHADOW := Color("a8321f")
const ROOF_BLUE := Color("3e7fd6")
const ROOF_BLUE_SHADOW := Color("2b5ea8")
const GOLD := Color("ffc93c")
const GOLD_DEEP := Color("f2a81e")
const MANA := Color("c24be0")
const MANA_DEEP := Color("5a1288")
const MANA_BRIGHT := Color("f05cff")
const WATER := Color("3fc6d8")
const WATER_DEEP := Color("1f8fb8")
const FOLIAGE := Color("3fa34d")
const FOLIAGE_DARK := Color("2f8c3e")
const TRUNK := Color("8a5a33")
const METAL := Color("4a4f5a")
const METAL_RENDER := Color("676a72")
const METAL_LIGHT := Color("6f7684")
const PLASTER := Color("f4e4c1")
const WINDOW_GLOW := Color("ffc860")
const OPENING := Color("2a1a10")
const CLOTH_RED := Color("d83a2a")
const CLOTH_BLUE := Color("3a78d8")

static var _cache: Dictionary = {}
## Current night amount (0 = day, 1 = night); read by night lights created mid-transition.
static var night_amount: float = 0.0
## Baked-paint palette: material instance id -> column index, plus the data image/texture.
static var _paint_index: Dictionary = {}
static var _palette_image: Image
static var _palette_texture: ImageTexture


static func _lookup(key: String) -> Material:
	return _cache.get(key) as Material


static func solid(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "solid|%s|%.2f|%.2f" % [color.to_html(), roughness, metallic]
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		_cache[key] = m
		_register_paint(m, color, 0, Color(0, 0, 0, 0), roughness, metallic, 0.5)
	return m


static func emissive(color: Color, energy: float, albedo_mix: float = 0.6) -> StandardMaterial3D:
	var key := "emissive|%s|%.2f|%.2f" % [color.to_html(), energy, albedo_mix]
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color * albedo_mix
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.roughness = 0.4
		_cache[key] = m
		_register_paint(m, color * albedo_mix, 0, Color(color.srgb_to_linear(), energy), 0.4, 0.0, 0.5)
	return m


static func stone(light: Color = STONE, dark: Color = STONE_DARK, block: Vector2 = Vector2(0.46, 0.24)) -> ShaderMaterial:
	var key := "stone|%s|%s|%.2f|%.2f" % [light.to_html(), dark.to_html(), block.x, block.y]
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = STONE_SHADER
		m.set_shader_parameter(&"color_light", light)
		m.set_shader_parameter(&"color_dark", dark)
		m.set_shader_parameter(&"mortar_color", dark.darkened(0.25))
		m.set_shader_parameter(&"block_size", block)
		_cache[key] = m
		_register_paint(m, light, 1, Color(dark.srgb_to_linear(), 0.0), 0.88, 0.0, 0.3, 0, block, 0, dark.darkened(0.25))
	return m


static func stone_dark() -> ShaderMaterial:
	return stone(STONE_DARK.lightened(0.08), STONE_DARK.darkened(0.15), Vector2(0.5, 0.26))


## `local_uv` follows the mesh UV (rounded_box faces carry unit-scaled UVs) for tilted or animated parts.
static func planks(horizontal: bool = true, light: Color = WOOD, dark: Color = WOOD_DARK, width: float = 0.2, local_uv: bool = false) -> ShaderMaterial:
	var key := "planks|%s|%s|%s|%.2f|%s" % [horizontal, light.to_html(), dark.to_html(), width, local_uv]
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = WOOD_SHADER
		m.set_shader_parameter(&"color_light", light)
		m.set_shader_parameter(&"color_dark", dark)
		m.set_shader_parameter(&"seam_color", dark.darkened(0.45))
		m.set_shader_parameter(&"horizontal", horizontal)
		m.set_shader_parameter(&"plank_width", width)
		m.set_shader_parameter(&"use_uv", local_uv)
		_cache[key] = m
		_register_paint(m, light, 2, Color(dark.srgb_to_linear(), 0.0), 0.82, 0.0, 0.3, (1 if horizontal else 0) | (2 if local_uv else 0), Vector2(width, 0.0), 0, dark.darkened(0.45))
	return m


static func roof(base: Color, shadow: Color) -> ShaderMaterial:
	var key := "roof|%s|%s" % [base.to_html(), shadow.to_html()]
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = ROOF_SHADER
		m.set_shader_parameter(&"color_base", base)
		m.set_shader_parameter(&"color_shadow", shadow)
		_cache[key] = m
		_register_paint(m, base, 3, Color(shadow.srgb_to_linear(), 0.0), 0.7, 0.0, 0.45)
	return m


static func roof_red() -> ShaderMaterial:
	return roof(ROOF_RED, ROOF_RED_SHADOW)


static func roof_blue() -> ShaderMaterial:
	return roof(ROOF_BLUE, ROOF_BLUE_SHADOW)


static func wood() -> StandardMaterial3D:
	return solid(WOOD, 0.8)


static func wood_dark() -> StandardMaterial3D:
	return solid(WOOD_DARK, 0.82)


static func plaster() -> StandardMaterial3D:
	return solid(PLASTER, 0.92)


static func metal() -> StandardMaterial3D:
	return solid(METAL_RENDER, 0.58, 0.25)


static func metal_light() -> StandardMaterial3D:
	return solid(METAL_LIGHT, 0.45, 0.35)


static func opening() -> StandardMaterial3D:
	return solid(OPENING, 0.95)


static func gold() -> StandardMaterial3D:
	var key := "gold"
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = GOLD_DEEP
		m.metallic = 0.6
		m.roughness = 0.34
		m.emission_enabled = true
		m.emission = GOLD
		m.emission_energy_multiplier = Tuning.EMISSION_GOLD
		_cache[key] = m
		_register_paint(m, GOLD_DEEP, 0, Color(GOLD.srgb_to_linear(), Tuning.EMISSION_GOLD), 0.34, 0.6, 0.5)
	return m


static func window_glow() -> StandardMaterial3D:
	var m := emissive(WINDOW_GLOW, Tuning.EMISSION_WINDOW, 0.9)
	_set_paint_kind(m, 1)
	return m


static func lantern() -> StandardMaterial3D:
	var m := emissive(Color("ffd77a"), Tuning.EMISSION_LANTERN, 0.9)
	m.emission_energy_multiplier = lerpf(Tuning.DAY_LANTERN_EMISSION, Tuning.NIGHT_LANTERN_EMISSION, night_amount)
	m.emission = Color("ffd77a").lerp(Tuning.NIGHT_WINDOW_COLOR, night_amount * 0.7)
	_set_paint_kind(m, 2)
	return m


static func water() -> StandardMaterial3D:
	var key := "water"
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = WATER
		m.roughness = 0.08
		m.metallic = 0.1
		m.emission_enabled = true
		m.emission = WATER_DEEP
		m.emission_energy_multiplier = 0.15
		m.rim_enabled = true
		m.rim = 0.4
		_cache[key] = m
	return m


static func button_red() -> StandardMaterial3D:
	var key := "button_red"
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = Color("e8322a")
		m.roughness = 0.22
		m.emission_enabled = true
		m.emission = Color("ff3a2a")
		m.emission_energy_multiplier = 0.25
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		_cache[key] = m
		_register_paint(m, Color("e8322a"), 0, Color(Color("ff3a2a").srgb_to_linear(), 0.25), 0.22, 0.0, 0.5)
	return m


static func halo() -> ShaderMaterial:
	var key := "halo"
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = HALO_SHADER
		m.set_shader_parameter(&"color", Tuning.NIGHT_LIGHT_COLOR)
		m.set_shader_parameter(&"intensity", Tuning.HALO_NIGHT_INTENSITY * night_amount)
		_cache[key] = m
	return m


static func rock() -> ShaderMaterial:
	var key := "rock"
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = ROCK_SHADER
		_cache[key] = m
		_register_paint(m, Color(0.62, 0.58, 0.52), 4, Color(Color(0.42, 0.39, 0.35).srgb_to_linear(), 0.0), 0.9, 0.0, 0.25)
	return m


## Drives every shared emissive for the day/night blend. Only touches cached materials.
static func set_night(amount: float) -> void:
	night_amount = clampf(amount, 0.0, 1.0)
	var t: float = night_amount
	RenderingServer.global_shader_parameter_set(&"night_amount", t)
	var win := window_glow()
	win.emission_energy_multiplier = lerpf(Tuning.EMISSION_WINDOW, Tuning.NIGHT_WINDOW_EMISSION, t)
	win.emission = WINDOW_GLOW.lerp(Tuning.NIGHT_WINDOW_COLOR, t)
	win.albedo_color = (WINDOW_GLOW * 0.9).lerp(Tuning.NIGHT_WINDOW_COLOR * 0.5, t)
	lantern()
	var mana_mult: float = lerpf(1.0, Tuning.NIGHT_MANA_MULTIPLIER, t)
	mana_crystal().emission_energy_multiplier = Tuning.EMISSION_MANA_CRYSTAL * mana_mult
	mana_liquid().set_shader_parameter(&"emission_energy", Tuning.EMISSION_MANA * mana_mult)
	bubble().emission_energy_multiplier = 1.5 * mana_mult
	halo().set_shader_parameter(&"intensity", Tuning.HALO_NIGHT_INTENSITY * t)


static func mana_crystal() -> StandardMaterial3D:
	var m := emissive(MANA, Tuning.EMISSION_MANA_CRYSTAL, 0.8)
	_set_paint_kind(m, 3)
	return m


static func mana_liquid() -> ShaderMaterial:
	var key := "mana_liquid"
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = MANA_SHADER
		m.set_shader_parameter(&"color_deep", MANA_DEEP)
		m.set_shader_parameter(&"color_bright", MANA_BRIGHT)
		m.set_shader_parameter(&"emission_energy", Tuning.EMISSION_MANA)
		m.set_shader_parameter(&"pulse_speed", Tuning.MANA_PULSE_SPEED)
		m.set_shader_parameter(&"ripple", Tuning.MANA_RIPPLE)
		_cache[key] = m
	return m


static func glass() -> ShaderMaterial:
	var key := "glass"
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = GLASS_SHADER
		_cache[key] = m
	return m


static func flag(main: Color, trim: Color = GOLD) -> ShaderMaterial:
	var key := "flag|%s|%s" % [main.to_html(), trim.to_html()]
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = FLAG_SHADER
		m.set_shader_parameter(&"color_main", main)
		m.set_shader_parameter(&"color_trim", trim)
		m.set_shader_parameter(&"wave_speed", Tuning.FLAG_WAVE_SPEED)
		m.set_shader_parameter(&"wave_amplitude", Tuning.FLAG_WAVE_AMPLITUDE)
		_cache[key] = m
	return m


static func smoke() -> StandardMaterial3D:
	var key := "smoke"
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.93, 0.93, 0.95)
		m.roughness = 1.0
		m.shadow_to_opacity = false
		_cache[key] = m
	return m


static func bubble() -> StandardMaterial3D:
	var key := "bubble"
	var m := _lookup(key) as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1.0, 0.85, 1.0, 0.8)
		m.emission_enabled = true
		m.emission = MANA_BRIGHT
		m.emission_energy_multiplier = 1.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cache[key] = m
	return m


## The single opaque material of baked buildings (see building_paint.gdshader).
static func paint() -> ShaderMaterial:
	var key := "paint"
	var m := _lookup(key) as ShaderMaterial
	if m == null:
		_ensure_palette()
		m = ShaderMaterial.new()
		m.shader = PAINT_SHADER
		m.set_shader_parameter(&"palette", _palette_texture)
		m.set_shader_parameter(&"window_color", WINDOW_GLOW)
		m.set_shader_parameter(&"night_color", Tuning.NIGHT_WINDOW_COLOR)
		m.set_shader_parameter(&"lantern_color", Color("ffd77a"))
		m.set_shader_parameter(&"window_day", Tuning.EMISSION_WINDOW)
		m.set_shader_parameter(&"window_night", Tuning.NIGHT_WINDOW_EMISSION)
		m.set_shader_parameter(&"lantern_day", Tuning.DAY_LANTERN_EMISSION)
		m.set_shader_parameter(&"lantern_night", Tuning.NIGHT_LANTERN_EMISSION)
		m.set_shader_parameter(&"mana_night_multiplier", Tuning.NIGHT_MANA_MULTIPLIER)
		_cache[key] = m
	return m


## Palette column of an opaque building material, or -1 when it must keep its own material.
static func paint_index(mat: Material) -> int:
	if mat == null:
		return -1
	return _paint_index.get(mat.get_instance_id(), -1)


static func _ensure_palette() -> void:
	if _palette_image == null:
		_palette_image = Image.create_empty(PALETTE_SIZE, 5, false, Image.FORMAT_RGBAF)
		_palette_texture = ImageTexture.create_from_image(_palette_image)


## Writes one material into the palette. Colors are stored linear (the data texture skips sRGB).
static func _register_paint(m: Material, albedo: Color, pattern: int, secondary_linear: Color, roughness: float,
		metallic: float, specular: float, flags: int = 0, params: Vector2 = Vector2.ZERO, kind: int = 0, tertiary: Color = Color.BLACK) -> void:
	_ensure_palette()
	var idx: int = _paint_index.size()
	if idx >= PALETTE_SIZE:
		push_error("materials: paint palette full")
		return
	_paint_index[m.get_instance_id()] = idx
	var a: Color = albedo.srgb_to_linear()
	_palette_image.set_pixel(idx, 0, Color(a.r, a.g, a.b, float(pattern)))
	_palette_image.set_pixel(idx, 1, secondary_linear)
	_palette_image.set_pixel(idx, 2, Color(roughness, metallic, specular, float(flags)))
	_palette_image.set_pixel(idx, 3, Color(params.x, params.y, float(kind), 0.0))
	_palette_image.set_pixel(idx, 4, tertiary.srgb_to_linear())
	_palette_texture.update(_palette_image)


static func _set_paint_kind(m: Material, kind: int) -> void:
	var idx: int = paint_index(m)
	if idx < 0:
		return
	var c: Color = _palette_image.get_pixel(idx, 3)
	if int(c.b) == kind:
		return
	c.b = float(kind)
	_palette_image.set_pixel(idx, 3, c)
	_palette_texture.update(_palette_image)

