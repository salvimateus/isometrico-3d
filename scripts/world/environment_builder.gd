extends RefCounted

## Sun, sky, tonemap, SSAO, glow and fog for the diorama. The sky material lives at
## `WorldEnvironment.environment.sky.sky_material`; the light is the `Sun` node.

const Tuning := preload("res://scripts/tuning.gd")
const Quality := preload("res://scripts/quality.gd")


static func build(parent: Node3D, tonemap: String) -> void:
	# Day/night is driven through `night` (0..1) and `moon_direction` on this material.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/world/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Tuning.DAY_AMBIENT_COLOR
	env.ambient_light_sky_contribution = Tuning.DAY_AMBIENT_SKY_CONTRIBUTION
	env.ambient_light_energy = Tuning.DAY_AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if tonemap == "aces":
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.95
		env.tonemap_white = 6.0
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
		env.tonemap_white = 6.0
	var mobile: bool = Quality.is_mobile()
	# SSAO/SSIL exist only in Forward+.
	var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_enabled = Tuning.SSAO_ENABLED and forward_plus and not mobile
	env.ssao_radius = Tuning.SSAO_RADIUS
	env.ssao_intensity = Tuning.SSAO_INTENSITY
	env.ssao_power = Tuning.SSAO_POWER
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = Tuning.SSIL_ENABLED and forward_plus and not mobile
	env.glow_enabled = Tuning.GLOW_ENABLED
	env.glow_intensity = Tuning.GLOW_INTENSITY
	env.glow_hdr_threshold = Tuning.GLOW_HDR_THRESHOLD
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = Tuning.FOG_ENABLED
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("BFE3F2")
	env.fog_light_energy = 1.0
	env.fog_depth_begin = 105.0
	env.fog_depth_end = 260.0
	env.fog_depth_curve = 1.4
	env.fog_density = 0.6
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = Tuning.FOG_AERIAL_PERSPECTIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Tuning.DAY_SUN_COLOR
	sun.light_energy = Tuning.DAY_SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_blur = Tuning.SHADOW_BLUR
	sun.light_angular_distance = Tuning.SUN_ANGULAR_SIZE_DEG
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = Tuning.MOBILE_SHADOW_MAX_DISTANCE if mobile else Tuning.SHADOW_MAX_DISTANCE
	if mobile:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	parent.add_child(sun)
	# Light travels toward +X and slightly -Z: lit +Z faces, shaded +X faces, shadows to screen bottom-right.
	sun.look_at_from_position(Vector3(-0.85, 1.05, 0.38) * 30.0, Vector3.ZERO, Vector3.UP)
