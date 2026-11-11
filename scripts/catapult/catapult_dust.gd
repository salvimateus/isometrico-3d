extends Node3D

## World-space ground FX for the catapult: round-robin dust puffs, a radial dust wave and water spray.

const T := preload("res://scripts/catapult/catapult_tuning.gd")

var _pool: Array[CPUParticles3D] = []
var _next: int = 0
var _wave: CPUParticles3D
var _spray: CPUParticles3D
var _mesh: SphereMesh


func _init() -> void:
	name = "CatapultDust"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = SphereMesh.new()
	_mesh.radius = 0.5
	_mesh.height = 1.0
	_mesh.radial_segments = 10
	_mesh.rings = 5
	_mesh.material = _material()
	for i: int in T.DUST_POOL:
		var p := _make(16, T.DUST_LIFETIME)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.15
		p.direction = Vector3.UP
		p.spread = 70.0
		_pool.append(p)
	_wave = _make(T.LAND_DUST_COUNT, T.DUST_LIFETIME * 1.4)
	_wave.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_wave.emission_ring_axis = Vector3.UP
	_wave.emission_ring_radius = 0.6
	_wave.emission_ring_inner_radius = 0.45
	_wave.emission_ring_height = 0.0
	_wave.direction = Vector3.UP
	_wave.spread = 15.0
	_wave.initial_velocity_min = 0.6
	_wave.initial_velocity_max = 1.6
	_wave.radial_accel_min = 22.0
	_wave.radial_accel_max = 34.0
	_wave.damping_min = 9.0
	_wave.damping_max = 13.0
	_wave.scale_amount_min = T.DUST_SIZE * 1.6
	_wave.scale_amount_max = T.DUST_SIZE * 2.8

	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	drop.radial_segments = 8
	drop.rings = 4
	drop.material = _material()
	_spray = _make(T.SPRAY_COUNT, T.SPRAY_LIFETIME)
	_spray.mesh = drop
	_spray.explosiveness = 0.97
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_spray.emission_ring_axis = Vector3.UP
	_spray.emission_ring_radius = 0.5
	_spray.emission_ring_inner_radius = 0.2
	_spray.emission_ring_height = 0.0
	_spray.direction = Vector3.UP
	_spray.spread = 32.0
	_spray.initial_velocity_min = T.SPRAY_SPEED_MIN
	_spray.initial_velocity_max = T.SPRAY_SPEED_MAX
	_spray.radial_accel_min = 2.0
	_spray.radial_accel_max = 5.0
	_spray.gravity = Vector3(0.0, -16.0, 0.0)
	_spray.damping_min = 0.0
	_spray.damping_max = 0.5
	_spray.scale_amount_min = T.SPRAY_SIZE * 0.6
	_spray.scale_amount_max = T.SPRAY_SIZE * 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, T.SPRAY_COLOR)
	ramp.set_color(1, Color(T.SPRAY_COLOR, 0.0))
	ramp.add_point(0.75, T.SPRAY_COLOR)
	_spray.color_ramp = ramp


## One-shot puff of `count` particles at `pos`; `speed` scales the upward kick, `size` the particles.
## `push` adds a shared horizontal drift (fire blast).
func puff(pos: Vector3, count: int, speed: float, size: float, push: Vector3 = Vector3.ZERO) -> void:
	var p: CPUParticles3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.global_position = pos
	p.amount = maxi(1, count)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.25
	p.gravity = Vector3(push.x, -1.2, push.z)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.restart()


## Water droplets thrown up and out from a surface point.
func spray(pos: Vector3) -> void:
	_spray.global_position = pos
	_spray.restart()


## Radial dust shockwave hugging the ground.
func wave(pos: Vector3) -> void:
	_wave.global_position = pos + Vector3.UP * 0.05
	_wave.restart()


func _make(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.randomness = 0.4
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.gravity = Vector3(0.0, -1.2, 0.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(T.DUST_COLOR, 0.95))
	ramp.set_color(1, Color(T.DUST_COLOR, 0.0))
	p.color_ramp = ramp
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color.WHITE
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_is_srgb = true
	return m
