extends CanvasLayer

## Fullscreen post pass over the 3D view, below the HUD layer. F2 toggles it.

const Tuning := preload("res://scripts/tuning.gd")

var _rect: ColorRect


func _ready() -> void:
	layer = Tuning.POSTFX_LAYER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world/post_fx.gdshader")
	mat.set_shader_parameter("ca_strength", Tuning.POSTFX_CA_STRENGTH)
	mat.set_shader_parameter("ca_start", Tuning.POSTFX_CA_START)
	mat.set_shader_parameter("grain_strength", Tuning.POSTFX_GRAIN_STRENGTH)
	mat.set_shader_parameter("grain_size", Tuning.POSTFX_GRAIN_SIZE)
	mat.set_shader_parameter("grain_fps", Tuning.POSTFX_GRAIN_FPS)
	mat.set_shader_parameter("grain_highlight_keep", Tuning.POSTFX_GRAIN_HIGHLIGHT_KEEP)
	_rect.material = mat
	add_child(_rect)
	visible = Tuning.POSTFX_ENABLED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F2:
		visible = not visible
