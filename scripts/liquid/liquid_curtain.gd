extends Node3D

## Continuous waterfall curtain: one ribbon per active lip cell, hanging from the wet lip down the cliff
## (sliding along physics geometry when it hits it, free-falling otherwise). Width follows the local flow,
## so a weak flow thins into filaments and disappears. The base gets looping foam rings and mist.
## Top level at the identity transform; driven by the liquid field every frame.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const P := preload("res://scripts/liquid/liquid_profile.gd")
const FALLS_SHADER := preload("res://shaders/liquid/liquid_falls.gdshader")
const FOAM_SHADER := preload("res://shaders/liquid/water_foam_patch.gdshader")

var material := ShaderMaterial.new()

var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _profiles: Dictionary = {} # lip id -> [PackedVector3Array points, PackedFloat32Array distances]
var _widths: Dictionary = {} # lip id -> [current flow 0..1, Vector4 lip, Vector2 out]
var _bases: Dictionary = {} # event block key -> {node, mat, phase, strength}
var _noise: Texture2D
var _cell: float = 0.15
var _night: float = 0.0
var _colliders_ready: bool = false


func _init() -> void:
	name = "WaterfallCurtain"
	top_level = true
	material.shader = P.shader(FALLS_SHADER)
	_mi.mesh = _mesh
	_mi.material_override = material
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.custom_aabb = AABB(Vector3(-200, -60, -200), Vector3(400, 120, 400))
	add_child(_mi)


func setup(noise: Texture2D, cell: float) -> void:
	_noise = noise
	_cell = cell
	material.set_shader_parameter(&"noise_tex", noise)


func set_night(amount: float) -> void:
	_night = amount
	material.set_shader_parameter(&"day", 1.0 - amount)
	material.set_shader_parameter(&"body_color", Color(0.42, 0.78, 0.88).lerp(Color(0.16, 0.32, 0.45), amount))
	material.set_shader_parameter(&"foam_color", LT.FOAM_COLOR.lerp(LT.NIGHT_FOAM_COLOR, amount))
	for b: Dictionary in _bases.values():
		(b["mat"] as ShaderMaterial).set_shader_parameter(&"day", 1.0 - amount)


func clear_terrain_cache() -> void:
	_profiles.clear()


## Rendered cliffs and skirts often have no physics: mirror the big static meshes into a private
## collision layer once, so the curtain can follow the visible rock face.
## Call during loading (attach_tower does): builds the colliders and every lip's fall path up front,
## so nothing heavy lands on the frame the first waterfall starts. `lips`/`dirs`: block key -> arrays.
func prepare(lips: Dictionary, dirs: Dictionary) -> void:
	_ensure_colliders()
	await get_tree().physics_frame
	for key: int in lips:
		var l: Array = lips[key]
		var d: Array = dirs[key]
		for i: int in l.size():
			_profile(key * 4096 + i, l[i], d[i])


func _ensure_colliders() -> void:
	if _colliders_ready or not is_inside_tree():
		return
	_colliders_ready = true
	var field: Node = get_parent()
	for n: Node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or field.is_ancestor_of(mi):
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if maxf(box.size.x, box.size.z) < LT.CURTAIN_COLLIDER_MIN_SIZE:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = LT.CURTAIN_COLLISION_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		add_child(body)
		body.global_transform = mi.global_transform


## `targets`: lip id -> [flow 0..1, Vector4 lip (x, z, lip y, base y), Vector2 outward, block key].
func update(targets: Dictionary, delta: float, fx: Node3D) -> void:
	var grow: float = 1.0 - exp(-delta * 3.0)
	var shrink: float = 1.0 - exp(-delta * 1.2)
	for id: int in targets:
		var t: Array = targets[id]
		if not _widths.has(id):
			_widths[id] = [0.0, t[1], t[2], t[3]]
	var block_flow: Dictionary = {}
	var block_pos: Dictionary = {}
	for id: int in _widths.keys():
		var w: Array = _widths[id]
		var target: float = float((targets[id] as Array)[0]) if targets.has(id) else 0.0
		w[0] = lerpf(float(w[0]), target, grow if target > float(w[0]) else shrink)
		if float(w[0]) < 0.02 and target <= 0.0:
			_widths.erase(id)
			continue
		var key: int = w[3]
		block_flow[key] = float(block_flow.get(key, 0.0)) + float(w[0])
		if not block_pos.has(key):
			var prof: Array = _profile(id, w[1], w[2])
			var pts: PackedVector3Array = prof[0]
			block_pos[key] = pts[pts.size() - 1]
	_rebuild()
	_update_bases(block_flow, block_pos, delta, fx)


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _widths.is_empty():
		_mi.visible = false
		return
	_mi.visible = true
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for id: int in _widths:
		var w: Array = _widths[id]
		var flow: float = w[0]
		var lip: Vector4 = w[1]
		var out: Vector2 = w[2]
		var prof: Array = _profile(id, lip, out)
		var pts: PackedVector3Array = prof[0]
		var dist: PackedFloat32Array = prof[1]
		var along := Vector3(-out.y, 0.0, out.x)
		var half: float = _cell * LT.CURTAIN_OVERLAP * 0.5 * clampf(0.35 + 0.65 * flow, 0.0, 1.0)
		var edge_u: float = Vector2(lip.x, lip.y).dot(Vector2(-out.y, out.x))
		var normal := Vector3(out.x, 0.0, out.y)
		var a := Color(1, 1, 1, clampf(flow, 0.0, 1.0))
		for i: int in pts.size() - 1:
			var s0: float = half * (1.0 + dist[i] * LT.CURTAIN_SPREAD)
			var s1: float = half * (1.0 + dist[i + 1] * LT.CURTAIN_SPREAD)
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var quad: Array = [
				[p0 - along * s0, Vector2(0.0, dist[i]), edge_u - s0],
				[p0 + along * s0, Vector2(1.0, dist[i]), edge_u + s0],
				[p1 + along * s1, Vector2(1.0, dist[i + 1]), edge_u + s1],
				[p1 - along * s1, Vector2(0.0, dist[i + 1]), edge_u - s1],
			]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var q: Array = quad[k]
				_mesh.surface_set_color(a)
				_mesh.surface_set_normal(normal)
				_mesh.surface_set_uv(q[1])
				_mesh.surface_set_uv2(Vector2(q[2], 0.0))
				_mesh.surface_add_vertex(q[0])
	_mesh.surface_end()


## Fall path from the lip: ballistic, sliding along physics geometry it meets, down to the base height.
func _profile(id: int, lip: Vector4, out: Vector2) -> Array:
	if _profiles.has(id):
		return _profiles[id]
	_ensure_colliders()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	var o3 := Vector3(out.x, 0.0, out.y)
	var p := Vector3(lip.x, lip.z + 0.03, lip.y) + o3 * 0.06
	var v: Vector3 = o3 * LT.CURTAIN_EXIT_SPEED
	var pts := PackedVector3Array([p])
	var dist := PackedFloat32Array([0.0])
	var total: float = 0.0
	var dt: float = 0.05
	for i: int in 48:
		v.y -= LT.GRAVITY * dt
		var next: Vector3 = p + v * dt
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(p, next, 1 | LT.CURTAIN_COLLISION_LAYER)
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var n: Vector3 = hit["normal"]
				next = (hit["position"] as Vector3) + n * 0.05
				v = (v - n * v.dot(n)) * 0.9
		if next.y <= lip.w:
			next.y = lip.w
			total += p.distance_to(next)
			pts.append(next)
			dist.append(total)
			break
		total += p.distance_to(next)
		p = next
		if i % P.curtain_stride() == P.curtain_stride() - 1:
			pts.append(p)
			dist.append(total)
		if total > 14.0:
			break
	if pts.size() < 2:
		pts.append(p + Vector3.DOWN)
		dist.append(1.0)
	var prof: Array = [pts, dist]
	_profiles[id] = prof
	return prof


func _update_bases(block_flow: Dictionary, block_pos: Dictionary, delta: float, fx: Node3D) -> void:
	for key: int in block_flow:
		if not _bases.has(key):
			var mi := MeshInstance3D.new()
			var disc := PlaneMesh.new()
			disc.size = Vector2(2.0, 2.0)
			mi.mesh = disc
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = FOAM_SHADER
			mat.set_shader_parameter(&"noise_tex", _noise)
			mat.set_shader_parameter(&"seed", randf() * 10.0)
			mat.set_shader_parameter(&"day", 1.0 - _night)
			mat.set_shader_parameter(&"ring_strength", 0.3)
			mi.material_override = mat
			add_child(mi)
			_bases[key] = {"node": mi, "mat": mat, "phase": randf(), "strength": 0.0}
		var b: Dictionary = _bases[key]
		var pos: Vector3 = block_pos[key]
		var strength: float = clampf(float(block_flow[key]) / 4.0, 0.0, 1.0)
		b["strength"] = strength
		b["phase"] = fmod(float(b["phase"]) + delta * 0.45, 1.0)
		var mi: MeshInstance3D = b["node"]
		mi.global_position = pos + Vector3.UP * 0.02
		var r: float = 0.6 + strength * 1.1
		mi.scale = Vector3(r, 1.0, r)
		var mat: ShaderMaterial = b["mat"]
		mat.set_shader_parameter(&"progress", float(b["phase"]) * (0.4 + 0.6 * strength))
		if fx != null and randf() < strength * 8.0 * delta:
			fx.call(&"mist", pos + Vector3.UP * 0.3, 1, 0.6, 0.6, 1.8 + strength)
		if fx != null and randf() < strength * 14.0 * delta:
			fx.call(&"splash", pos + Vector3.UP * 0.02, 3, 1.2, 1.6, 0.4)
	for key: int in _bases.keys():
		if not block_flow.has(key):
			(_bases[key]["node"] as Node).queue_free()
			_bases.erase(key)
