extends RefCounted

## Places nature props with MultiMeshInstance3D: dense forest ring, sparse life inside the base.

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const Meshes := preload("res://scripts/world/decor_meshes.gd")
const Mats := preload("res://scripts/world/world_materials.gd")
const GroundData := preload("res://scripts/world/ground_data.gd")
const Quality := preload("res://scripts/quality.gd")

var _rng := RandomNumberGenerator.new()
var _ground: GroundData
var _hash: Dictionary = {}
var tree_points: Array[Vector3] = []
var rock_points: Array[Vector3] = []
## Shakeable instances: {"multimesh", "index", "pos" (Vector2), "scale", "custom", "kind"}.
var shakers: Array[Dictionary] = []


func build(parent: Node3D, ground: GroundData) -> void:
	_rng.seed = 20261110
	_ground = ground
	var root := Node3D.new()
	root.name = "Decor"
	parent.add_child(root)
	var bush_mat: ShaderMaterial = Mats.foliage(&"bush", 0.04, 0.7)
	bush_mat.set_shader_parameter("shake_amount", Tuning.BUSH_SHAKE_AMOUNT)
	_set_push(bush_mat, Tuning.FOLIAGE_PUSH_BUSH)
	var pines: Array = _place_trees(_n(Tuning.TREE_PINE_COUNT))
	for v: int in Meshes.PINE_VARIANTS:
		var pine_mat: ShaderMaterial = Mats.foliage(StringName("pine_%d" % v), 0.06, Meshes.pine_height(v))
		pine_mat.set_shader_parameter("shake_amount", Tuning.TREE_SHAKE_AMOUNT)
		_add(root, "Pines%d" % v, Meshes.pine_variant(v), pine_mat, pines[v], true, &"tree")
	_add(root, "Bushes", Meshes.bush(), bush_mat, _place_bushes(), true, &"bush")
	var rocks: Array = _place_rocks()
	for v: int in 4:
		var subset: Array = []
		for i: int in rocks.size():
			if i % 4 == v:
				subset.append(rocks[i])
		_add(root, "Rocks%d" % v, Meshes.rock(v), Mats.vertex_color(&"rock", 0.9), subset, true)
	_add(root, "Pebbles", Meshes.rock(4), Mats.vertex_color(&"rock", 0.9), _place_pebbles(), true)
	var flower_mat: ShaderMaterial = Mats.foliage(&"flower", 0.05, 0.2)
	var tuft_mat: ShaderMaterial = Mats.foliage(&"tuft", 0.07, 0.35, true)
	var reed_mat: ShaderMaterial = Mats.foliage(&"reed", 0.06, 0.6)
	_set_push(flower_mat, Tuning.FOLIAGE_PUSH_FLOWER)
	_set_push(tuft_mat, Tuning.FOLIAGE_PUSH_TUFT)
	_set_push(reed_mat, Tuning.FOLIAGE_PUSH_REED)
	_add(root, "Flowers", Meshes.flower(), flower_mat, _place_flowers(), false)
	_add(root, "Mushrooms", Meshes.mushroom(), Mats.vertex_color(&"mushroom", 0.7), _place_mushrooms(), false)
	_add(root, "GrassTufts", Meshes.grass_tuft(), tuft_mat, _place_tufts(), false)
	var lily_mat: ShaderMaterial = Mats.foliage(&"lily", 0.0, 1.0)
	lily_mat.set_shader_parameter("splash_bob", 1.0)
	reed_mat.set_shader_parameter("splash_bob", 0.6)
	_add(root, "LilyPads", Meshes.lily_pad(), lily_mat, _place_lily_pads(), false)
	_add(root, "Reeds", Meshes.reed(), reed_mat, _place_reeds(), false)


## Scatter count for the active quality tier.
func _n(count: int) -> int:
	return int(round(count * Tuning.MOBILE_SCATTER_SCALE)) if Quality.is_mobile() else count


func _set_push(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("push_amount", amount)
	mat.set_shader_parameter("push_radius", Tuning.FOLIAGE_PUSH_RADIUS)


func _add(root: Node3D, node_name: String, mesh: Mesh, mat: Material, items: Array, shadows: bool, shake_kind: StringName = &"") -> void:
	if items.is_empty():
		return
	if shake_kind != &"":
		for it: Array in items:
			var tint: Color = it[1]
			it[1] = Color(tint.g, tint.r / maxf(tint.g, 0.001) - 1.0, -100.0, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i: int in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	# Static props: no physics interpolation, so runtime custom-data writes (bump shake) stay legal.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if shake_kind != &"":
		for i: int in items.size():
			var xf: Transform3D = items[i][0]
			shakers.append({"multimesh": mm, "index": i, "pos": Vector2(xf.origin.x, xf.origin.z), "scale": xf.basis.get_scale().x, "custom": items[i][1], "kind": shake_kind})
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func _item(p: Vector2, scale: float, tint: Color, tilt: float = 0.0) -> Array:
	var y: float = Shape.ground_height(p)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	if tilt > 0.0:
		basis = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(-tilt, tilt)) * basis
	return [Transform3D(basis.scaled(Vector3.ONE * scale), Vector3(p.x, y, p.y)), tint]


func _tint(spread: float, hue_shift: float = 0.0) -> Color:
	var k: float = 1.0 + _rng.randf_range(-spread, spread)
	var h: float = _rng.randf_range(-hue_shift, hue_shift)
	return Color(k * (1.0 + h), k, k * (1.0 - h), -1.0)


func _random_island_point(min_margin: float) -> Vector2:
	for attempt: int in 40:
		var r: float = Tuning.ISLAND_HALF_SIZE * 1.05
		var p := Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
		if Shape.inside_margin(p) > min_margin:
			return p
	return Vector2.ZERO


func _clump(p: Vector2) -> float:
	var n: float = sin(p.x * 0.42 + 0.8) * sin(p.y * 0.37 - 1.1) + 0.6 * sin((p.x + p.y) * 0.21 + 2.0)
	return smoothstep(-0.55, 0.45, n)


func _front_factor(p: Vector2) -> float:
	return clampf((p.x + p.y) / (2.0 * Layout.HALF), 0.0, 1.0)


func _clear_zone(p: Vector2, pad: float) -> bool:
	if p.distance_to(Layout.LANDING_CENTER) < Layout.LANDING_RADIUS + maxf(pad, 0.0):
		return false
	if Shape.depression_depth(p) > 0.03 and pad > 0.2:
		return false
	if Layout.pond_sdf(p) < pad:
		return false
	if absf(p.x - Layout.BRIDGE_CENTER.x) < 1.4 + pad and p.y > Layout.HALF - 0.5:
		return false
	if _ground.blocked_at(p, pad) > 0:
		return false
	return true


func _spaced(p: Vector2, radius: float, layer: String) -> bool:
	var cell := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var key := "%s:%d:%d" % [layer, cell.x + dx, cell.y + dz]
			if not _hash.has(key):
				continue
			for q: Vector3 in _hash[key]:
				if p.distance_to(Vector2(q.x, q.y)) < (radius + q.z) * 0.5:
					return false
	var own := "%s:%d:%d" % [layer, cell.x, cell.y]
	if not _hash.has(own):
		_hash[own] = []
	_hash[own].append(Vector3(p.x, p.y, radius))
	return true


## Returns one item list per pine variant. Young pines lean toward the forest edge, tall ones toward the back.
func _place_trees(count: int) -> Array:
	var out: Array = []
	for v: int in Meshes.PINE_VARIANTS:
		out.append([])
	var placed: int = 0
	var tries: int = 0
	while placed < count and tries < count * 60:
		tries += 1
		var p: Vector2 = _random_island_point(0.9)
		var pd: float = Shape.playable_distance(p)
		var front: float = _front_factor(p)
		if pd < lerpf(0.5, 2.2, front):
			continue
		if _rng.randf() > smoothstep(0.2, 2.6, pd) * _clump(p):
			continue
		if not _clear_zone(p, 1.0):
			continue
		var depth_in: float = clampf((pd - 1.0) / 4.0, 0.0, 1.0)
		var back: float = clampf(-(p.x + p.y) / (2.0 * Layout.HALF), 0.0, 1.0)
		var variant: int = _pick_pine_variant(depth_in, back)
		var scale: float = _rng.randf_range(0.85, 1.2) * lerpf(0.8, 1.1, depth_in) * lerpf(1.0, 0.88, front * (1.0 - depth_in))
		var footprint: float = 1.75 if variant == 2 else (1.0 if variant == 3 else 1.4)
		if not _spaced(p, footprint * scale, "tree"):
			continue
		var it: Array = _item(p, scale, _tint(0.1, 0.07), 0.07)
		var xf: Transform3D = it[0]
		xf.basis = xf.basis * Basis.from_scale(Vector3(1, _rng.randf_range(0.9, 1.12), 1))
		it[0] = xf
		out[variant].append(it)
		tree_points.append(Vector3(p.x, p.y, scale))
		placed += 1
	return out


func _pick_pine_variant(depth_in: float, back: float) -> int:
	var w_young: float = lerpf(0.35, 0.08, depth_in)
	var w_full: float = 0.3
	var w_tall: float = lerpf(0.35, 0.7, maxf(depth_in, back))
	var roll: float = _rng.randf() * (w_young + w_full + w_tall)
	if roll < w_young:
		return 3
	if roll < w_young + w_full:
		return 2
	return 0 if _rng.randf() < 0.55 else 1


func _place_bushes() -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < Tuning.BUSH_COUNT and tries < Tuning.BUSH_COUNT * 40:
		tries += 1
		var p: Vector2 = _random_island_point(0.7)
		var pd: float = Shape.playable_distance(p)
		if pd < 0.2 and _rng.randf() > 0.08:
			continue
		if not _clear_zone(p, 0.5):
			continue
		if not _spaced(p, 0.9, "bush") or not _spaced(p, 0.9, "tree"):
			continue
		out.append(_item(p, _rng.randf_range(0.7, 1.25), _tint(0.1, 0.06)))
	return out


func _place_rocks() -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < Tuning.ROCK_COUNT and tries < Tuning.ROCK_COUNT * 40:
		tries += 1
		var p: Vector2 = _random_island_point(0.35)
		var near_edge: bool = Shape.inside_margin(p) < 2.2
		var pd: float = Shape.playable_distance(p)
		if not near_edge and pd < 0.5 and _rng.randf() > 0.15:
			continue
		if not _clear_zone(p, 0.4):
			continue
		if not _spaced(p, 0.7, "rock") or not _spaced(p, 0.6, "tree"):
			continue
		var scale: float = _rng.randf_range(0.6, 1.5) * (1.25 if near_edge else 1.0)
		if pd < 0.5:
			scale = minf(scale, 0.7)
		out.append(_item(p, scale, _tint(0.06), 0.25))
		rock_points.append(Vector3(p.x, p.y, scale))
	for lobe: Vector3 in Layout.POND_LOBES:
		for i: int in 5:
			var a: float = _rng.randf() * TAU
			var p := Vector2(lobe.x, lobe.y) + Vector2(cos(a), sin(a)) * (lobe.z + 0.15)
			if Layout.pond_sdf(p) > -0.05 and _clear_zone(p, -0.3) and absf(p.x - Layout.BRIDGE_CENTER.x) > 1.2:
				out.append(_item(p, _rng.randf_range(0.45, 0.8), _tint(0.05), 0.3))
	return out


func _place_pebbles() -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < Tuning.PEBBLE_COUNT and tries < Tuning.PEBBLE_COUNT * 30:
		tries += 1
		var p := Vector2(_rng.randf_range(-Layout.HALF - 4, Layout.HALF + 4), _rng.randf_range(-Layout.HALF - 4, Layout.HALF + 4))
		if Shape.inside_margin(p) < 0.4 or Layout.pond_sdf(p) < 0.1:
			continue
		var b: int = _ground.blocked_at(p, 0.0)
		if b == 2 or _ground.blocked_at(p, 0.25) == 2:
			continue
		if b == 0 and _ground.blocked_at(p, 0.6) != 1 and _rng.randf() > 0.2:
			continue
		out.append(_item(p, _rng.randf_range(0.14, 0.3), Color(1.05, 0.98, 0.88, 1), 0.4))
	return out


func _place_flowers() -> Array:
	var out: Array = []
	var palette: Array[Color] = [Color(1, 1, 1, 1), Color(1.0, 0.62, 0.78, 1), Color(1.0, 0.86, 0.35, 1), Color(0.78, 0.6, 1.0, 1), Color(1.0, 0.5, 0.42, 1)]
	var tries: int = 0
	while out.size() < _n(Tuning.FLOWER_COUNT) and tries < Tuning.FLOWER_COUNT * 20:
		tries += 1
		var center: Vector2 = _random_island_point(0.6)
		var pd: float = Shape.playable_distance(center)
		if pd < 0.0 and _rng.randf() > 0.35:
			continue
		var col: Color = palette[_rng.randi() % palette.size()].srgb_to_linear()
		col.a = -1.0
		var n: int = _rng.randi_range(3, 7)
		for i: int in n:
			var p: Vector2 = center + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
			if Shape.inside_margin(p) < 0.5 or not _clear_zone(p, 0.25):
				continue
			out.append(_item(p, _rng.randf_range(0.8, 1.3), col))
	return out


func _place_mushrooms() -> Array:
	var out: Array = []
	for t: Vector3 in tree_points:
		if out.size() >= Tuning.MUSHROOM_COUNT:
			break
		if _rng.randf() > 0.3:
			continue
		var a: float = _rng.randf() * TAU
		var p := Vector2(t.x, t.y) + Vector2(cos(a), sin(a)) * _rng.randf_range(0.45, 0.8) * t.z
		if Shape.inside_margin(p) < 0.4 or not _clear_zone(p, 0.1):
			continue
		for i: int in _rng.randi_range(1, 3):
			var q: Vector2 = p + Vector2(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.18, 0.18))
			out.append(_item(q, _rng.randf_range(0.7, 1.3), Color(1, 1, 1, 0), 0.2))
	return out


func _place_tufts() -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < _n(Tuning.GRASS_TUFT_COUNT) and tries < Tuning.GRASS_TUFT_COUNT * 6:
		tries += 1
		var p: Vector2 = _random_island_point(0.25)
		var pd: float = Shape.playable_distance(p)
		if pd < 0.0 and _rng.randf() > 0.3:
			continue
		if Layout.pond_sdf(p) < 0.15:
			continue
		if _ground.blocked_at(p, 0.12) > 0 and _rng.randf() > 0.03:
			continue
		out.append(_item(p, _rng.randf_range(0.7, 1.35), _tint(0.12, 0.08), 0.2))
	return out


func _place_lily_pads() -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < 14 and tries < 400:
		tries += 1
		var lobe: Vector3 = Layout.POND_LOBES[_rng.randi() % Layout.POND_LOBES.size()]
		var p := Vector2(lobe.x, lobe.y) + Vector2(_rng.randf_range(-lobe.z, lobe.z), _rng.randf_range(-lobe.z, lobe.z))
		if Layout.pond_sdf(p) > -0.45 or absf(p.x - Layout.BRIDGE_CENTER.x) < 1.0:
			continue
		if not _spaced(p, 0.7, "lily"):
			continue
		var it: Array = _item(p, _rng.randf_range(0.6, 1.0), _tint(0.08))
		var xf: Transform3D = it[0]
		xf.origin.y = Shape.POND_WATER_Y + 0.005
		it[0] = xf
		out.append(it)
	return out


func _place_reeds() -> Array:
	var out: Array = []
	for lobe: Vector3 in Layout.POND_LOBES:
		for i: int in 9:
			var a: float = _rng.randf() * TAU
			var p := Vector2(lobe.x, lobe.y) + Vector2(cos(a), sin(a)) * (lobe.z - 0.1)
			if Layout.pond_sdf(p) > 0.05 or absf(p.x - Layout.BRIDGE_CENTER.x) < 1.3:
				continue
			out.append(_item(p, _rng.randf_range(0.8, 1.3), _tint(0.1), 0.15))
	return out
