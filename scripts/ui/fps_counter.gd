extends PanelContainer

## Small HUD pill with averaged FPS and frame time, refreshed a few times per second.

const Tuning := preload("res://scripts/tuning.gd")

const GOOD := Color("7BE36A")
const OK := Color("FFD54A")
const BAD := Color("FF6B5A")

signal tapped

var _label: RichTextLabel
var _accum: float = 0.0
var _frames: int = 0


func _init(font: Font) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.62)
	style.set_corner_radius_all(16)
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", style)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("normal_font", font)
	_label.add_theme_font_size_override("normal_font_size", 16)
	_label.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))
	_label.text = "-- FPS"
	add_child(_label)


func _on_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		tapped.emit()
		accept_event()


func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	if _accum < Tuning.FPS_REFRESH_INTERVAL:
		return
	var ms: float = _accum / _frames * 1000.0
	var fps: float = _frames / _accum
	_accum = 0.0
	_frames = 0
	var col: Color = GOOD if fps >= 60.0 else (OK if fps >= 30.0 else BAD)
	_label.text = "[color=#%s]%d FPS[/color]  ·  %.1f ms" % [col.to_html(false), roundi(fps), ms]
