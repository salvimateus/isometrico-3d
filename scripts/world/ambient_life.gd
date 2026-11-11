extends RefCounted

## Light ambient particles: butterflies over the meadow, falling leaves, birds circling high.

const Tuning := preload("res://scripts/tuning.gd")
const Kit := preload("res://scripts/world/mesh_kit.gd")
const Quality := preload("res://scripts/quality.gd")


static func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "AmbientLife"
	parent.add_child(root)
	root.add_child(_butterflies())
	root.add_child(_leaves())
	root.add_child(_birds())


static func _wing_mesh(span: float, depth: float) -> ArrayMesh:
	var kit := Kit.new()
	var white := Color.WHITE
	var n := Vector3.UP
	for side: float in [-1.0, 1.0]:
		kit.add_triangle(Vector3(0, 0, -depth * 0.2), Vector3(side * span, 0, -depth * 0.6), Vector3(side * span * 0.8, 0, depth * 0.35), white, white, white, n)
		kit.add_triangle(Vector3(0, 0, -depth * 0.2), Vector3(side * span * 0.8, 0, depth * 0.35), Vector3(0, 0, depth * 0.3), white, white, white, n)
	return kit.commit()


## Small gull: a rounded body with tapered two-tone wings (flap shader bends vertices by |x|).
static func _bird_mesh() -> ArrayMesh:
	var kit := Kit.new()
	kit.add(Kit.sphere(0.07, 8, 5), Transform3D(Basis().scaled(Vector3(0.8, 0.7, 2.0)), Vector3.ZERO), Color("C9D2DE"), Color.WHITE)
	var tip := Color("6F7C8E")
	var root := Color.WHITE
	for side: float in [-1.0, 1.0]:
		kit.add_triangle(Vector3(0, 0.01, -0.06), Vector3(side * 0.3, 0.02, 0.0), Vector3(0, 0.01, 0.08), root, tip, root, Vector3.UP)
		kit.add_triangle(Vector3(side * 0.3, 0.02, 0.0), Vector3(side * 0.12, 0.0, 0.1), Vector3(0, 0.01, 0.08), tip, root, root, Vector3.UP)
	return kit.commit()


static func _flap_material(speed: float, angle: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world/flapper.gdshader")
	mat.set_shader_parameter("flap_speed", speed)
	mat.set_shader_parameter("flap_angle", angle)
	return mat


static func _butterflies() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Butterflies"
	p.amount = maxi(1, int(round(Tuning.BUTTERFLY_COUNT * (Tuning.MOBILE_PARTICLE_SCALE if Quality.is_mobile() else 1.0))))
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-24, -2, -24), Vector3(48, 8, 48))
	p.draw_pass_1 = _wing_mesh(0.12, 0.16)
	p.material_override = _flap_material(16.0, 1.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(15, 0.6, 15)
	p.position = Vector3(0, 1.3, 0)
	m.gravity = Vector3.ZERO
	m.direction = Vector3(1, 0, 0)
	m.spread = 180.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 0.7
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.2
	m.turbulence_noise_scale = 3.0
	m.turbulence_noise_speed_random = 0.6
	m.turbulence_influence_min = 0.08
	m.turbulence_influence_max = 0.2
	m.particle_flag_rotate_y = true
	m.angle_min = -180.0
	m.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([Color("FFE45C"), Color("FF8FC1"), Color("FFFFFF"), Color("8FD3FF")])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_initial_ramp = tex
	var scale := Curve.new()
	scale.add_point(Vector2(0, 0))
	scale.add_point(Vector2(0.08, 1))
	scale.add_point(Vector2(0.92, 1))
	scale.add_point(Vector2(1, 0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale
	m.scale_curve = scale_tex
	p.process_material = m
	return p


static func _leaves() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Leaves"
	p.amount = maxi(1, int(round(Tuning.LEAF_COUNT * (Tuning.MOBILE_PARTICLE_SCALE if Quality.is_mobile() else 1.0))))
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = Vector3(0, 3.2, 0)
	p.visibility_aabb = AABB(Vector3(-24, -5, -24), Vector3(48, 8, 48))
	p.draw_pass_1 = _wing_mesh(0.07, 0.12)
	p.material_override = _flap_material(3.0, 0.5)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 17.0
	m.emission_ring_inner_radius = 13.0
	m.emission_ring_height = 0.6
	m.gravity = Vector3(0.25, -0.35, 0.1)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.2
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.5
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.12
	m.angular_velocity_min = -120.0
	m.angular_velocity_max = 120.0
	m.particle_flag_rotate_y = true
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color("7AD058"), Color("FFC93C"), Color("E07B39")])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_initial_ramp = tex
	var scale := Curve.new()
	scale.add_point(Vector2(0, 0))
	scale.add_point(Vector2(0.1, 1))
	scale.add_point(Vector2(0.85, 1))
	scale.add_point(Vector2(1, 0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale
	m.scale_curve = scale_tex
	p.process_material = m
	return p


static func _birds() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Birds"
	p.amount = maxi(1, int(round(Tuning.BIRD_COUNT * (Tuning.MOBILE_PARTICLE_SCALE if Quality.is_mobile() else 1.0))))
	p.lifetime = 30.0
	p.preprocess = 30.0
	p.position = Vector3(0, 13.0, 0)
	p.visibility_aabb = AABB(Vector3(-60, -4, -60), Vector3(120, 8, 120))
	p.draw_pass_1 = _bird_mesh()
	p.material_override = _flap_material(7.0, 0.55)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(30, 1.0, 30)
	m.gravity = Vector3.ZERO
	m.direction = Vector3(-1, 0, -0.4)
	m.spread = 25.0
	m.initial_velocity_min = 1.6
	m.initial_velocity_max = 2.2
	m.particle_flag_rotate_y = true
	m.angle_min = 68.0
	m.angle_max = 68.0
	m.color = Color("E9EEF5")
	p.process_material = m
	return p
