extends Node3D

## Billboard countdown: chunky outlined Label3D that pops in with an elastic wobble and a radial burst behind it.

const T := preload("res://scripts/catapult/catapult_tuning.gd")
const BillboardShader := preload("res://shaders/catapult/catapult_billboard.gdshader")

var _label: Label3D
var _burst: MeshInstance3D
var _burst_mat: ShaderMaterial
var _age: float = 0.0
var _burst_age: float = 99.0
var _base_scale: float = 1.0
var _leaving: float = -1.0
var _color := Color.WHITE


func _init() -> void:
	name = "CatapultCountdown"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_burst_mat = ShaderMaterial.new()
	_burst_mat.shader = BillboardShader
	_burst_mat.set_shader_parameter(&"mode", 1)
	_burst_mat.set_shader_parameter(&"size", Vector2(T.BURST_SIZE, T.BURST_SIZE))
	_burst_mat.render_priority = 1
	var quad := QuadMesh.new()
	quad.size = Vector2(T.BURST_SIZE, T.BURST_SIZE)
	_burst = MeshInstance3D.new()
	_burst.mesh = quad
	_burst.material_override = _burst_mat
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visible = false
	add_child(_burst)

	_label = Label3D.new()
	_label.font = make_font()
	_label.font_size = T.NUMBER_FONT_SIZE
	_label.pixel_size = T.NUMBER_PIXEL_SIZE
	_label.outline_size = T.NUMBER_OUTLINE
	_label.outline_modulate = T.NUMBER_OUTLINE_COLOR
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.double_sided = true
	_label.render_priority = 3
	_label.outline_render_priority = 2
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.visible = false
	add_child(_label)
	set_process(false)


## Shared HUD font: the same chunky system face the HUD uses.
static func make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Segoe UI", "Arial"])
	f.font_weight = 900
	return f


# Godot re-enables processing on ready when _process exists; stay idle until used.
func _ready() -> void:
	set_process(false)


func show_step(text: String, color: Color, scale_mult: float = 1.0) -> void:
	_label.text = text
	_color = Color(color.r * T.LABEL_HDR_BOOST, color.g * T.LABEL_HDR_BOOST, color.b * T.LABEL_HDR_BOOST, 1.0)
	_label.modulate = _color
	_label.visible = true
	_base_scale = scale_mult
	_age = 0.0
	_leaving = -1.0
	_burst_age = 0.0
	_burst.visible = true
	_burst_mat.set_shader_parameter(&"accent_color", Color(color, 0.95))
	_apply()
	set_process(true)


## Draws the label and burst fully transparent for a few frames so their shaders compile at load.
func prewarm(frames: int) -> void:
	_label.text = "3"
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_label.visible = true
	_burst.visible = true
	_burst_mat.set_shader_parameter(&"opacity", 0.0)
	for i: int in frames:
		await get_tree().process_frame
	_burst_mat.set_shader_parameter(&"opacity", 1.0)
	if not is_processing():
		_label.visible = false
		_burst.visible = false


## Squeezes the current label away.
func leave() -> void:
	if _label.visible and _leaving < 0.0:
		_leaving = 0.0


func is_showing() -> bool:
	return _label.visible


func _process(delta: float) -> void:
	_age += delta
	_burst_age += delta
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving >= T.SQUEEZE_OUT_TIME:
			_label.visible = false
	if _burst_age >= T.BURST_TIME:
		_burst.visible = false
	_apply()
	if not _label.visible and not _burst.visible:
		set_process(false)


func _apply() -> void:
	var wobble: float = exp(-T.POP_DECAY * _age) * cos(T.POP_FREQ * _age)
	var s: float = _base_scale * (1.0 + (T.POP_FROM - 1.0) * wobble)
	var squash := Vector3(s * (1.0 - 0.18 * wobble), s * (1.0 + 0.18 * wobble), s)
	if _leaving >= 0.0:
		var k: float = clampf(_leaving / T.SQUEEZE_OUT_TIME, 0.0, 1.0)
		squash = Vector3(s * (1.0 + 0.6 * k), s * (1.0 - k), s)
		_label.modulate = Color(_color, 1.0 - k)
	else:
		_label.modulate = _color
	_label.scale = squash.max(Vector3.ONE * 0.001)
	var bp: float = clampf(_burst_age / T.BURST_TIME, 0.0, 1.0)
	_burst_mat.set_shader_parameter(&"progress", bp)
	_burst.scale = Vector3.ONE * _base_scale
