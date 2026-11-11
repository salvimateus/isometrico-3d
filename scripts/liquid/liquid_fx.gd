extends Node3D

## Particle juice for the liquid field: droplets, spray mist, waterfall streaks and splash crowns.
## Everything is emitted on demand (GPUParticles3D.emit_particle) and collides with the scene heightfield.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const P := preload("res://scripts/liquid/liquid_profile.gd")
const DROPLET_SHADER := preload("res://shaders/liquid/liquid_droplet.gdshader")
const MIST_SHADER := preload("res://shaders/liquid/liquid_mist.gdshader")
const CROWN_SHADER := preload("res://shaders/liquid/liquid_crown.gdshader")

const FLAGS: int = GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR

var area := Rect2(-16.0, -16.0, 32.0, 32.0)

var _drops: GPUParticles3D
var _mist: GPUParticles3D
var _falls: GPUParticles3D
var _drop_mat: ShaderMaterial
var _fall_mat: ShaderMaterial
var _mist_mat: ShaderMaterial
var _crowns: Array[Dictionary] = []
var _crown_mesh: Mesh
var _noise: NoiseTexture2D
var _rng := RandomNumberGenerator.new()
var _budget: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_noise = NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	_noise.noise = fn
	_noise.seamless = true
	_noise.width = 128
	_noise.height = 128
	_noise.generate_mipmaps = true

	var aabb := AABB(Vector3(area.position.x - 4.0, -12.0, area.position.y - 4.0), Vector3(area.size.x + 8.0, 24.0, area.size.y + 8.0))
	var collider := GPUParticlesCollisionHeightField3D.new()
	collider.name = "SplashCollider"
	collider.size = Vector3(area.size.x + 4.0, 24.0, area.size.y + 4.0)
	collider.position = Vector3(area.get_center().x, 0.0, area.get_center().y)
	collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(collider)

	_drop_mat = _droplet_material(0.75, false)
	_drops = _particles("Droplets", P.droplet_amount(), 1.6, _drop_process(0.5, 1.0), _quad(Vector2(0.07, 0.07)), _drop_mat, aabb)
	_fall_mat = _droplet_material(2.6, true)
	var fall_process: ParticleProcessMaterial = _drop_process(0.6, 1.3)
	# Falls run down sloped cliffs and skirts instead of vanishing on first touch.
	fall_process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	fall_process.collision_friction = 0.15
	fall_process.collision_bounce = 0.05
	_falls = _particles("FallStreaks", P.fall_amount(), 1.6, fall_process, _quad(Vector2(0.13, 0.13)), _fall_mat, aabb)
	_mist_mat = ShaderMaterial.new()
	_mist_mat.shader = MIST_SHADER
	_mist_mat.set_shader_parameter(&"noise_tex", _noise)
	_mist_mat.set_shader_parameter(&"density", 0.2)
	_mist = _particles("Mist", P.mist_amount(), 2.6, _mist_process(), _quad(Vector2(1.0, 1.0)), _mist_mat, aabb)
	_crown_mesh = _make_crown_mesh()


func set_night(amount: float) -> void:
	var day: float = 1.0 - amount
	for m: ShaderMaterial in [_drop_mat, _fall_mat]:
		m.set_shader_parameter(&"day", day)
	_mist_mat.set_shader_parameter(&"light", lerpf(1.0, 0.32, amount))
	_mist_mat.set_shader_parameter(&"tint", Color(0.93, 0.97, 1.0).lerp(Color(0.55, 0.68, 0.85), amount))


## Radial burst of droplets. `bias` adds a shared velocity (e.g. the incoming jet).
func splash(pos: Vector3, count: int, speed: float, up: float, radius: float, bias: Vector3 = Vector3.ZERO) -> void:
	for i: int in int(ceil(count * P.splash_scale())):
		var a: float = _rng.randf() * TAU
		var r: float = sqrt(_rng.randf()) * radius
		var dir := Vector3(cos(a), 0.0, sin(a))
		var s: float = speed * _rng.randf_range(0.35, 1.0)
		var v: Vector3 = dir * s + Vector3.UP * up * _rng.randf_range(0.4, 1.0) + bias * _rng.randf_range(0.2, 0.7)
		_emit(_drops, pos + dir * r, v, _rng.randf_range(0.6, 1.25))


## Droplets thrown along a direction with a cone spread (jet breakup, spill).
func spray(pos: Vector3, vel: Vector3, count: int, spread: float) -> void:
	for i: int in int(ceil(count * P.splash_scale())):
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * spread
		_emit(_drops, pos + jitter * 0.1, vel + jitter, _rng.randf_range(0.5, 1.0))


func mist(pos: Vector3, count: int, spread: float, rise: float, size: float = 1.0) -> void:
	for i: int in count:
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 0.5), _rng.randf_range(-1, 1)) * spread
		var v := Vector3(off.x * 0.6, rise * _rng.randf_range(0.5, 1.2), off.z * 0.6)
		_emit(_mist, pos + off, v, size * _rng.randf_range(0.7, 1.3))


## Waterfall: a streak leaving the edge with `vel`, plus occasional mist below.
func fall(pos: Vector3, vel: Vector3, base_y: float, strength: float) -> void:
	_emit(_falls, pos, vel + Vector3(_rng.randf_range(-0.2, 0.2), -_rng.randf_range(0.0, 0.6), _rng.randf_range(-0.2, 0.2)), _rng.randf_range(0.7, 1.2) * clampf(0.6 + strength, 0.6, 1.4))
	if _rng.randf() < 0.35:
		var t: float = sqrt(maxf(2.0 * (pos.y - base_y), 0.0) / 9.8)
		var land := Vector3(pos.x + vel.x * t, base_y + 0.2, pos.z + vel.z * t)
		mist(land, 1, 0.8, 0.7, 2.4)
	if _rng.randf() < 0.25:
		spray(pos, vel * 0.8 + Vector3.UP * 0.6, 1, 0.6)


func crown(pos: Vector3, radius: float, height: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _crown_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = CROWN_SHADER
	mat.set_shader_parameter(&"noise_tex", _noise)
	mat.set_shader_parameter(&"seed", _rng.randf() * 10.0)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	_crowns.append({"node": mi, "mat": mat, "t": 0.0, "radius": radius, "height": height})


func _process(delta: float) -> void:
	for i: int in range(_crowns.size() - 1, -1, -1):
		var c: Dictionary = _crowns[i]
		var t: float = float(c["t"]) + delta / 0.75
		c["t"] = t
		var mi: MeshInstance3D = c["node"]
		if t >= 1.0:
			mi.queue_free()
			_crowns.remove_at(i)
			continue
		var grow: float = 1.0 - pow(1.0 - t, 3.0)
		var rise: float = sin(minf(t * 1.6, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, t) * 0.5)
		var r: float = float(c["radius"]) * (0.35 + 0.9 * grow)
		mi.scale = Vector3(r, float(c["height"]) * maxf(rise, 0.02), r)
		(c["mat"] as ShaderMaterial).set_shader_parameter(&"progress", t)


func _emit(p: GPUParticles3D, pos: Vector3, vel: Vector3, scale_mul: float) -> void:
	var b := Basis.IDENTITY.scaled(Vector3.ONE * scale_mul)
	p.emit_particle(Transform3D(b, pos), vel, Color(1, 1, 1, 1), Color(), FLAGS)


func _particles(n: String, amount: int, life: float, process: ParticleProcessMaterial, mesh: Mesh, mat: Material, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.0
	p.amount_ratio = 1.0
	p.emitting = true
	p.process_material = process
	p.draw_pass_1 = mesh
	p.material_override = mat
	p.visibility_aabb = aabb
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.collision_base_size = 0.03
	p.fixed_fps = 0
	p.interpolate = true
	add_child(p)
	return p


func _drop_process(size_min: float, size_max: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3(0.0, -LT.GRAVITY, 0.0)
	m.particle_flag_align_y = true
	m.scale_min = size_min
	m.scale_max = size_max
	m.damping_min = 0.2
	m.damping_max = 0.6
	m.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	m.collision_use_scale = true
	m.color_ramp = _fade_ramp(0.0, 0.85)
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	return m


func _mist_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3(0.0, -0.25, 0.0)
	m.damping_min = 1.2
	m.damping_max = 2.4
	m.scale_min = 0.9
	m.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color_ramp = _fade_ramp(0.12, 0.55)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	return m


func _fade_ramp(fade_in: float, fade_out_start: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0 if fade_in > 0.0 else 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	if fade_in > 0.0:
		g.add_point(fade_in, Color(1, 1, 1, 1))
	g.add_point(fade_out_start, Color(1, 1, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _droplet_material(stretch: float, streak: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DROPLET_SHADER
	m.set_shader_parameter(&"stretch", stretch)
	m.set_shader_parameter(&"streak_mode", streak)
	m.set_shader_parameter(&"softness", 0.75 if streak else 0.55)
	return m


func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0.0, -size.y * 0.5, 0.0)
	return q


func _make_crown_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 28
	var rows: int = 4
	for j: int in rows:
		for i: int in sides:
			for k: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var a: float = float(i + int(k[0])) / float(sides)
				var v: float = float(j + int(k[1])) / float(rows)
				var r: float = 0.7 + 0.45 * v * v
				st.set_uv(Vector2(a, v))
				st.set_normal(Vector3(cos(a * TAU), 0.3, sin(a * TAU)).normalized())
				st.add_vertex(Vector3(cos(a * TAU) * r, v, sin(a * TAU) * r))
	return st.commit()
