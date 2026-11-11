extends Node3D

## Wind trail that follows a flying body: camera-facing ribbon of recent positions, velocity-aligned
## wind streaks and little cloud puffs left in the air.

const T := preload("res://scripts/catapult/catapult_tuning.gd")

var _target: Node3D
var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _ribbon: MeshInstance3D
var _imesh: ImmediateMesh
var _ribbon_mat: StandardMaterial3D
var _streaks: CPUParticles3D
var _puffs: CPUParticles3D
var _prev := Vector3.ZERO
var _vel := Vector3.ZERO
var _following: bool = false


func _init() -> void:
	name = "CatapultFlightFx"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_imesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _imesh
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_mat.vertex_color_use_as_albedo = true
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_mat.disable_fog = true
	add_child(_ribbon)

	var streak_mesh := CylinderMesh.new()
	streak_mesh.top_radius = 0.018
	streak_mesh.bottom_radius = 0.018
	streak_mesh.height = 0.7
	streak_mesh.radial_segments = 4
	streak_mesh.rings = 1
	streak_mesh.material = _particle_material()
	_streaks = CPUParticles3D.new()
	_streaks.mesh = streak_mesh
	_streaks.amount = T.STREAK_AMOUNT
	_streaks.lifetime = T.STREAK_LIFETIME
	_streaks.local_coords = false
	_streaks.emitting = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_streaks.emission_sphere_radius = 0.7
	_streaks.particle_flag_align_y = true
	_streaks.spread = 4.0
	_streaks.gravity = Vector3.ZERO
	_streaks.initial_velocity_min = 2.0
	_streaks.initial_velocity_max = 4.0
	_streaks.color_ramp = _ramp(Color(1, 1, 1, 0.75))
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_streaks)

	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4
	puff_mesh.material = _particle_material()
	_puffs = CPUParticles3D.new()
	_puffs.mesh = puff_mesh
	_puffs.amount = 30
	_puffs.lifetime = 0.7
	_puffs.local_coords = false
	_puffs.emitting = false
	_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_puffs.emission_sphere_radius = 0.25
	_puffs.gravity = Vector3(0.0, 0.3, 0.0)
	_puffs.spread = 180.0
	_puffs.initial_velocity_min = 0.2
	_puffs.initial_velocity_max = 0.6
	_puffs.scale_amount_min = 0.25
	_puffs.scale_amount_max = 0.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.1))
	_puffs.scale_amount_curve = curve
	_puffs.color_ramp = _ramp(Color(1, 1, 1, 0.8))
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_puffs)
	set_process(false)


# Godot re-enables processing on ready when _process exists; stay idle until used.
func _ready() -> void:
	set_process(false)


func follow(target: Node3D) -> void:
	_target = target
	_following = true
	_points.clear()
	_ages.clear()
	_prev = _sample()
	_vel = Vector3.ZERO
	_streaks.global_position = _prev
	_puffs.global_position = _prev
	_streaks.emitting = true
	_puffs.emitting = true
	set_process(true)


## Stops emitting; the ribbon and particles fade out on their own.
func release() -> void:
	_following = false
	_streaks.emitting = false
	_puffs.emitting = false


func _sample() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return _prev
	return _target.get_global_transform_interpolated().origin + Vector3.UP * T.TRAIL_HEIGHT


func _process(delta: float) -> void:
	for i: int in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[0] > T.TRAIL_LIFETIME:
		_ages.pop_front()
		_points.pop_front()
	if _following:
		var pos: Vector3 = _sample()
		if delta > 0.0:
			_vel = _vel.lerp((pos - _prev) / delta, 1.0 - exp(-20.0 * delta))
		_prev = pos
		_points.append(pos)
		_ages.append(0.0)
		while _points.size() > T.TRAIL_POINTS:
			_points.pop_front()
			_ages.pop_front()
		_streaks.global_position = pos
		_puffs.global_position = pos
		if _vel.length() > 0.5:
			_streaks.direction = -_vel.normalized()
			_puffs.direction = -_vel.normalized()
	_rebuild()
	if not _following and _points.is_empty() and not _streaks.emitting:
		set_process(false)


func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = cam.global_position
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ribbon_mat)
	var n: int = _points.size()
	for i: int in n:
		var p: Vector3 = _points[i]
		var nxt: Vector3 = _points[mini(i + 1, n - 1)]
		var prv: Vector3 = _points[maxi(i - 1, 0)]
		var tangent: Vector3 = (nxt - prv)
		if tangent.length_squared() < 1e-6:
			tangent = Vector3.UP
		var side: Vector3 = tangent.cross(eye - p).normalized()
		var along: float = float(i) / float(n - 1)
		var life: float = 1.0 - clampf(_ages[i] / T.TRAIL_LIFETIME, 0.0, 1.0)
		var w: float = T.TRAIL_WIDTH * along * life
		var c := Color(T.TRAIL_COLOR, T.TRAIL_COLOR.a * along * life)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * w * 0.5)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * w * 0.5)
	_imesh.surface_end()


static func _particle_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_is_srgb = true
	m.no_depth_test = false
	return m


static func _ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c, 0.0))
	return g
