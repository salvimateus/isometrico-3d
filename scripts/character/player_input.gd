extends RefCounted

## Registers the `player_*` input actions at runtime and reads them (left stick + WASD, RB + Shift, A + Space, X + E).

const T := preload("res://scripts/character/character_tuning.gd")

const MOVE_LEFT: StringName = &"player_move_left"
const MOVE_RIGHT: StringName = &"player_move_right"
const MOVE_FORWARD: StringName = &"player_move_forward"
const MOVE_BACK: StringName = &"player_move_back"
const RUN: StringName = &"player_run"
const JUMP: StringName = &"player_jump"
const INTERACT: StringName = &"player_interact"


static func ensure_actions() -> void:
	_ensure(MOVE_LEFT, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure(MOVE_RIGHT, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure(MOVE_FORWARD, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure(MOVE_BACK, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_ensure(RUN, [_key(KEY_SHIFT), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_ensure(JUMP, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_ensure(INTERACT, [_key(KEY_E), _button(JOY_BUTTON_X)])


## Screen-space move vector: x = right, y = down (forward is negative). Radial deadzone, remapped to 0..1.
static func read_move() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_FORWARD, MOVE_BACK, T.STICK_DEADZONE)


static func is_run_held() -> bool:
	return Input.is_action_pressed(RUN)


static func is_jump_held() -> bool:
	return Input.is_action_pressed(JUMP)


static func _ensure(action: StringName, events: Array[InputEvent]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, T.ACTION_DEADZONE)
	for ev: InputEvent in events:
		InputMap.action_add_event(action, ev)


static func _key(code: Key) -> InputEvent:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


static func _axis(axis: JoyAxis, value: float) -> InputEvent:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = value
	return ev


static func _button(button: JoyButton) -> InputEvent:
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button
	return ev
