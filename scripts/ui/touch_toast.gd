extends Control

## Short top-center toast in the HUD pill style (no blur): pops in with a springy scale, holds, fades out.

const SHOW_TIME: float = 2.4

var _panel: PanelContainer
var _title: Label
var _detail: Label
var _icon: Control
var _tween: Tween


func _init(font: Font) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.78)
	style.set_corner_radius_all(26)
	style.border_color = Color(1, 1, 1, 0.22)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 12
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_pad_icon)
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_title = _label(font, 20, Color.WHITE)
	col.add_child(_title)
	_detail = _label(font, 13, Color(1, 1, 1, 0.7))
	col.add_child(_detail)
	_panel.modulate.a = 0.0
	_panel.minimum_size_changed.connect(_place)


func show_toast(title: String, detail: String, connected: bool) -> void:
	_title.text = title
	_detail.text = detail
	_detail.visible = not detail.is_empty()
	_icon.set_meta(&"connected", connected)
	_icon.queue_redraw()
	_panel.reset_size()
	_place()
	if _tween != null:
		_tween.kill()
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE * 0.6
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.14)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(SHOW_TIME)
	_tween.chain().tween_property(_panel, "modulate:a", 0.0, 0.3)


func _place() -> void:
	var sz: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = sz
	_panel.pivot_offset = sz * 0.5
	_panel.position = Vector2((size.x - sz.x) * 0.5, 78.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_place()


func _label(font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw_pad_icon() -> void:
	# Original gamepad glyph: rounded body, d-pad cross, two face dots; a status dot in the corner.
	var c: Vector2 = _icon.size * 0.5
	var body := PackedVector2Array()
	for i: int in 33:
		var t: float = TAU * float(i) / 32.0
		var p := Vector2(cos(t) * 19.0, sin(t) * 11.0)
		if p.y > 0.0:
			p.y += absf(p.x) * 0.35
		body.append(c + p)
	_icon.draw_colored_polygon(body, Color(1, 1, 1, 0.95))
	_icon.draw_rect(Rect2(c + Vector2(-13, -1.5), Vector2(9, 3)), Color(0.08, 0.1, 0.18))
	_icon.draw_rect(Rect2(c + Vector2(-10, -4.5), Vector2(3, 9)), Color(0.08, 0.1, 0.18))
	_icon.draw_circle(c + Vector2(8, -2), 2.4, Color("FFC93C"), true, -1.0, true)
	_icon.draw_circle(c + Vector2(12, 2), 2.4, Color("D77CF0"), true, -1.0, true)
	var on: bool = bool(_icon.get_meta(&"connected", true))
	var dot: Vector2 = c + Vector2(16, -12)
	_icon.draw_circle(dot, 6.0, Color(0.08, 0.1, 0.18), true, -1.0, true)
	_icon.draw_circle(dot, 4.2, Color("7BE36A") if on else Color("FF6B5A"), true, -1.0, true)
