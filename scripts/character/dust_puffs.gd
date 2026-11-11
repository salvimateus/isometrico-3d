extends Node3D

## World-space dust: round-robin one-shot puffs (steps, skids, takeoff), a radial landing ring, a crash
## crater and a continuous thin running trail. Water effects live in scripts/liquid/water_fx.gd. Cheap CPU particles sharing one mesh and material.

const T := preload("res://scripts/character/character_tuning.gd")
const Mats := preload("res://scripts/character/character_materials.gd")
const Q := preload("res://scripts/character/char_quality.gd")

var _pool: Array[CPUParticles3D] = []
var _next: int = 0
var _ring: CPUParticles3D
var _trail: CPUParticles3D
var _crater: MeshInstance3D
var _crater_mat: StandardMaterial3D
var _crater_tween: Tween


func _init() -> void:
	name = "DustPuffs"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = Mats.get_dust_material()
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.15))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(T.DUST_COLOR, 0.9))
	ramp.set_color(1, Color(T.DUST_COLOR, 0.0))

	for i: int in T.DUST_POOL_SIZE:
		var p := _make(mesh, scale_curve, ramp, T.DUST_PER_STEP, T.DUST_LIFETIME, T.DUST_SIZE)
		p.one_shot = true
		p.explosiveness = 0.95
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.07
		p.direction = Vector3.UP
		p.spread = 75.0
		p.initial_velocity_min = 0.35
		p.initial_velocity_max = 0.9
		_pool.append(p)

	_ring = _make(mesh, scale_curve, ramp, T.DUST_RING_AMOUNT, T.DUST_LIFETIME * 1.2, T.DUST_SIZE * 1.2)
	_ring.one_shot = true
	_ring.explosiveness = 1.0
	_ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_ring.emission_ring_axis = Vector3.UP
	_ring.emission_ring_radius = 0.22
	_ring.emission_ring_inner_radius = 0.18
	_ring.emission_ring_height = 0.0
	_ring.direction = Vector3.UP
	_ring.spread = 10.0
	_ring.initial_velocity_min = 0.2
	_ring.initial_velocity_max = 0.5
	_ring.radial_accel_min = 9.0
	_ring.radial_accel_max = 14.0
	_ring.damping_min = 5.0
	_ring.damping_max = 7.0

	_crater = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.6)
	_crater.mesh = plane
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.75))
	grad.add_point(0.55, Color(1.0, 1.0, 1.0, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_crater_mat = StandardMaterial3D.new()
	_crater_mat.albedo_texture = tex
	_crater_mat.albedo_color = Color(0.42, 0.28, 0.15, 0.0)
	_crater_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crater_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_crater_mat.roughness = 1.0
	_crater.material_override = _crater_mat
	_crater.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crater.visible = false
	add_child(_crater)

	_trail = _make(mesh, scale_curve, ramp, T.TRAIL_AMOUNT, T.TRAIL_LIFETIME, T.TRAIL_SIZE)
	_trail.one_shot = false
	_trail.explosiveness = 0.0
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 0.08
	_trail.direction = Vector3.UP
	_trail.spread = 40.0
	_trail.initial_velocity_min = 0.1
	_trail.initial_velocity_max = 0.3


func _make(mesh: Mesh, scale_curve: Curve, ramp: Gradient, amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = Q.particles(amount)
	p.lifetime = lifetime
	p.randomness = 0.4
	p.local_coords = false
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gravity = Vector3(0.0, -0.4, 0.0)
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.3
	p.scale_amount_curve = scale_curve
	p.color_ramp = ramp
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	return p


func puff(world_pos: Vector3, back_dir: Vector3, strength: float = 1.0) -> void:
	var p: CPUParticles3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.global_position = world_pos + Vector3(0.0, 0.04, 0.0)
	p.direction = (back_dir * 0.6 + Vector3.UP).normalized()
	p.initial_velocity_max = 0.9 * strength
	p.restart()


func ring(world_pos: Vector3, strength: float) -> void:
	_ring.global_position = world_pos + Vector3(0.0, 0.03, 0.0)
	var k: float = clampf(strength, 0.3, 1.5)
	_ring.radial_accel_min = 9.0 * k
	_ring.radial_accel_max = 14.0 * k
	_ring.scale_amount_max = T.DUST_SIZE * 1.6 * k
	_ring.restart()


## Heavy crash: big dust ring, a ring of puffs and a dusty crater decal that fades out.
func crater(world_pos: Vector3, strength: float) -> void:
	ring(world_pos, strength)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		puff(world_pos + dir * 0.35, dir, 1.4)
	_crater.global_position = world_pos + Vector3(0.0, 0.02, 0.0)
	_crater.visible = true
	_crater_mat.albedo_color.a = 1.0
	_crater.scale = Vector3.ONE * 0.6
	if _crater_tween != null:
		_crater_tween.kill()
	_crater_tween = create_tween()
	_crater_tween.tween_property(_crater, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_crater_tween.tween_interval(2.0)
	_crater_tween.tween_property(_crater_mat, "albedo_color:a", 0.0, 1.5)
	_crater_tween.tween_callback(func() -> void: _crater.visible = false)


## Call every frame; the trail emits only while `active`.
func trail(world_pos: Vector3, active: bool) -> void:
	_trail.global_position = world_pos + Vector3(0.0, 0.03, 0.0)
	if _trail.emitting != active:
		_trail.emitting = active
