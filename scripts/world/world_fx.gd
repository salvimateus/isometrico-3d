extends Node3D

## World clock + shader globals (world_time, spring-followed player_position) and one-shot FX bursts.
## Find it with get_tree().get_first_node_in_group(&"world_fx").

const Tuning := preload("res://scripts/tuning.gd")
const Kit := preload("res://scripts/world/mesh_kit.gd")

var time: float = 0.0
var player: Node3D = null

var _spring_pos := Vector3(0, -100, 0)
var _spring_vel := Vector3.ZERO
var _cache: Dictionary = {}
var _repeller: GPUParticlesAttractorSphere3D
var _clouds_suppressed: bool = false


func _ready() -> void:
	add_to_group(&"world_fx")
	process_priority = -10
	_repeller = GPUParticlesAttractorSphere3D.new()
	_repeller.name = "ButterflyRepeller"
	_repeller.radius = Tuning.BUTTERFLY_FLEE_RADIUS
	_repeller.strength = Tuning.BUTTERFLY_FLEE_STRENGTH
	_repeller.attenuation = 0.6
	_repeller.position = Vector3(0, -100, 0)
	add_child(_repeller)


func _process(delta: float) -> void:
	time += delta
	RenderingServer.global_shader_parameter_set(&"world_time", time)
	if player != null and is_instance_valid(player):
		var target: Vector3 = player.global_position
		if _spring_pos.y < -50.0:
			_spring_pos = target
		var k: float = Tuning.FOLIAGE_PUSH_SPRING
		var damping: float = Tuning.FOLIAGE_PUSH_DAMPING
		_spring_vel += ((target - _spring_pos) * k - _spring_vel * damping) * delta
		_spring_pos += _spring_vel * delta
		RenderingServer.global_shader_parameter_set(&"player_position", _spring_pos)
		_repeller.global_position = target + Vector3(0, 0.8, 0)
		_update_cloud_suppression()


func dust(pos: Vector3, radius: float, strength: float = 1.0) -> void:
	var amount: int = int(round(Tuning.FX_DUST_COUNT * clampf(strength, 0.4, 1.5)))
	_burst(&"dust", pos, amount, 0.9, func() -> Array: return _dust_assets(), radius)


func leaves(pos: Vector3, strength: float = 1.0) -> void:
	var amount: int = int(round(Tuning.FX_LEAF_COUNT * clampf(strength, 0.4, 1.5)))
	_burst(&"leaves", pos, amount, 2.2, func() -> Array: return _leaf_assets(), 0.6)


func splash_drops(pos: Vector3, strength: float = 1.0) -> void:
	var amount: int = int(round(Tuning.POND_SPLASH_DROPS * clampf(strength, 0.4, 1.6)))
	_burst(&"splash", pos, amount, 1.2, func() -> Array: return _splash_assets(), 0.35)


func sparks(pos: Vector3, radius: float) -> void:
	_burst(&"sparks", pos, Tuning.FX_SPARK_COUNT, 0.7, func() -> Array: return _spark_assets(), radius)


func _burst(key: StringName, pos: Vector3, amount: int, lifetime: float, make: Callable, radius: float) -> void:
	if amount <= 0:
		return
	if not _cache.has(key):
		_cache[key] = make.call()
	var assets: Array = _cache[key]
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = lifetime
	p.draw_pass_1 = assets[0]
	p.material_override = assets[1]
	var pm: ParticleProcessMaterial = (assets[2] as ParticleProcessMaterial).duplicate()
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.6
	pm.emission_sphere_radius = radius
	p.process_material = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	p.position = pos
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _scale_curve(peak_at: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(peak_at, 1))
	c.add_point(Vector2(1, 0))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _dust_assets() -> Array:
	var kit := Kit.new()
	kit.add(Kit.sphere(0.24, 8, 5), Transform3D(), Color("D9C29A"), Color("F3E6CC"))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.85)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.radial_velocity_min = 0.8
	pm.radial_velocity_max = 1.8
	pm.gravity = Vector3(0, -0.6, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.scale_curve = _scale_curve(0.2)
	return [kit.commit(), mat, pm]


func _leaf_assets() -> Array:
	# A pair of needles joined at the base; the flapper shader opens and closes them like scissors.
	var kit := Kit.new()
	var c := Color.WHITE
	for side: float in [-1.0, 1.0]:
		var tip := Vector3(side * 0.06, 0, 0.17)
		var mid := Vector3(side * 0.028, 0, 0.06)
		var across := Vector3(0.022, 0, -side * 0.006)
		kit.add_triangle(Vector3(0, 0, -0.05), mid + across, tip, c, c, c, Vector3.UP)
		kit.add_triangle(Vector3(0, 0, -0.05), tip, mid - across, c, c, c, Vector3.UP)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world/flapper.gdshader")
	mat.set_shader_parameter("flap_speed", 4.0)
	mat.set_shader_parameter("flap_angle", 0.4)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 120.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 1.0
	pm.damping_max = 1.6
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.particle_flag_rotate_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.62, 0.86])
	ramp.colors = PackedColorArray([Color("2F8C3E"), Color("3FA34D"), Color("6CC04F"), Color("A0703F")])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_initial_ramp = tex
	pm.scale_curve = _scale_curve(0.1)
	return [kit.commit(), mat, pm]


func _spark_assets() -> Array:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _star_texture()
	mat.emission_enabled = true
	mat.emission = Color("FFE6A0")
	mat.emission_energy_multiplier = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -2.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _scale_curve(0.15)
	pm.color = Color("FFF2C2")
	return [mesh, mat, pm]


func _splash_assets() -> Array:
	var kit := Kit.new()
	kit.add(Kit.sphere(0.07, 8, 5), Transform3D(Basis().scaled(Vector3(1, 1.4, 1)), Vector3.ZERO), Color("BFEFF7"), Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.15
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.85)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 28.0
	pm.initial_velocity_min = 2.6
	pm.initial_velocity_max = 5.0
	pm.radial_velocity_min = 0.6
	pm.radial_velocity_max = 1.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.scale_curve = _scale_curve(0.1)
	return [kit.commit(), mat, pm]


func _star_texture() -> ImageTexture:
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			var p := Vector2(x + 0.5, y + 0.5) / size * 2.0 - Vector2.ONE
			var cross: float = maxf(1.0 - absf(p.x) * 6.0, 0.0) * (1.0 - absf(p.y)) + maxf(1.0 - absf(p.y) * 6.0, 0.0) * (1.0 - absf(p.x))
			var core: float = maxf(1.0 - p.length() * 2.2, 0.0)
			var a: float = clampf(cross + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Clears the sky over the island while the player rides the catapult (mounted through landing).
func _update_cloud_suppression() -> void:
	var busy: bool = (player.has_method(&"is_mounted") and bool(player.call(&"is_mounted"))) \
		or (player.has_method(&"is_launched") and bool(player.call(&"is_launched")))
	if busy == _clouds_suppressed:
		return
	_clouds_suppressed = busy
	for node: Node in get_tree().get_nodes_in_group(&"cloud_field"):
		if node.has_method(&"set_suppressed"):
			node.call(&"set_suppressed", busy)
