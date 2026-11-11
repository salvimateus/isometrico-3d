extends Node3D

## Gold mines and mana collectors fill over time, show a bouncing badge when ready and,
## on collect, burst 3D coins/drops that hand off to 2D icons flying into the HUD pills.

const Tuning := preload("res://scripts/tuning.gd")
const Kit := preload("res://scripts/world/mesh_kit.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")

const BUBBLE_ASPECT: float = 1.2
const ICON_BASE_PX: float = 46.0


class Collector:
	extends RefCounted
	var index: int = -1
	var kind: StringName = &"gold"
	var slot: Node3D
	var aabb: AABB
	var footprint: Vector2i = Vector2i.ONE
	var fill: float = 0.0
	var fill_time: float = 25.0
	var bubble: MeshInstance3D
	var pop: float = 0.0
	var fade: float = 1.0
	var shown: bool = false
	var hop_phase: float = 0.0
	var pop_tween: Tween
	var squash_tween: Tween


class Piece:
	extends RefCounted
	var kind: StringName = &"gold"
	var node: MeshInstance3D
	var flyer: Control
	var from: Vector3
	var to: Vector3
	var arc: float = 1.0
	var spin_axis: Vector3 = Vector3.UP
	var spin: float = 0.0
	var delay: float = 0.0
	var t: float = 0.0
	var flying: bool = false
	var screen_from: Vector2
	var bend: float = 1.0
	var fly_time: float = 0.6
	var start_scale: float = 1.0
	var share: int = 0
	var order: int = 0


var spawner: Object
var rig: Node3D
var hud: Hud
var player: Node3D

var _collectors: Array[Collector] = []
var _by_index: Dictionary = {}
var _pieces: Array[Piece] = []
var _free_nodes: Dictionary = {&"gold": [], &"mana": []}
var _free_flyers: Dictionary = {&"gold": [], &"mana": []}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _bubble_mats: Dictionary = {}
var _bubble_mesh: QuadMesh
var _fx_layer: CanvasLayer
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_spawner: Object, p_rig: Node3D, p_hud: CanvasLayer) -> void:
	spawner = p_spawner
	rig = p_rig
	hud = p_hud as Hud
	_rng.seed = 7331
	_build_assets()
	_fx_layer = CanvasLayer.new()
	_fx_layer.name = "CollectFx"
	_fx_layer.layer = Tuning.HUD_LAYER + 1
	add_child(_fx_layer)

	var buildings: Array = spawner.get(&"buildings")
	var first_seen: Dictionary = {}
	for i: int in buildings.size():
		var b: Dictionary = buildings[i]
		var resource: StringName = _resource_of(b["kind"])
		if resource == &"":
			continue
		var c := Collector.new()
		c.index = i
		c.kind = resource
		c.slot = b["slot"]
		c.aabb = b["aabb"]
		c.footprint = b["footprint"]
		c.fill_time = _rng.randf_range(Tuning.COLLECT_FILL_TIME_MIN, Tuning.COLLECT_FILL_TIME_MAX)
		c.hop_phase = _rng.randf() * TAU
		if not first_seen.has(resource):
			first_seen[resource] = true
			c.fill = Tuning.COLLECT_START_FULL_FILL
		else:
			c.fill = _rng.randf_range(0.05, 0.7)
		c.bubble = MeshInstance3D.new()
		c.bubble.name = "CollectBubble_%d" % i
		c.bubble.mesh = _bubble_mesh
		c.bubble.material_override = _bubble_mats[resource]
		c.bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.bubble.visible = false
		add_child(c.bubble)
		_collectors.append(c)
		_by_index[i] = c


func set_player(p_player: Node3D) -> void:
	player = p_player


func is_collector(index: int) -> bool:
	return _by_index.has(index)


func try_collect(index: int) -> bool:
	var c: Collector = _by_index.get(index)
	if c == null or c.fill < Tuning.COLLECT_MIN_FILL:
		return false
	_collect(c)
	return true


func _process(delta: float) -> void:
	_time += delta
	var occlude: float = 1.0 if rig != null and rig.has_method(&"is_shoulder") and bool(rig.call(&"is_shoulder")) else 0.0
	for mat: ShaderMaterial in _bubble_mats.values():
		mat.set_shader_parameter(&"occlude", occlude)
	for c: Collector in _collectors:
		c.fill = minf(c.fill + delta / c.fill_time, 1.0)
		if not c.shown and c.fill >= Tuning.COLLECT_BUBBLE_THRESHOLD:
			_show_bubble(c)
		if c.bubble.visible:
			_update_bubble(c)
		if c.shown and player != null and is_instance_valid(player) and _player_near(c):
			_collect(c)
	_update_pieces(delta)


func _show_bubble(c: Collector) -> void:
	c.shown = true
	c.fade = 1.0
	c.pop = 0.0
	c.bubble.visible = true
	if c.pop_tween != null:
		c.pop_tween.kill()
	c.pop_tween = create_tween()
	c.pop_tween.tween_property(c, "pop", 1.0, Tuning.COLLECT_BUBBLE_POP_IN_TIME).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.play(get_tree(), &"ui_pop", Tuning.COLLECT_SFX_VOLUME_DB - 8.0, _rng.randf_range(1.05, 1.2))


func _bubble_anchor(c: Collector) -> Vector3:
	var top := Vector3(c.aabb.get_center().x, c.aabb.end.y + Tuning.COLLECT_BUBBLE_HEIGHT, c.aabb.get_center().z)
	return c.slot.global_position + c.slot.global_basis.get_rotation_quaternion() * top


func _update_bubble(c: Collector) -> void:
	var s: float = Tuning.COLLECT_BUBBLE_SIZE
	var h: float = absf(sin(_time * Tuning.COLLECT_BUBBLE_HOP_SPEED + c.hop_phase))
	var squash: float = Tuning.COLLECT_BUBBLE_SQUASH * (1.0 - smoothstep(0.0, 0.35, h))
	var stretch: float = Tuning.COLLECT_BUBBLE_SQUASH * 0.35 * smoothstep(0.2, 0.7, h) * (1.0 - smoothstep(0.85, 1.0, h))
	var sx: float = 1.0 + squash - stretch
	var sy: float = 1.0 - squash + stretch
	if c.fill >= 1.0:
		var pulse: float = 1.0 + Tuning.COLLECT_BUBBLE_FULL_PULSE * (0.5 + 0.5 * sin(_time * 6.0 + c.hop_phase))
		sx *= pulse
		sy *= pulse
	var p: float = maxf(c.pop, 0.0)
	var pos: Vector3 = _bubble_anchor(c) + Vector3.UP * (h * Tuning.COLLECT_BUBBLE_HOP_HEIGHT - (1.0 - sy) * s * BUBBLE_ASPECT * 0.5)
	c.bubble.global_transform = Transform3D(Basis.from_scale(Vector3(sx * p, sy * p, 1.0) + Vector3(0.0001, 0.0001, 0.0)), pos)
	c.bubble.set_instance_shader_parameter(&"fill", c.fill)
	c.bubble.set_instance_shader_parameter(&"fade", c.fade)
	c.bubble.set_instance_shader_parameter(&"glow", 1.0 if c.fill >= 1.0 else 0.0)


func _player_near(c: Collector) -> bool:
	# Touch-collect only while walking: never mid-air, mounted on or launched by the catapult.
	if player is CharacterBody3D and not (player as CharacterBody3D).is_on_floor():
		return false
	if player.has_method(&"is_launched") and bool(player.call(&"is_launched")):
		return false
	if player.has_method(&"is_mounted") and bool(player.call(&"is_mounted")):
		return false
	var center: Vector3 = c.slot.global_position
	var pp: Vector3 = player.global_position
	var dx: float = maxf(absf(pp.x - center.x) - c.footprint.x * 0.5, 0.0)
	var dz: float = maxf(absf(pp.z - center.z) - c.footprint.y * 0.5, 0.0)
	return dx * dx + dz * dz <= Tuning.COLLECT_AUTO_RADIUS_TILES * Tuning.COLLECT_AUTO_RADIUS_TILES


func _collect(c: Collector) -> void:
	var ratio: float = clampf(c.fill, 0.0, 1.0)
	var capacity: int = Tuning.COLLECT_GOLD_CAPACITY if c.kind == &"gold" else Tuning.COLLECT_MANA_CAPACITY
	var amount: int = maxi(1, roundi(capacity * ratio))
	var max_pieces: int = Tuning.COLLECT_GOLD_PIECES if c.kind == &"gold" else Tuning.COLLECT_MANA_PIECES
	var count: int = clampi(roundi(max_pieces * ratio), 2, max_pieces)
	c.fill = 0.0
	var origin: Vector3 = c.bubble.global_position if c.bubble.visible else _bubble_anchor(c)
	_hide_bubble(c)
	_squash_building(c)
	Sfx.play(get_tree(), &"collect_whoosh", Tuning.COLLECT_SFX_VOLUME_DB, _rng.randf_range(0.95, 1.08))
	Sfx.play(get_tree(), &"ui_pop", Tuning.COLLECT_SFX_VOLUME_DB - 2.0, _rng.randf_range(0.9, 1.0))

	var base_share: int = amount / count
	for i: int in count:
		var piece := Piece.new()
		piece.kind = c.kind
		piece.order = i
		piece.share = base_share + (amount - base_share * count if i == count - 1 else 0)
		piece.node = _take_node(c.kind)
		var ang: float = TAU * (float(i) / count) + _rng.randf_range(-0.4, 0.4)
		var reach: float = Tuning.COLLECT_BURST_SPREAD * _rng.randf_range(0.45, 1.0)
		piece.from = origin
		piece.to = origin + Vector3(cos(ang) * reach, -_rng.randf_range(0.2, 0.9), sin(ang) * reach)
		piece.arc = Tuning.COLLECT_BURST_HEIGHT * _rng.randf_range(0.55, 1.0)
		piece.spin_axis = Vector3(_rng.randf_range(-0.3, 0.3), 1.0, _rng.randf_range(-0.3, 0.3)).normalized()
		piece.spin = _rng.randf_range(0.7, 1.3) * Tuning.COLLECT_BURST_SPIN * (1.0 if i % 2 == 0 else -1.0)
		piece.delay = i * Tuning.COLLECT_PIECE_STAGGER
		piece.bend = 1.0 if i % 2 == 0 else -1.0
		piece.fly_time = Tuning.COLLECT_FLY_TIME + _rng.randf_range(-1.0, 1.0) * Tuning.COLLECT_FLY_TIME_JITTER
		piece.node.global_position = origin
		piece.node.scale = Vector3.ONE * 0.001
		piece.node.visible = true
		_pieces.append(piece)


func _hide_bubble(c: Collector) -> void:
	c.shown = false
	if c.pop_tween != null:
		c.pop_tween.kill()
	c.pop_tween = create_tween()
	c.pop_tween.tween_property(c, "pop", 1.35, Tuning.COLLECT_BUBBLE_POP_OUT_TIME * 0.4).set_ease(Tween.EASE_OUT)
	c.pop_tween.parallel().tween_property(c, "fade", 0.0, Tuning.COLLECT_BUBBLE_POP_OUT_TIME)
	c.pop_tween.tween_callback(func() -> void:
		if not c.shown:
			c.bubble.visible = false)


func _squash_building(c: Collector) -> void:
	if c.squash_tween != null:
		c.squash_tween.kill()
	var t: float = Tuning.COLLECT_BUILDING_BOUNCE_TIME
	c.squash_tween = create_tween()
	c.squash_tween.tween_property(c.slot, "scale", Tuning.COLLECT_BUILDING_SQUASH, t * 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c.squash_tween.tween_property(c.slot, "scale", Vector3.ONE, t * 0.78).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _update_pieces(delta: float) -> void:
	if _pieces.is_empty():
		return
	var cam: Camera3D = rig.get(&"camera") if rig != null else null
	var i: int = _pieces.size() - 1
	while i >= 0:
		var p: Piece = _pieces[i]
		if _step_piece(p, delta, cam):
			_pieces.remove_at(i)
		i -= 1


## Returns true when the piece arrived and was released.
func _step_piece(p: Piece, delta: float, cam: Camera3D) -> bool:
	if p.delay > 0.0:
		p.delay -= delta
		return false
	p.t += delta
	if not p.flying:
		var u: float = clampf(p.t / Tuning.COLLECT_BURST_TIME, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - u, 2.2)
		var pos: Vector3 = p.from.lerp(p.to, e) + Vector3.UP * p.arc * 4.0 * e * (1.0 - e)
		p.node.global_position = pos
		var grow: float = Tuning.COLLECT_PIECE_SCALE * (1.0 + 0.25 * sin(minf(u * 3.0, 1.0) * PI))
		p.node.global_basis = Basis(p.spin_axis, p.t * p.spin).scaled(Vector3.ONE * maxf(grow * minf(u * 4.0, 1.0), 0.001))
		if u >= 1.0:
			if cam == null or hud == null or cam.is_position_behind(pos):
				_finish_piece(p)
				return true
			_to_flyer(p, cam, pos)
		return false
	var v: float = clampf(p.t / p.fly_time, 0.0, 1.0)
	var target: Vector2 = hud.pill_screen_position(p.kind)
	var dist: float = p.screen_from.distance_to(target)
	var dir: Vector2 = (target - p.screen_from) / maxf(dist, 1.0)
	var ctrl: Vector2 = (p.screen_from + target) * 0.5 + Vector2(-dir.y, dir.x) * dist * Tuning.COLLECT_FLY_CURVE * p.bend + Vector2(0.0, dist * 0.12)
	var k: float = v * v * (2.4 - 1.4 * v)
	var a: Vector2 = p.screen_from.lerp(ctrl, k)
	var b: Vector2 = ctrl.lerp(target, k)
	var at: Vector2 = a.lerp(b, k)
	var sc: float = lerpf(p.start_scale, Tuning.COLLECT_FLYER_END_SCALE, k) * (1.0 + 0.18 * sin(minf(v * 2.0, 1.0) * PI))
	p.flyer.position = at - p.flyer.size * 0.5
	p.flyer.scale = Vector2.ONE * sc
	p.flyer.rotation = sin(v * PI * 2.0) * 0.25 * p.bend
	if v >= 1.0:
		_finish_piece(p)
		return true
	return false


func _to_flyer(p: Piece, cam: Camera3D, pos: Vector3) -> void:
	p.flying = true
	p.t = 0.0
	var screen: Vector2 = cam.unproject_position(pos)
	var edge: Vector2 = cam.unproject_position(pos + cam.global_basis.x * 0.22 * Tuning.COLLECT_PIECE_SCALE)
	p.start_scale = clampf(screen.distance_to(edge) * 2.0 / (ICON_BASE_PX * 0.92), 0.25, 1.6)
	p.screen_from = screen
	_release_node(p)
	p.flyer = _take_flyer(p.kind)
	p.flyer.pivot_offset = p.flyer.size * 0.5
	p.flyer.position = screen - p.flyer.size * 0.5
	p.flyer.scale = Vector2.ONE * p.start_scale
	p.flyer.visible = true


func _finish_piece(p: Piece) -> void:
	_release_node(p)
	if p.flyer != null:
		p.flyer.visible = false
		_free_flyers[p.kind].append(p.flyer)
		p.flyer = null
	if hud != null:
		hud.add_resource(p.kind, p.share)
	var preset: StringName = &"coin_clink" if p.kind == &"gold" else &"mana_bloop"
	var pitch: float = 1.0 + _rng.randf_range(-1.0, 1.0) * Tuning.COLLECT_SFX_PITCH_JITTER + p.order * 0.02
	Sfx.play(get_tree(), preset, Tuning.COLLECT_SFX_VOLUME_DB, pitch)


func _release_node(p: Piece) -> void:
	if p.node != null:
		p.node.visible = false
		_free_nodes[p.kind].append(p.node)
		p.node = null


func _take_node(kind: StringName) -> MeshInstance3D:
	var pool: Array = _free_nodes[kind]
	if not pool.is_empty():
		return pool.pop_back()
	var n := MeshInstance3D.new()
	n.mesh = _meshes[kind]
	n.material_override = _materials[kind]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	return n


## Draws one coin and one drop for a frame at `hidden` (under the ground) and pre-builds a flyer of each,
## so the first collection does not compile pipelines or allocate nodes mid-play.
func warm_up(hidden: Vector3) -> void:
	var nodes: Array[MeshInstance3D] = []
	for kind: StringName in [&"gold", &"mana"]:
		var n: MeshInstance3D = _take_node(kind)
		n.global_position = hidden
		n.visible = true
		nodes.append(n)
		var f: Control = _take_flyer(kind)
		f.visible = false
		_free_flyers[kind].append(f)
	await get_tree().process_frame
	await get_tree().process_frame
	for i: int in nodes.size():
		nodes[i].visible = false
		_free_nodes[[&"gold", &"mana"][i]].append(nodes[i])


func _take_flyer(kind: StringName) -> Control:
	var pool: Array = _free_flyers[kind]
	if not pool.is_empty():
		return pool.pop_back()
	var f: Control = ResourceIcon.new(kind)
	f.size = Vector2(ICON_BASE_PX, ICON_BASE_PX)
	_fx_layer.add_child(f)
	return f


func _resource_of(building_kind: StringName) -> StringName:
	match building_kind:
		&"gold_mine":
			return &"gold"
		&"mana_collector":
			return &"mana"
	return &""


func _build_assets() -> void:
	_bubble_mesh = QuadMesh.new()
	_bubble_mesh.size = Vector2(Tuning.COLLECT_BUBBLE_SIZE, Tuning.COLLECT_BUBBLE_SIZE * BUBBLE_ASPECT)
	var shader: Shader = load("res://shaders/world/collect_bubble.gdshader")
	for kind: StringName in [&"gold", &"mana"]:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.render_priority = 8
		m.set_shader_parameter(&"kind", 0 if kind == &"gold" else 1)
		m.set_shader_parameter(&"accent", Tuning.GOLD_COLOR if kind == &"gold" else Tuning.MANA_COLOR)
		m.set_shader_parameter(&"accent_dark", Tuning.GOLD_COLOR_DARK if kind == &"gold" else Tuning.MANA_COLOR_DARK)
		m.set_shader_parameter(&"aspect", BUBBLE_ASPECT)
		_bubble_mats[kind] = m

	var coin := Kit.new()
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	coin.add(Kit.cylinder(0.22, 0.22, 0.07, 18), Transform3D(face, Vector3.ZERO), Tuning.GOLD_COLOR_DARK, Tuning.GOLD_COLOR_DARK)
	coin.add(Kit.cylinder(0.17, 0.17, 0.085, 18), Transform3D(face, Vector3.ZERO), Tuning.GOLD_COLOR, Color("FFE07A"))
	_meshes[&"gold"] = coin.commit()
	var gold_mat := StandardMaterial3D.new()
	gold_mat.vertex_color_use_as_albedo = true
	gold_mat.metallic = 0.35
	gold_mat.roughness = 0.3
	gold_mat.emission_enabled = true
	gold_mat.emission = Tuning.GOLD_COLOR
	gold_mat.emission_energy_multiplier = 0.25
	_materials[&"gold"] = gold_mat

	var drop := Kit.new()
	drop.add(Kit.sphere(0.17, 14, 8), Transform3D.IDENTITY, Tuning.MANA_COLOR_DARK, Tuning.MANA_COLOR)
	drop.add(Kit.cylinder(0.0, 0.158, 0.26, 14), Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0)), Tuning.MANA_COLOR, Color("E9A4F7"))
	_meshes[&"mana"] = drop.commit()
	var mana_mat := StandardMaterial3D.new()
	mana_mat.vertex_color_use_as_albedo = true
	mana_mat.roughness = 0.25
	mana_mat.emission_enabled = true
	mana_mat.emission = Tuning.MANA_COLOR
	mana_mat.emission_energy_multiplier = Tuning.COLLECT_MANA_EMISSION
	_materials[&"mana"] = mana_mat
