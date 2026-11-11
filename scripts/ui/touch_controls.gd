extends CanvasLayer

## Brawl-Stars-style touch controls: dynamic move stick (left), big jump button and interact "super" button
## (bottom right), small camera / day-night / shoulder-swap gadgets. Every finger stays bound to the control
## it started on; free fingers on the right tap (select), orbit (shoulder) or pinch (zoom).
## Shows when a touchscreen exists (or `--touch-ui=1` / `--touch-demo=...`), hides on keyboard/gamepad input.

const Tuning := preload("res://scripts/tuning.gd")
const Joystick := preload("res://scripts/ui/touch_joystick.gd")
const TouchButton := preload("res://scripts/ui/touch_button.gd")
const Icons := preload("res://scripts/ui/touch_icons.gd")
const Haptics := preload("res://scripts/input/haptics.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")
const Toast := preload("res://scripts/ui/touch_toast.gd")

const CHAR_TUNING_PATH: String = "res://scripts/character/character_tuning.gd"
const CATAPULT_TUNING_PATH: String = "res://scripts/catapult/catapult_tuning.gd"

const MOVE_LEFT: StringName = &"player_move_left"
const MOVE_RIGHT: StringName = &"player_move_right"
const MOVE_FORWARD: StringName = &"player_move_forward"
const MOVE_BACK: StringName = &"player_move_back"
const RUN: StringName = &"player_run"
const JUMP: StringName = &"player_jump"
const INTERACT: StringName = &"player_interact"

const BIND_STICK: StringName = &"stick"
const BIND_FREE: StringName = &"free"


class FreeFinger:
	extends RefCounted
	var start: Vector2
	var pos: Vector2
	var age: float = 0.0
	var dragged: bool = false
	var pinched: bool = false


var _rig: Node3D = null
var _selection: Node = null
var _hud: CanvasLayer = null
var _player: Node3D = null

var _canvas: Control
var _stick: Joystick
var _jump: TouchButton
var _interact: TouchButton
var _camera_btn: TouchButton
var _day_btn: TouchButton
var _swap_btn: TouchButton
var _buttons: Array[TouchButton] = []

## finger index -> BIND_STICK | BIND_FREE | TouchButton
var _bindings: Dictionary = {}
var _free: Dictionary = {}
var _pinch_dist: float = -1.0
var _taps: Array[Vector3] = []

var _enabled: bool = false
var _shown: bool = false
var _alpha: float = 0.0
var _scale: float = 1.0
var _safe: Rect2 = Rect2()
var _forced_insets: Vector4 = Vector4.ZERO
var _pressed: Dictionary = {}
var _hold_until: Dictionary = {}
var _clock: float = 0.0
var _air_time: float = 0.0
var _was_run: bool = false
var _move_dz: float = 0.2
var _prompt_range: float = 1.6
var _day_night: Node = null
var _last_touch: float = 0.0
var _last_y: float = 0.0
var _still_time: float = 0.0
var _pad_mode: bool = false
var _toast: Control = null


func setup(rig: Node3D, selection: Node, hud: CanvasLayer) -> void:
	_rig = rig
	_selection = selection
	_hud = hud
	if _rig != null and _rig.has_signal(&"mode_changed"):
		_rig.connect(&"mode_changed", func(_s: bool) -> void: _refresh_gadgets())


func set_player(p: Node3D) -> void:
	_player = p


func is_showing() -> bool:
	return _shown


func show_controls(on: bool) -> void:
	if not _enabled or on == _shown:
		return
	_shown = on
	if not on:
		_cancel_all()
	else:
		_last_touch = _clock
	_apply_hud_hint()


## Gamepad hot-plug: toast, hide the touch controls while a pad is connected, bring them back on unplug.
func on_joy_connection(device: int, connected: bool, joy_name: String = "") -> void:
	if joy_name.is_empty():
		joy_name = Input.get_joy_name(device)
	if _toast != null:
		_toast.call(&"show_toast", "Controle conectado" if connected else "Controle desconectado", joy_name, connected)
	Sfx.play(get_tree(), &"ui_pop" if connected else &"ui_tick", Tuning.TOUCH_SFX_DB, 1.0 if connected else 0.8)
	if connected:
		_pad_mode = true
		if _enabled:
			show_controls(false)
	else:
		_pad_mode = not Input.get_connected_joypads().filter(func(d: int) -> bool: return d != device).is_empty()
		if _enabled and not _pad_mode:
			show_controls(true)
	_apply_hud_hint()


func _apply_hud_hint() -> void:
	if _hud == null:
		return
	var mode: StringName = &"touch" if _shown else (&"pad" if _pad_mode else &"desktop")
	if _hud.has_method(&"set_hint_mode"):
		_hud.call(&"set_hint_mode", mode)
	elif _hud.has_method(&"set_touch_mode"):
		_hud.call(&"set_touch_mode", _shown)


func _ready() -> void:
	layer = Tuning.HUD_LAYER + Tuning.TOUCH_LAYER_OFFSET
	var demo: String = ""
	var forced: bool = false
	var joy_demo: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a == "--touch-ui=1" or a == "--touch-ui":
			forced = true
		elif a == "--touch-ui=0":
			forced = false
		elif a.begins_with("--touch-demo"):
			forced = true
			demo = a.trim_prefix("--touch-demo").trim_prefix("=")
			if demo.is_empty():
				demo = "rest"
		elif a == "--joy-demo" or a.begins_with("--joy-demo="):
			joy_demo = true
		elif a.begins_with("--touch-safe="):
			var v: PackedStringArray = a.trim_prefix("--touch-safe=").split(",")
			if v.size() == 4:
				_forced_insets = Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	_enabled = forced or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_move_dz = float(_tuning_const(CHAR_TUNING_PATH, "STICK_DEADZONE", 0.2))
	_prompt_range = float(_tuning_const(CATAPULT_TUNING_PATH, "PROMPT_RANGE", 1.6))

	Icons.glow_texture()
	_canvas = Control.new()
	_canvas.name = "TouchCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)

	_stick = Joystick.new()
	_jump = TouchButton.new(&"jump")
	_jump.accent = Color("FFD45C")
	_interact = TouchButton.new(&"interact")
	_interact.dim_when_unlit = true
	_interact.glow_color = Color("C063E8")
	_camera_btn = TouchButton.new(&"camera")
	_day_btn = TouchButton.new(&"day_night")
	_swap_btn = TouchButton.new(&"swap")
	_buttons = [_swap_btn, _day_btn, _camera_btn, _interact, _jump]

	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_gadgets()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Black", "Segoe UI", "Arial"])
	font.font_weight = 900
	_toast = Toast.new(font)
	_toast.name = "Toast"
	add_child(_toast)
	Input.joy_connection_changed.connect(on_joy_connection)
	_canvas.visible = _enabled
	set_process(_enabled)
	set_process_input(_enabled)
	if _enabled:
		show_controls.call_deferred(true)
		if not demo.is_empty():
			var script: GDScript = load("res://scripts/ui/touch_demo.gd")
			var d: Node = script.new()
			d.name = "TouchDemo"
			add_child(d)
			d.call(&"run", self, demo)
		elif joy_demo:
			var jd: Node = (load("res://scripts/ui/touch_demo.gd") as GDScript).new()
			jd.name = "TouchDemo"
			add_child(jd)
			jd.call(&"run", self, "joy")


func _exit_tree() -> void:
	_release_all_actions()


# --- Layout -------------------------------------------------------------------------------------

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_scale = clampf(minf(vp.x, vp.y) / Tuning.TOUCH_REFERENCE_SHORT_SIDE, Tuning.TOUCH_UI_SCALE_MIN, Tuning.TOUCH_UI_SCALE_MAX)
	_safe = _safe_rect(vp)
	var s: float = _scale
	_stick.place(Vector2(_safe.position.x + Tuning.TOUCH_STICK_HOME.x * s, _safe.end.y - Tuning.TOUCH_STICK_HOME.y * s), Tuning.TOUCH_STICK_RADIUS * s, Tuning.TOUCH_KNOB_RADIUS * s)
	_jump.radius = Tuning.TOUCH_JUMP_RADIUS * s
	_jump.center = _safe.end - Tuning.TOUCH_JUMP_INSET * s
	_interact.radius = Tuning.TOUCH_INTERACT_RADIUS * s
	_interact.center = _jump.center + Tuning.TOUCH_INTERACT_OFFSET * s
	var gx: float = _safe.end.x - (Tuning.TOUCH_MARGIN + Tuning.TOUCH_GADGET_RADIUS) * s
	var gy: float = _jump.center.y - (Tuning.TOUCH_JUMP_RADIUS + Tuning.TOUCH_GADGET_RADIUS + 40.0) * s
	var column: Array[TouchButton] = [_camera_btn, _day_btn, _swap_btn]
	for i: int in column.size():
		column[i].radius = Tuning.TOUCH_GADGET_RADIUS * s
		column[i].center = Vector2(gx, gy - Tuning.TOUCH_GADGET_GAP * s * float(i))


## Safe area (notches) in canvas coordinates. Desktop windows use the whole viewport.
func _safe_rect(vp: Vector2) -> Rect2:
	var rect := Rect2(Vector2.ZERO, vp)
	var to_canvas: Transform2D = get_viewport().get_final_transform().affine_inverse()
	if OS.has_feature("mobile"):
		var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
		var safe: Rect2 = Rect2(DisplayServer.get_display_safe_area()).intersection(win)
		if safe.has_area():
			safe.position -= win.position
			rect = rect.intersection(to_canvas * safe)
	if _forced_insets != Vector4.ZERO:
		var k: float = to_canvas.get_scale().x
		rect = rect.grow_individual(-_forced_insets.x * k, -_forced_insets.y * k, -_forced_insets.z * k, -_forced_insets.w * k)
	return rect


# --- Input --------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			show_controls(true)
			_last_touch = _clock
			_finger_down(t.index, t.position)
		else:
			_finger_up(t.index, t.position, t.canceled)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_finger_drag(d.index, d.position, d.relative)
	elif event is InputEventKey:
		if (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			_pad_mode = false
			show_controls(false)
			_apply_hud_hint()
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_pad_mode = true
			show_controls(false)
			_apply_hud_hint()
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > Tuning.TOUCH_GAMEPAD_AXIS_HIDE:
			_pad_mode = true
			show_controls(false)
			_apply_hud_hint()


func _finger_down(index: int, p: Vector2) -> void:
	if _bindings.has(index):
		_finger_up(index, p, true)
	for b: TouchButton in _buttons:
		if b.hit(p):
			_bindings[index] = b
			_press_button(b, p)
			return
	var left_zone: bool = p.x < _safe.position.x + _safe.size.x * Tuning.TOUCH_LEFT_ZONE and p.y > _safe.position.y + _safe.size.y * Tuning.TOUCH_TOP_BAND
	if left_zone and not _stick.active:
		_bindings[index] = BIND_STICK
		_stick.press(p)
		_feedback(0.12, 0.0, 0.03, &"ui_tick", 1.25, -6.0)
		return
	var f := FreeFinger.new()
	f.start = p
	f.pos = p
	_free[index] = f
	_bindings[index] = BIND_FREE
	if _free.size() == 2:
		_pinch_dist = _pinch_span()
		for other: FreeFinger in _free.values():
			other.pinched = true


func _finger_drag(index: int, p: Vector2, relative: Vector2) -> void:
	var bound: Variant = _bindings.get(index)
	if bound == null:
		return
	if bound is StringName and bound == BIND_STICK:
		_stick.drag(p)
	elif bound is StringName and bound == BIND_FREE:
		var f: FreeFinger = _free[index]
		f.pos = p
		if f.start.distance_to(p) > Tuning.TOUCH_TAP_SLOP * _scale:
			f.dragged = true
		if _free.size() >= 2:
			var span: float = _pinch_span()
			if _pinch_dist > 0.0 and span > 0.0:
				_rig_call(&"touch_zoom", [span / _pinch_dist])
			_pinch_dist = span
		elif not f.pinched and f.dragged and _is_shoulder():
			_rig_call(&"touch_orbit", [relative * Tuning.TOUCH_ORBIT_GAIN])


func _finger_up(index: int, p: Vector2, canceled: bool) -> void:
	var bound: Variant = _bindings.get(index)
	_bindings.erase(index)
	if bound == null:
		return
	if bound is StringName and bound == BIND_STICK:
		_stick.release()
	elif bound is StringName and bound == BIND_FREE:
		var f: FreeFinger = _free[index]
		_free.erase(index)
		if _free.size() < 2:
			_pinch_dist = -1.0
		if not canceled and not f.pinched and not f.dragged and f.age <= Tuning.TOUCH_TAP_TIME:
			_taps.append(Vector3(p.x, p.y, 0.0))
			_rig_call(&"touch_tap", [p])
	elif bound is TouchButton:
		var b: TouchButton = bound
		b.release()
		if b == _jump:
			_release_action_soon(JUMP)
		elif b == _interact:
			_release_action_soon(INTERACT)


func _press_button(b: TouchButton, p: Vector2) -> void:
	b.press(p)
	match b.kind:
		&"jump":
			_press_action(JUMP, 1.0)
			_feedback(0.35, 0.2, 0.05, &"ui_tick", 0.9, 0.0)
		&"interact":
			_press_action(INTERACT, 1.0)
			_feedback(0.3, 0.45 if b.lit_target else 0.1, 0.06, &"ui_pop" if b.lit_target else &"ui_tick", 1.0, 0.0)
		&"camera":
			_rig_call(&"toggle_mode", [])
			_feedback(0.25, 0.0, 0.04, &"ui_select", 1.0, 0.0)
		&"day_night":
			var dn: Node = _find_day_night()
			if dn != null and dn.has_method(&"toggle"):
				dn.call(&"toggle")
			_feedback(0.25, 0.0, 0.04, &"ui_select", 0.85, 0.0)
		&"swap":
			_rig_call(&"swap_shoulder", [])
			_feedback(0.25, 0.0, 0.04, &"ui_tick", 1.1, 0.0)
	_refresh_gadgets()


func _pinch_span() -> float:
	var pts: Array = _free.values()
	if pts.size() < 2:
		return -1.0
	return (pts[0] as FreeFinger).pos.distance_to((pts[1] as FreeFinger).pos)


func _cancel_all() -> void:
	_stick.release()
	for b: TouchButton in _buttons:
		b.release()
	_bindings.clear()
	_free.clear()
	_pinch_dist = -1.0
	_hold_until.clear()
	_release_all_actions()


# --- Actions ------------------------------------------------------------------------------------

func _press_action(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	_hold_until.erase(action)
	if strength <= 0.0:
		if _pressed.has(action):
			Input.action_release(action)
			_pressed.erase(action)
		return
	Input.action_press(action, clampf(strength, 0.0, 1.0))
	if not _pressed.has(action):
		_pressed[action] = _clock


## Taps can be shorter than a physics tick: keep the action held for a minimum time.
func _release_action_soon(action: StringName) -> void:
	if not _pressed.has(action):
		return
	_hold_until[action] = float(_pressed[action]) + Tuning.TOUCH_MIN_HOLD


func _release_all_actions() -> void:
	for action: StringName in _pressed.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_pressed.clear()
	_hold_until.clear()


func _feed_move() -> void:
	var v: Vector2 = _stick.output()
	# The player reads get_vector() with its own radial deadzone: pre-compensate so the response stays linear.
	var len: float = v.length()
	var fed: Vector2 = Vector2.ZERO if len <= 0.0 else v / len * (_move_dz + (1.0 - _move_dz) * len)
	_press_action(MOVE_RIGHT, maxf(fed.x, 0.0))
	_press_action(MOVE_LEFT, maxf(-fed.x, 0.0))
	_press_action(MOVE_BACK, maxf(fed.y, 0.0))
	_press_action(MOVE_FORWARD, maxf(-fed.y, 0.0))
	var run: bool = _stick.active and _stick.in_run_band()
	if run and not _was_run:
		_stick.flash_run()
		_feedback(0.18, 0.0, 0.03, &"ui_tick", 1.5, -6.0)
	_was_run = run
	_press_action(RUN, 1.0 if run else 0.0)


# --- Frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	for action: StringName in _hold_until.keys():
		if _clock >= float(_hold_until[action]):
			_hold_until.erase(action)
			if _pressed.has(action):
				Input.action_release(action)
				_pressed.erase(action)
	for f: FreeFinger in _free.values():
		f.age += delta
	if _shown:
		_feed_move()
	_alpha = move_toward(_alpha, 1.0 if _shown else 0.0, delta / Tuning.TOUCH_FADE_TIME)
	_canvas.modulate.a = _alpha
	_canvas.visible = _alpha > 0.0
	if _alpha <= 0.0:
		return

	_stick.update(delta)
	_update_jump_ring(delta)
	_update_interact()
	_refresh_gadgets()
	for b: TouchButton in _buttons:
		b.update(delta)
	for i: int in range(_taps.size() - 1, -1, -1):
		var t: Vector3 = _taps[i]
		t.z += delta / Tuning.TOUCH_RIPPLE_TIME
		if t.z >= 1.0:
			_taps.remove_at(i)
		else:
			_taps[i] = t
	_canvas.queue_redraw()


func _update_jump_ring(delta: float) -> void:
	var body := _player as CharacterBody3D
	var airborne: bool = body != null and is_instance_valid(body) and not body.is_on_floor() and not _player_busy()
	if airborne:
		# is_on_floor() goes stale while the body is not simulated: require real vertical motion.
		var y: float = body.global_position.y
		_still_time = _still_time + delta if absf(y - _last_y) < 0.0005 else 0.0
		_last_y = y
		airborne = _still_time < 0.15
	_air_time = _air_time + delta if airborne else 0.0
	_jump.ring = clampf(_air_time / Tuning.TOUCH_AIR_RING_TIME, 0.0, 1.0) if airborne and _air_time > 0.05 else -1.0


func _update_interact() -> void:
	var near: bool = _near_interactable()
	_interact.lit_target = near
	_interact.icon_variant = 1 if near else 0


func _near_interactable() -> bool:
	if _player == null or not is_instance_valid(_player) or _player_busy() or _selection == null:
		return false
	var targets: Variant = _selection.get(&"mount_targets")
	if not (targets is Dictionary):
		return false
	for c: Variant in (targets as Dictionary).values():
		if not (c is Node) or not is_instance_valid(c):
			continue
		var controller: Node = c
		if controller.has_method(&"is_ready") and not bool(controller.call(&"is_ready")):
			continue
		var catapult := controller.get_parent() as Node3D
		if catapult == null:
			continue
		var half: Variant = controller.get(&"_footprint_half")
		var fp: Vector2 = half if half is Vector2 else Vector2(1.5, 1.5)
		var local: Vector3 = catapult.global_transform.affine_inverse() * _player.global_position
		var gap := Vector2(maxf(absf(local.x) - fp.x, 0.0), maxf(absf(local.z) - fp.y, 0.0))
		if gap.length() <= _prompt_range:
			return true
	return false


func _player_busy() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var mounted: bool = _player.has_method(&"is_mounted") and bool(_player.call(&"is_mounted"))
	var launched: bool = _player.has_method(&"is_launched") and bool(_player.call(&"is_launched"))
	return mounted or launched


func _refresh_gadgets() -> void:
	var shoulder: bool = _is_shoulder()
	_swap_btn.shown = shoulder
	var idle_cap: float = 1.0 if _clock - _last_touch < Tuning.TOUCH_GADGET_IDLE_DELAY else Tuning.TOUCH_GADGET_IDLE_ALPHA
	for b: TouchButton in [_camera_btn, _day_btn, _swap_btn]:
		b.cap_target = idle_cap
	_camera_btn.icon_variant = 0 if shoulder else 1
	var dn: Node = _find_day_night()
	var night: bool = dn != null and float(dn.get(&"amount")) > 0.5
	_day_btn.icon_variant = 1 if night else 0


func _draw_controls() -> void:
	_stick.draw(_canvas)
	for f: FreeFinger in _free.values():
		_canvas.draw_circle(f.pos, 30.0 * _scale, Color(1, 1, 1, 0.16), true, -1.0, true)
		_canvas.draw_circle(f.pos, 30.0 * _scale, Color(1, 1, 1, 0.5), false, 2.5, true)
	if _free.size() >= 2:
		var pts: Array = _free.values()
		var a: Vector2 = (pts[0] as FreeFinger).pos
		var b: Vector2 = (pts[1] as FreeFinger).pos
		_canvas.draw_dashed_line(a, b, Color(1, 1, 1, 0.38), 3.0, 12.0 * _scale, true, true)
	for t: Vector3 in _taps:
		var e: float = 1.0 - pow(1.0 - t.z, 3.0)
		_canvas.draw_circle(Vector2(t.x, t.y), lerpf(10.0, 46.0, e) * _scale, Color(1, 1, 1, 0.55 * (1.0 - t.z)), false, lerpf(6.0, 1.5, t.z), true)
	for i: int in range(_buttons.size() - 1, -1, -1):
		_buttons[i].draw(_canvas)


# --- Helpers ------------------------------------------------------------------------------------

func _feedback(weak: float, strong: float, duration: float, sfx: StringName, pitch: float, db: float) -> void:
	Haptics.rumble(weak, strong, duration)
	Sfx.play(get_tree(), sfx, Tuning.TOUCH_SFX_DB + db, pitch * randf_range(0.96, 1.04))


func _rig_call(method: StringName, args: Array) -> void:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(method):
		_rig.callv(method, args)


func _is_shoulder() -> bool:
	return _rig != null and is_instance_valid(_rig) and _rig.has_method(&"is_shoulder") and bool(_rig.call(&"is_shoulder"))


func _find_day_night() -> Node:
	if _day_night == null or not is_instance_valid(_day_night):
		_day_night = get_parent().get_node_or_null(^"DayNight") if get_parent() != null else null
	return _day_night


static func _tuning_const(path: String, key: String, fallback: Variant) -> Variant:
	if not ResourceLoader.exists(path):
		return fallback
	var s: Resource = load(path)
	if s is Script:
		return (s as Script).get_script_constant_map().get(key, fallback)
	return fallback
