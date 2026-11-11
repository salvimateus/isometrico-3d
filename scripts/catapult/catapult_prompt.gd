extends Node3D

## Floating interaction bubble (HUD-style pill with tail and outlined text) that pops in, bobs and pops out.

const T := preload("res://scripts/catapult/catapult_tuning.gd")
const BillboardShader := preload("res://shaders/catapult/catapult_billboard.gdshader")
const Countdown := preload("res://scripts/catapult/catapult_countdown.gd")

var _pivot: Node3D
var _bubble: MeshInstance3D
var _mat: ShaderMaterial
var _label: Label3D
var _shown: bool = false
var _amount: float = 0.0
var _clock: float = 0.0
var _touch: bool = false


func _init() -> void:
	name = "CatapultPrompt"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pivot = Node3D.new()
	add_child(_pivot)
	_mat = ShaderMaterial.new()
	_mat.shader = BillboardShader
	_mat.set_shader_parameter(&"mode", 0)
	_mat.set_shader_parameter(&"size", T.PROMPT_SIZE)
	_mat.set_shader_parameter(&"fill_color", T.PROMPT_FILL)
	_mat.set_shader_parameter(&"border_color", T.PROMPT_BORDER)
	_mat.render_priority = 4
	var quad := QuadMesh.new()
	quad.size = T.PROMPT_SIZE
	_bubble = MeshInstance3D.new()
	_bubble.mesh = quad
	_bubble.material_override = _mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_bubble)

	_label = Label3D.new()
	_label.text = T.PROMPT_TEXT
	_label.font = Countdown.make_font()
	_label.font_size = T.PROMPT_FONT_SIZE
	_label.pixel_size = T.PROMPT_PIXEL_SIZE
	_label.outline_size = T.PROMPT_OUTLINE
	_label.outline_modulate = T.NUMBER_OUTLINE_COLOR
	_label.modulate = Color(T.LABEL_HDR_BOOST, T.LABEL_HDR_BOOST, T.LABEL_HDR_BOOST)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.double_sided = true
	_label.render_priority = 6
	_label.outline_render_priority = 5
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Bubble UV center is above the tail; lift the text to the pill's center.
	_label.position.y = T.PROMPT_SIZE.y * 0.11
	_pivot.add_child(_label)
	visible = false


## Touch shows a tapping hand instead of the gamepad/keyboard hint.
func set_touch(touch: bool) -> void:
	if touch == _touch:
		return
	_touch = touch
	if touch:
		var font := Countdown.make_font()
		font.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji"] + Array(font.font_names))
		_label.font = font
		_label.text = String.chr(T.PROMPT_TOUCH_GLYPH) if font.has_char(T.PROMPT_TOUCH_GLYPH) else T.PROMPT_TOUCH_FALLBACK
		_label.font_size = T.PROMPT_TOUCH_FONT_SIZE
	else:
		_label.font = Countdown.make_font()
		_label.text = T.PROMPT_TEXT
		_label.font_size = T.PROMPT_FONT_SIZE


func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	if shown:
		visible = true


func is_shown() -> bool:
	return _shown


func _process(delta: float) -> void:
	_clock += delta
	var rate: float = 1.0 / (T.PROMPT_POP_IN if _shown else T.PROMPT_POP_OUT)
	_amount = move_toward(_amount, 1.0 if _shown else 0.0, delta * rate)
	if _amount <= 0.0 and not _shown:
		visible = false
		return
	var s: float = _ease_out_back(_amount) if _shown else _amount * _amount
	var bob: float = sin(_clock * T.PROMPT_BOB_FREQ * TAU * 0.5)
	var breathe: float = 1.0 + 0.04 * sin(_clock * T.PROMPT_BOB_FREQ * TAU * 0.5 + 1.2)
	_pivot.position.y = bob * T.PROMPT_BOB_HEIGHT
	_pivot.scale = Vector3(s * breathe, s * (2.0 - breathe), s).max(Vector3.ONE * 0.001)
	_mat.set_shader_parameter(&"opacity", clampf(_amount * 1.5, 0.0, 1.0))
	_label.modulate.a = clampf(_amount * 1.5, 0.0, 1.0)


static func _ease_out_back(t: float) -> float:
	var c1: float = 2.4
	var c3: float = c1 + 1.0
	var u: float = t - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u
