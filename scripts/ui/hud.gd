extends CanvasLayer

## Minimal HUD: resource pills (top right) and a discreet controls hint (bottom left).
## Pills react to income: rolling number, pop, icon glow and bar fill tween.

const ResourceIcon := preload("res://scripts/ui/resource_icon.gd")
const FpsCounter := preload("res://scripts/ui/fps_counter.gd")
const Tuning := preload("res://scripts/tuning.gd")

const HINT_TEXT: String = "WASD andar  ·  Shift correr  ·  Espaço pular  ·  E interagir  ·  ↑↓ zoom  ·  → câmera  ·  ← dia/noite  ·  Arrastar mover  ·  Clique: selecionar, catapulta, botão d'água  ·  F2 efeitos  ·  F3 névoa  ·  F11 tela cheia
Controle: analóg. esq. andar  ·  A pular  ·  X interagir  ·  RB correr  ·  D-pad ↑↓ zoom  ·  D-pad → câmera  ·  D-pad ← dia/noite"


class Pill:
	extends RefCounted
	var holder: Control
	var panel: PanelContainer
	var icon: Control
	var label: Label
	var bar: ProgressBar
	var cap: float = 1.0
	var target: int = 0
	var shown: float = 0.0
	var number_tween: Tween
	var pop_tween: Tween
	var glow_tween: Tween
	var bar_tween: Tween
	var icon_pop: float = 1.0
	var shine_clock: float = 0.0


const HINT_TOUCH_TEXT: String = "Arraste à esquerda: andar (borda: correr)  ·  Pinça: zoom  ·  Toque: selecionar"

var _font: SystemFont
var fps_pill: PanelContainer
var _hint: PanelContainer
var _hint_label: Label
var _hint_mode: StringName = &"desktop"
var _pills: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	layer = Tuning.HUD_LAYER
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial"])
	_font.font_weight = 900
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var pills := VBoxContainer.new()
	pills.add_theme_constant_override("separation", 12)
	pills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pills.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pills.offset_left = -330
	pills.offset_right = -26
	pills.offset_top = 24
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pills)
	pills.add_child(_pill(&"gold", Tuning.HUD_GOLD_START, Tuning.HUD_GOLD_CAP, Color("FFC93C"), Color("E59A12")))
	pills.add_child(_pill(&"mana", Tuning.HUD_MANA_START, Tuning.HUD_MANA_CAP, Color("D77CF0"), Color("A23CC6")))

	var hint := PanelContainer.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 22
	hint.offset_bottom = -20
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.07, 0.09, 0.16, 0.42)
	hint_style.set_corner_radius_all(16)
	hint_style.content_margin_left = 16
	hint_style.content_margin_right = 16
	hint_style.content_margin_top = 8
	hint_style.content_margin_bottom = 9
	hint.add_theme_stylebox_override("panel", hint_style)
	var hint_label := Label.new()
	hint_label.text = HINT_TEXT
	hint_label.add_theme_constant_override("line_spacing", 2)
	hint_label.add_theme_font_override("font", _font)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	hint.add_child(hint_label)
	root.add_child(hint)
	_hint = hint
	_hint_label = hint_label
	if _hint_mode != &"desktop":
		set_hint_mode(_hint_mode)

	var fps: PanelContainer = FpsCounter.new(_font)
	fps_pill = fps
	fps.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps.offset_left = 22
	fps.offset_top = 20
	root.add_child(fps)


func _process(delta: float) -> void:
	_time += delta
	var i: int = 0
	for kind: StringName in _pills:
		var p: Pill = _pills[kind]
		var breath: float = 1.0 + Tuning.HUD_BREATH_AMPLITUDE * sin(_time * Tuning.HUD_BREATH_SPEED * TAU * 0.5 + float(i) * 1.7)
		p.icon.pivot_offset = p.icon.size * 0.5
		p.icon.scale = Vector2.ONE * breath * p.icon_pop
		p.shine_clock += delta
		var period: float = Tuning.HUD_SHINE_PERIOD
		var local: float = fmod(p.shine_clock + float(i) * period * 0.5, period)
		p.icon.set(&"shine", local / Tuning.HUD_SHINE_TIME if local < Tuning.HUD_SHINE_TIME else -1.0)
		i += 1


## Swaps the controls hint for the short touch version (top center, clear of the thumb controls).
func set_touch_mode(on: bool) -> void:
	set_hint_mode(&"touch" if on else &"desktop")


## Hint variant: &"desktop" (keyboard + pad, bottom left), &"pad" (pad only, bottom left), &"touch" (top center).
func set_hint_mode(mode: StringName) -> void:
	_hint_mode = mode
	if _hint == null:
		return
	match mode:
		&"touch":
			_hint_label.text = HINT_TOUCH_TEXT
		&"pad":
			_hint_label.text = HINT_TEXT.get_slice("\n", 1)
		_:
			_hint_label.text = HINT_TEXT
	_hint.size = Vector2.ZERO
	if mode == &"touch":
		_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_hint.grow_vertical = Control.GROW_DIRECTION_END
		_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	else:
		_hint.grow_horizontal = Control.GROW_DIRECTION_END
		_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 0)
		_hint.offset_left = 22
		_hint.offset_bottom = -20
		_hint.offset_top = _hint.offset_bottom - _hint.get_combined_minimum_size().y


## Center of the pill icon in viewport pixels.
func pill_screen_position(kind: StringName) -> Vector2:
	var p: Pill = _pills.get(kind)
	if p == null:
		return Vector2.ZERO
	var rect: Rect2 = p.icon.get_global_rect()
	return rect.position + p.icon.size * 0.5 * p.panel.scale


func add_resource(kind: StringName, amount: int) -> void:
	var p: Pill = _pills.get(kind)
	if p == null:
		return
	p.target += amount
	if p.number_tween != null:
		p.number_tween.kill()
	p.number_tween = create_tween()
	p.number_tween.tween_method(_set_shown.bind(p), p.shown, float(p.target), Tuning.HUD_ROLL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if p.bar_tween != null:
		p.bar_tween.kill()
	p.bar_tween = create_tween()
	p.bar_tween.tween_property(p.bar, "value", clampf(float(p.target) / p.cap, 0.0, 1.0), Tuning.HUD_BAR_TWEEN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	pop_pill(kind)


func pop_pill(kind: StringName) -> void:
	var p: Pill = _pills.get(kind)
	if p == null:
		return
	p.panel.pivot_offset = p.panel.size * 0.5
	if p.pop_tween != null:
		p.pop_tween.kill()
	p.pop_tween = create_tween().set_parallel(true)
	p.panel.scale = Vector2.ONE * Tuning.HUD_POP_SCALE
	p.pop_tween.tween_property(p.panel, "scale", Vector2.ONE, Tuning.HUD_POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	p.icon_pop = Tuning.HUD_ICON_POP_SCALE
	p.pop_tween.tween_property(p, "icon_pop", 1.0, Tuning.HUD_POP_TIME * 1.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if p.glow_tween != null:
		p.glow_tween.kill()
	p.icon.set(&"flash", 1.0)
	p.glow_tween = create_tween()
	p.glow_tween.tween_property(p.icon, "flash", 0.0, Tuning.HUD_GLOW_TIME).set_ease(Tween.EASE_OUT)


static func format_amount(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "." + out
		out = digits[i] + out
		count += 1
	return ("-" if value < 0 else "") + out


func _set_shown(value: float, p: Pill) -> void:
	p.shown = value
	p.label.text = format_amount(roundi(value))


func _pill(kind: StringName, amount: int, cap: int, bar_light: Color, bar_dark: Color) -> Control:
	var p := Pill.new()
	p.cap = float(maxi(cap, 1))
	p.target = amount
	p.shown = float(amount)
	_pills[kind] = p

	# Plain holder so the panel can scale freely; containers reset child scale on sort.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.holder = holder

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.62)
	style.set_corner_radius_all(26)
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 8
	style.content_margin_right = 20
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)
	p.panel = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon: Control = ResourceIcon.new(kind)
	row.add_child(icon)
	p.icon = icon

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var label := Label.new()
	label.text = format_amount(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.12, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	col.add_child(label)
	p.label = label

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(float(amount) / p.cap, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 9)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = bar_light
	fg.set_corner_radius_all(5)
	fg.border_color = bar_dark
	fg.border_width_bottom = 3
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	col.add_child(bar)
	p.bar = bar

	var sync := func() -> void: holder.custom_minimum_size = Vector2(0.0, panel.get_combined_minimum_size().y)
	panel.minimum_size_changed.connect(sync)
	sync.call()
	return holder


## Opens the perf panel when the FPS pill is tapped (settings: the perf_settings node).
func attach_perf_panel(settings: Node) -> void:
	var panel: PanelContainer = preload("res://scripts/ui/perf_panel.gd").new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 22
	panel.offset_top = 64
	fps_pill.get_parent().add_child(panel)
	panel.call(&"setup", settings, _font)
	fps_pill.connect(&"tapped", func() -> void: panel.visible = not panel.visible)
