extends PanelContainer

## Compact translucent performance panel (opened from the FPS pill): live CPU/GPU ms, draw calls,
## primitives, device + GPU name, and big cycling toggles bound to the perf settings node.

const Tuning := preload("res://scripts/tuning.gd")

var settings: Node
var _stats: Label
var _buttons: Dictionary = {}
var _accum: float = 0.0

# key, label, choices (Array) and how to show each value
const TOGGLES: Array = [
	["postfx", "Pós (aberração/grão)", [true, false]],
	["dof", "DOF", [true, false]],
	["glow", "Glow", [true, false]],
	["shadows", "Sombras", [0, 1024, 2048]],
	["msaa", "MSAA", [0, 2]],
	["scale", "Escala 3D", [0.0, 0.5, 0.6, 0.75, 1.0]],
	["fog", "Névoa", [true, false]],
	["clouds", "Nuvens", [true, false]],
	["night_lights", "Luzes noturnas", [true, false]],
	["water", "Água (simulação)", [true, false]],
	["foliage", "Vegetação", [0.25, 0.5, 1.0]],
	["fps_cap", "Limite FPS", [30, 60]],
]


func setup(p_settings: Node, font: Font) -> void:
	settings = p_settings
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.15, 0.82)
	style.set_corner_radius_all(18)
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var device := Label.new()
	device.text = "%s  ·  %s" % [OS.get_model_name(), RenderingServer.get_video_adapter_name()]
	_style_label(device, font, 14, Color(1, 1, 1, 0.7))
	col.add_child(device)
	_stats = Label.new()
	_style_label(_stats, font, 17, Color.WHITE)
	col.add_child(_stats)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for t: Array in TOGGLES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(196, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 15)
		for state: String in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.1 if state == "normal" else 0.2)
			sb.set_corner_radius_all(12)
			sb.border_color = Color(1, 1, 1, 0.22)
			sb.set_border_width_all(1)
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_cycle.bind(t))
		grid.add_child(b)
		_buttons[t[0]] = b
	var close := Button.new()
	close.text = "Fechar"
	close.custom_minimum_size = Vector2(0, 48)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_override("font", font)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	settings.connect(&"changed", _refresh_labels)
	_refresh_labels()


func _style_label(l: Label, font: Font, size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _cycle(t: Array) -> void:
	var choices: Array = t[2]
	var current: Variant = settings.get(&"values")[t[0]]
	var i: int = 0
	for k: int in choices.size():
		if is_equal_approx(float(choices[k]), float(current)):
			i = k
	settings.call(&"set_value", t[0], choices[(i + 1) % choices.size()])


func _fmt(key: String, v: Variant) -> String:
	match key:
		"shadows":
			return "desligado" if int(v) == 0 else str(int(v))
		"msaa":
			return "desligado" if int(v) == 0 else "%dx" % int(v)
		"scale":
			return "auto (%.2f)" % float(settings.call(&"current_scale")) if float(v) <= 0.0 else "%.2f" % float(v)
		"foliage":
			return "%d%%" % int(round(float(v) * 100.0))
		"fps_cap":
			return "sem limite" if int(v) == 0 else str(int(v))
	return "ligado" if bool(v) else "desligado"


func _refresh_labels() -> void:
	var vals: Dictionary = settings.get(&"values")
	for t: Array in TOGGLES:
		(_buttons[t[0]] as Button).text = "%s\n%s" % [t[1], _fmt(t[0], vals[t[0]])]


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < Tuning.FPS_REFRESH_INTERVAL:
		return
	_accum = 0.0
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_stats.text = "CPU %.1f ms  ·  GPU %.1f ms  ·  %d draws  ·  %dk tris  ·  3D %.2f" % [
		float(settings.call(&"cpu_ms")), float(settings.call(&"gpu_ms")), draws, prims / 1000, float(settings.call(&"current_scale"))]
	if _buttons.has("scale"):
		_refresh_labels()
