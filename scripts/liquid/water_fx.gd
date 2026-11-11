extends Node3D

## Standalone water splash juice (no liquid field needed): splash, squirt, drip trail and step spray.
## One shared instance under the SceneTree root: `load("res://scripts/liquid/water_fx.gd").get_or_create(tree)`.
## Drops are simulated on the CPU (ballistic, collide with the caller's water plane `surface_y`, which
## throws secondary splashes) and drawn as one MultiMesh; mist is GPU particles; column, crown and foam are meshes.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const P := preload("res://scripts/liquid/liquid_profile.gd")
const DROP_SHADER := preload("res://shaders/liquid/water_drop.gdshader")
const MIST_SHADER := preload("res://shaders/liquid/liquid_mist.gdshader")
const CROWN_SHADER := preload("res://shaders/liquid/liquid_crown.gdshader")
const FOAM_SHADER := preload("res://shaders/liquid/water_foam_patch.gdshader")

const NODE_NAME: String = "WaterFx"
const MIST_FLAGS: int = GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR

var _mm := MultiMesh.new()
var _drop_mat := ShaderMaterial.new()
var _mist: GPUParticles3D
var _mist_mat := ShaderMaterial.new()
var _noise: NoiseTexture2D
var _crown_mesh: Mesh
var _column_mesh: Mesh
var _disc := PlaneMesh.new()
var _rng := RandomNumberGenerator.new()
var _night: float = 0.0

# Drop pool (parallel arrays, swap-remove).
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _plane := PackedFloat32Array()
var _foam := PackedFloat32Array()
var _gen := PackedInt32Array()
var _count: int = 0

var _shapes: Array[Dictionary] = [] # column / crown / foam patches
var _squirts: Array[Dictionary] = []
var _trails: Array[Dictionary] = []
var _pending: Array[Callable] = []


static func get_or_create(tree: SceneTree) -> Node3D:
	var root: Window = tree.root
	var existing: Node = root.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing as Node3D
	var script: GDScript = load("res://scripts/liquid/water_fx.gd")
	var fx: Node3D = script.new()
	fx.name = NODE_NAME
	# Deferred so it is safe from _ready(); calls made before it enters the tree are queued.
	root.add_child.call_deferred(fx)
	return fx


func _init() -> void:
	_rng.randomize()
	var n: int = P.water_fx_max_drops()
	_pos.resize(n)
	_vel.resize(n)
	_age.resize(n)
	_life.resize(n)
	_size.resize(n)
	_plane.resize(n)
	_foam.resize(n)
	_gen.resize(n)


func _ready() -> void:
	_noise = NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.02
	fnl.fractal_octaves = 3
	_noise.noise = fnl
	_noise.seamless = true
	_noise.width = 128
	_noise.height = 128
	_noise.generate_mipmaps = true

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = P.water_fx_max_drops()
	_mm.visible_instance_count = 0
	_drop_mat.shader = DROP_SHADER
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Drops"
	mmi.multimesh = _mm
	mmi.material_override = _drop_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	add_child(mmi)

	_mist_mat.shader = MIST_SHADER
	_mist_mat.set_shader_parameter(&"noise_tex", _noise)
	_mist_mat.set_shader_parameter(&"density", 0.22)
	_mist = GPUParticles3D.new()
	_mist.name = "Mist"
	_mist.amount = P.water_fx_mist_amount()
	_mist.lifetime = 1.8
	_mist.emitting = true
	_mist.local_coords = false
	_mist.visibility_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1000, 4000))
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0.0, -0.4, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.5, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_mist.process_material = pm
	var mq := QuadMesh.new()
	mq.size = Vector2.ONE
	_mist.draw_pass_1 = mq
	_mist.material_override = _mist_mat
	add_child(_mist)

	_crown_mesh = _tube_mesh(28, 5, 0.7, 0.45)
	_column_mesh = _tube_mesh(18, 8, 1.0, -0.65)
	_disc.size = Vector2(2.0, 2.0)
	set_night(_night)
	for c: Callable in _pending:
		c.call()
	_pending.clear()


# --- Public API ---------------------------------------------------------------------------------

## Big splash of a body hitting water at `pos`; strength 0.5..1.5 (1 = column ~3 m, crown ~1.7 m radius).
func splash(pos: Vector3, strength: float, surface_y: float) -> void:
	if not is_inside_tree():
		_pending.append(splash.bind(pos, strength, surface_y))
		return
	var s: float = clampf(strength, 0.2, 2.0)
	var base := Vector3(pos.x, surface_y, pos.z)
	var col_v: float = sqrt(2.0 * LT.GRAVITY * LT.WATER_FX_COLUMN_HEIGHT * s)
	# Column of water rising from the hole, its top breaking into drops.
	for i: int in int(70.0 * s):
		var a: float = _rng.randf() * TAU
		var r: float = sqrt(_rng.randf()) * 0.22 * s
		var v := Vector3(cos(a) * _rng.randf_range(0.1, 0.9), col_v * _rng.randf_range(0.55, 1.0), sin(a) * _rng.randf_range(0.1, 0.9))
		_spawn(base + Vector3(cos(a) * r, 0.05, sin(a) * r), v, _rng.randf_range(0.025, 0.06) * sqrt(s), surface_y, _rng.randf_range(0.3, 1.0), 0)
	# Crown sheet breaking into arcing drops.
	var crown_r: float = LT.WATER_FX_CROWN_RADIUS * s
	for i: int in int(150.0 * s):
		var a: float = _rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var out: float = _rng.randf_range(1.6, 3.6) * sqrt(s)
		var up: float = _rng.randf_range(2.2, 4.4) * sqrt(s)
		_spawn(base + dir * _rng.randf_range(0.25, 0.5) * s + Vector3.UP * 0.05, dir * out + Vector3.UP * up, _rng.randf_range(0.018, 0.05) * sqrt(s), surface_y, _rng.randf_range(0.3, 1.0), 0)
	_shape(_column_mesh, CROWN_SHADER, base, 0.24 * s, LT.WATER_FX_COLUMN_HEIGHT * s, 0.9, &"column")
	_shape(_crown_mesh, CROWN_SHADER, base, crown_r, 0.8 * s, 0.7, &"crown")
	_foam_patch(base, 1.2 * s + 0.6, 2.6, false)
	_foam_patch(base, 2.4 * s + 0.6, 1.6, true)
	for i: int in int(10.0 * s):
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 1.2), _rng.randf_range(-1, 1)) * 0.6 * s
		_mist_puff(base + off + Vector3.UP * 0.3, Vector3(off.x, _rng.randf_range(0.4, 1.2), off.z) * 0.8, 1.4 * s)


## Thin continuous jet from `origin` along `dir` (normalized) for `seconds`, splashing where it lands.
func squirt(origin: Vector3, dir: Vector3, seconds: float, surface_y: float) -> void:
	if not is_inside_tree():
		_pending.append(squirt.bind(origin, dir, seconds, surface_y))
		return
	_squirts.append({"origin": origin, "dir": dir.normalized(), "t": seconds, "plane": surface_y})


## Drops falling off a moving node (wet body leaving the water) for `seconds`.
func drip_trail(node: Node3D, seconds: float) -> void:
	if not is_inside_tree():
		_pending.append(drip_trail.bind(node, seconds))
		return
	_trails.append({"node": node, "t": seconds, "total": seconds, "acc": 0.0})


## Small spray of a step or a light touch on the water; strength 0.2..1.5.
func ripple_spray(pos: Vector3, strength: float, surface_y: float) -> void:
	if not is_inside_tree():
		_pending.append(ripple_spray.bind(pos, strength, surface_y))
		return
	var s: float = clampf(strength, 0.1, 2.0)
	var base := Vector3(pos.x, surface_y, pos.z)
	for i: int in int(14.0 * s) + 3:
		var a: float = _rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		_spawn(base + dir * 0.12, dir * _rng.randf_range(0.4, 1.4) * s + Vector3.UP * _rng.randf_range(1.0, 2.4) * sqrt(s), _rng.randf_range(0.012, 0.03), surface_y, _rng.randf_range(0.0, 0.5), 1)
	_foam_patch(base, 0.45 * s + 0.25, 1.1, true)


func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	var day: float = 1.0 - _night
	_drop_mat.set_shader_parameter(&"day", day)
	_mist_mat.set_shader_parameter(&"light", lerpf(1.0, 0.32, _night))
	_mist_mat.set_shader_parameter(&"tint", Color(0.93, 0.97, 1.0).lerp(Color(0.55, 0.68, 0.85), _night))
	for s: Dictionary in _shapes:
		(s["mat"] as ShaderMaterial).set_shader_parameter(&"day", day)


# --- Simulation ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_emitters(delta)
	_update_drops(delta)
	_update_shapes(delta)


func _update_emitters(delta: float) -> void:
	for i: int in range(_squirts.size() - 1, -1, -1):
		var q: Dictionary = _squirts[i]
		q["t"] = float(q["t"]) - delta
		if float(q["t"]) <= 0.0:
			_squirts.remove_at(i)
			continue
		var d: Vector3 = q["dir"]
		for k: int in int(ceil(LT.WATER_FX_SQUIRT_RATE * delta)):
			var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.25
			_spawn(q["origin"], (d + jitter * 0.12) * LT.WATER_FX_SQUIRT_SPEED * _rng.randf_range(0.9, 1.05), _rng.randf_range(0.014, 0.026), q["plane"], 0.15, 0)
	for i: int in range(_trails.size() - 1, -1, -1):
		var tr: Dictionary = _trails[i]
		var node: Node3D = tr["node"]
		tr["t"] = float(tr["t"]) - delta
		if float(tr["t"]) <= 0.0 or not is_instance_valid(node) or not node.is_inside_tree():
			_trails.remove_at(i)
			continue
		var k: float = float(tr["t"]) / float(tr["total"])
		tr["acc"] = float(tr["acc"]) + delta * LT.WATER_FX_DRIP_RATE * (0.3 + 0.7 * k)
		while float(tr["acc"]) >= 1.0:
			tr["acc"] = float(tr["acc"]) - 1.0
			var p: Vector3 = node.global_position + Vector3(_rng.randf_range(-0.22, 0.22), _rng.randf_range(0.1, 0.9), _rng.randf_range(-0.22, 0.22))
			_spawn(p, Vector3(0.0, -0.4, 0.0), _rng.randf_range(0.015, 0.03), p.y - 3.0, 0.1, 1, 1.2)


func _update_drops(delta: float) -> void:
	var g := Vector3(0.0, -LT.GRAVITY, 0.0)
	var i: int = 0
	while i < _count:
		_age[i] += delta
		var v: Vector3 = _vel[i] + g * delta
		v *= 1.0 - 0.15 * delta
		var p: Vector3 = _pos[i] + v * delta
		if (p.y <= _plane[i] and v.y < 0.0) or _age[i] >= _life[i]:
			if p.y <= _plane[i] and v.y < -1.5:
				_on_land(Vector3(p.x, _plane[i], p.z), v, _size[i], _gen[i], _plane[i])
			_kill(i)
			continue
		_pos[i] = p
		_vel[i] = v
		i += 1
	_mm.visible_instance_count = _count
	for j: int in _count:
		var v: Vector3 = _vel[j]
		var speed: float = v.length()
		var dir: Vector3 = v / speed if speed > 0.01 else Vector3.UP
		var side: Vector3 = dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
		var r: float = _size[j]
		var half: float = r * (1.0 + minf(speed * 0.35, 3.0))
		var basis := Basis(side * r, dir * half, side.cross(dir) * r)
		_mm.set_instance_transform(j, Transform3D(basis, _pos[j]))
		var fade: float = 1.0 - smoothstep(0.75, 1.0, _age[j] / _life[j])
		_mm.set_instance_color(j, Color(1, 1, 1, fade))
		_mm.set_instance_custom_data(j, Color(_foam[j], 0, 0, 0))


func _on_land(p: Vector3, v: Vector3, size: float, gen: int, plane: float) -> void:
	if gen >= 1 or _count > P.water_fx_max_drops() - 40:
		return
	var energy: float = clampf(-v.y / 6.0, 0.0, 1.0) * clampf(size / 0.04, 0.3, 1.2)
	if _rng.randf() > 0.35 + energy * 0.5:
		return
	for k: int in 2 + int(energy * 4.0):
		var a: float = _rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		_spawn(p + Vector3.UP * 0.01, dir * _rng.randf_range(0.3, 1.0) + Vector3.UP * _rng.randf_range(0.8, 1.8) * (0.5 + energy), size * 0.45, plane, _rng.randf_range(0.2, 0.8), gen + 1)
	if energy > 0.5 and _rng.randf() < 0.25:
		_foam_patch(p, 0.35 + energy * 0.3, 0.9, true)


func _spawn(p: Vector3, v: Vector3, size: float, plane: float, foam: float, gen: int, life: float = 3.0) -> void:
	if _count >= P.water_fx_max_drops():
		return
	var i: int = _count
	_pos[i] = p
	_vel[i] = v
	_age[i] = 0.0
	_life[i] = life
	_size[i] = size
	_plane[i] = plane
	_foam[i] = foam
	_gen[i] = gen
	_count += 1


func _kill(i: int) -> void:
	var last: int = _count - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_size[i] = _size[last]
		_plane[i] = _plane[last]
		_foam[i] = _foam[last]
		_gen[i] = _gen[last]
	_count = last


# --- Meshes -------------------------------------------------------------------------------------

func _mist_puff(p: Vector3, v: Vector3, size: float) -> void:
	_mist.emit_particle(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p), v, Color(1, 1, 1, 1), Color(), MIST_FLAGS)


func _shape(mesh: Mesh, shader: Shader, p: Vector3, radius: float, height: float, life: float, kind: StringName) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"noise_tex", _noise)
	mat.set_shader_parameter(&"seed", _rng.randf() * 10.0)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = p
	mi.scale = Vector3(0.01, 0.01, 0.01)
	_shapes.append({"node": mi, "mat": mat, "t": 0.0, "life": life, "radius": radius, "height": height, "kind": kind})


func _foam_patch(p: Vector3, radius: float, life: float, ring: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = FOAM_SHADER
	mat.set_shader_parameter(&"noise_tex", _noise)
	mat.set_shader_parameter(&"seed", _rng.randf() * 10.0)
	mat.set_shader_parameter(&"ring_only", 1.0 if ring else 0.0)
	mat.set_shader_parameter(&"day", 1.0 - _night)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = p + Vector3.UP * 0.012
	mi.scale = Vector3(radius, 1.0, radius)
	_shapes.append({"node": mi, "mat": mat, "t": 0.0, "life": life, "radius": radius, "height": 1.0, "kind": &"foam"})


func _update_shapes(delta: float) -> void:
	for i: int in range(_shapes.size() - 1, -1, -1):
		var s: Dictionary = _shapes[i]
		var t: float = float(s["t"]) + delta / float(s["life"])
		s["t"] = t
		var mi: MeshInstance3D = s["node"]
		if t >= 1.0:
			mi.queue_free()
			_shapes.remove_at(i)
			continue
		var mat: ShaderMaterial = s["mat"]
		mat.set_shader_parameter(&"progress", t)
		var r: float = s["radius"]
		var h: float = s["height"]
		match s["kind"]:
			&"column":
				# Shoots up fast, hangs, then slumps back into the surface.
				var rise: float = sin(minf(t / 0.45, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.5, 1.0, t))
				mi.scale = Vector3(r * (1.0 + t * 0.6), maxf(h * rise, 0.02), r * (1.0 + t * 0.6))
			&"crown":
				var grow: float = 1.0 - pow(1.0 - t, 3.0)
				var lift: float = sin(minf(t * 1.8, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.6, 1.0, t) * 0.6)
				mi.scale = Vector3(r * (0.3 + 0.7 * grow), maxf(h * lift, 0.02), r * (0.3 + 0.7 * grow))
			_:
				pass


## Open tube, radius 1 at the base; `flare` widens (or narrows when negative) toward the top.
func _tube_mesh(sides: int, rows: int, base_r: float, flare: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in rows:
		for i: int in sides:
			for k: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var a: float = float(i + int(k[0])) / float(sides)
				var v: float = float(j + int(k[1])) / float(rows)
				var r: float = maxf(base_r + flare * v * v, 0.05)
				st.set_uv(Vector2(a, v))
				st.set_normal(Vector3(cos(a * TAU), 0.3, sin(a * TAU)).normalized())
				st.add_vertex(Vector3(cos(a * TAU) * r, v, sin(a * TAU) * r))
	return st.commit()
