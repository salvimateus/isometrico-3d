extends Node

## Autoload: switches to fullscreen at boot unless a window size or a screenshot is requested
## on the command line, toggles fullscreen with F11 / Alt+Enter, and logs the resulting display state.

const WINDOWED_SIZE := Vector2i(1600, 900)
const Tuning := preload("res://scripts/tuning.gd")

var _back_time: float = -100.0
var _toast_layer: CanvasLayer


func _ready() -> void:
	# The project boots windowed at its base size so `--resolution WxH` keeps working (the engine hides that
	# arg from scripts). A window of any other size means a size was requested: stay windowed then.
	# Otherwise go fullscreen here, before the first frame is drawn, unless a screenshot run asked for a window.
	var boot_size: Vector2i = DisplayServer.window_get_size()
	var requested_size: bool = boot_size != _project_size()
	var shot: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = true
	if not requested_size and not shot and not OS.has_feature("mobile"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame
	await get_tree().process_frame
	_log_state()


func _project_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", WINDOWED_SIZE.x)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", WINDOWED_SIZE.y)))


func _parse_size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.to_lower().split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(parts[0].to_int(), parts[1].to_int())
	return WINDOWED_SIZE


func _set_windowed(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var screen: int = DisplayServer.window_get_current_screen()
	var origin: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(origin + (screen_size - size) / 2)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			_set_windowed(WINDOWED_SIZE)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
		_log_state.call_deferred()


func _log_state() -> void:
	var names: Dictionary = {
		DisplayServer.WINDOW_MODE_WINDOWED: "windowed",
		DisplayServer.WINDOW_MODE_MINIMIZED: "minimized",
		DisplayServer.WINDOW_MODE_MAXIMIZED: "maximized",
		DisplayServer.WINDOW_MODE_FULLSCREEN: "fullscreen",
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: "exclusive_fullscreen",
	}
	var size: Vector2i = DisplayServer.window_get_size()
	var screen: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	print("[Display] mode=%s size=%dx%d screen=%dx%d" % [names.get(DisplayServer.window_get_mode(), "?"), size.x, size.y, screen.x, screen.y])


## Android back (and gamepads that send KEYCODE_BACK as B): ignored once with a hint, quits on a second press.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _back_time <= Tuning.BACK_DOUBLE_PRESS_WINDOW:
		get_tree().quit()
		return
	_back_time = now
	_show_toast.call_deferred("Toque voltar de novo para sair")


func _show_toast(text: String) -> void:
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = Tuning.HUD_LAYER + 2
		add_child(_toast_layer)
	for c: Node in _toast_layer.get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.78)
	style.set_corner_radius_all(22)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(2)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 10
	style.content_margin_bottom = 11
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial"])
	font.font_weight = 900
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 20)
	panel.add_child(label)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -120
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(panel)
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(Tuning.BACK_DOUBLE_PRESS_WINDOW - 0.4)
	tw.tween_property(panel, "modulate:a", 0.0, 0.25)
	tw.tween_callback(panel.queue_free)
