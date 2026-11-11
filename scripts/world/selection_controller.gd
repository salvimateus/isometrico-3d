extends Node3D

## Hover highlight, click selection with squash-and-stretch, footprint ring and floating name.

const Tuning := preload("res://scripts/tuning.gd")
const Spawner := preload("res://scripts/world/building_spawner.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")

var spawner: Spawner
var rig: Node3D
## Optional resource_collectors node; clicks on a ready collector collect instead of selecting.
var collectors: Node = null
## building index -> controller with try_mount() (catapults).
var mount_targets: Dictionary = {}
## building index -> Callable run on click instead of selecting (e.g. the water tower button).
var click_actions: Dictionary = {}

var _hover_index: int = -1
var _selected_index: int = -1
var _hover_mat: ShaderMaterial
var _select_mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _label: Label3D
var _label_base_y: float = 0.0
var _bounce: Tween
var _hover_tween: Tween
var _ring_tween: Tween
var _time: float = 0.0


func setup(p_spawner: Spawner, p_rig: Node3D) -> void:
	spawner = p_spawner
	rig = p_rig
	var shader: Shader = load("res://shaders/world/highlight.gdshader")
	_hover_mat = ShaderMaterial.new()
	_hover_mat.shader = shader
	_hover_mat.set_shader_parameter("strength", Tuning.HOVER_RIM_STRENGTH)
	_hover_mat.set_shader_parameter("fill", Tuning.HOVER_FILL)
	_hover_mat.set_shader_parameter("rim_power", Tuning.HIGHLIGHT_RIM_POWER)
	_select_mat = ShaderMaterial.new()
	_select_mat.shader = shader
	_select_mat.set_shader_parameter("strength", Tuning.SELECT_RIM_STRENGTH)
	_select_mat.set_shader_parameter("fill", Tuning.SELECT_FILL)
	_select_mat.set_shader_parameter("rim_power", Tuning.HIGHLIGHT_RIM_POWER)
	_select_mat.set_shader_parameter("pulse", Tuning.SELECT_PULSE)

	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://shaders/world/footprint_ring.gdshader")
	_ring = MeshInstance3D.new()
	_ring.name = "FootprintRing"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_ring.mesh = quad
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 30
	_label.outline_size = 12
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0.12, 0.09, 0.2, 0.95)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial"])
	font.font_weight = 900
	_label.font = font
	_label.render_priority = 10
	_label.outline_render_priority = 9
	_label.visible = false
	add_child(_label)

	rig.connect(&"clicked", _on_clicked)


func _pick(screen_pos: Vector2) -> int:
	var cam: Camera3D = rig.get(&"camera")
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to, Spawner.PICK_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var collider: Object = hit["collider"]
	return int(collider.get_meta("building_index", -1))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover(_pick((event as InputEventMouseMotion).position))


func _on_clicked(screen_pos: Vector2) -> void:
	var index: int = _pick(screen_pos)
	if index >= 0 and collectors != null and bool(collectors.call(&"try_collect", index)):
		return
	if click_actions.has(index):
		(click_actions[index] as Callable).call()
		_play_bounce(index)
		return
	if mount_targets.has(index):
		(mount_targets[index] as Object).call(&"try_mount")
	select(index)


func select(index: int) -> void:
	if index == _selected_index:
		if index >= 0:
			_play_bounce(index)
		return
	var previous: int = _selected_index
	_selected_index = index
	if previous >= 0:
		_apply_overlay(previous, _hover_mat if previous == _hover_index else null)
	if index < 0:
		_hide_ring()
		_label.visible = false
		return
	_apply_overlay(index, _select_mat)
	_play_bounce(index)
	_show_ring(index)
	_show_label(index)
	var b: Dictionary = spawner.buildings[index]
	var fx: Node = get_tree().get_first_node_in_group(&"world_fx")
	if fx != null:
		var fp: Vector2i = b["footprint"]
		fx.call(&"sparks", (b["slot"] as Node3D).global_position + Vector3(0, 0.3, 0), minf(fp.x, fp.y) * 0.5)
	Sfx.play(get_tree(), &"ui_select", -4.0, randf_range(0.97, 1.05))


func select_first_of_kind(kind: StringName) -> void:
	for i: int in spawner.buildings.size():
		if spawner.buildings[i]["kind"] == kind:
			select(i)
			return


func _set_hover(index: int) -> void:
	if index == _hover_index:
		return
	var previous: int = _hover_index
	_hover_index = index
	if previous >= 0 and previous != _selected_index:
		_apply_overlay(previous, null)
	if index >= 0 and index != _selected_index:
		_apply_overlay(index, _hover_mat)
	if index >= 0:
		_play_hover_pop(index)
		Sfx.play(get_tree(), &"ui_tick", -12.0, randf_range(1.0, 1.15))
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if index >= 0 else Input.CURSOR_ARROW)


func _apply_overlay(index: int, mat: Material) -> void:
	_overlay_recursive(spawner.buildings[index]["model"], mat)


func _overlay_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		(node as GeometryInstance3D).material_overlay = mat
	for child: Node in node.get_children():
		_overlay_recursive(child, mat)


func _play_bounce(index: int) -> void:
	var slot: Node3D = spawner.buildings[index]["slot"]
	if _bounce and _bounce.is_valid():
		_bounce.kill()
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	for b: Dictionary in spawner.buildings:
		(b["slot"] as Node3D).scale = Vector3.ONE
	var t: float = Tuning.BOUNCE_TIME
	_bounce = create_tween()
	_bounce.tween_property(slot, "scale", Tuning.BOUNCE_SQUASH, t * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bounce.tween_property(slot, "scale", Tuning.BOUNCE_STRETCH, t * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bounce.tween_property(slot, "scale", Vector3.ONE, t * 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _play_hover_pop(index: int) -> void:
	if _bounce and _bounce.is_running():
		return
	var slot: Node3D = spawner.buildings[index]["slot"]
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(slot, "scale", Vector3.ONE * Tuning.HOVER_POP_SCALE, Tuning.HOVER_POP_TIME * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(slot, "scale", Vector3.ONE, Tuning.HOVER_POP_TIME * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _show_ring(index: int) -> void:
	var b: Dictionary = spawner.buildings[index]
	var fp: Vector2i = b["footprint"]
	var size := Vector2(fp.x + 0.5, fp.y + 0.5)
	_ring.scale = Vector3(size.x, 1, size.y)
	_ring.position = (b["slot"] as Node3D).position + Vector3(0, 0.035, 0)
	_ring_mat.set_shader_parameter("size", size)
	_ring.visible = true
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring_mat.set_shader_parameter("appear", 0.0)
	_ring_tween = create_tween()
	_ring_tween.tween_method(func(v: float) -> void: _ring_mat.set_shader_parameter("appear", v), 0.0, 1.0, 0.2)


func _hide_ring() -> void:
	_ring.visible = false


func _show_label(index: int) -> void:
	var b: Dictionary = spawner.buildings[index]
	var aabb: AABB = b["aabb"]
	_label.text = b["name"]
	_label_base_y = aabb.end.y * Tuning.LABEL_HEIGHT_FACTOR + Tuning.LABEL_HEIGHT_OFFSET
	_label.position = (b["slot"] as Node3D).position + Vector3(0, _label_base_y, 0)
	_label.visible = true


func _process(delta: float) -> void:
	_time += delta
	if _label.visible:
		_label.position.y = _label_base_y + sin(_time * 2.4) * Tuning.LABEL_FLOAT_AMPLITUDE
