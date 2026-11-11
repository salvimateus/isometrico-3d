extends RefCounted

## Shared haptics: joypad rumble on the device of the last joypad input; on mobile the phone always vibrates
## too (clip-on gamepads hold the phone). Nothing elsewhere. Feed it every input event via `note_input`.

const HANDHELD_MIN_MS: int = 35
const HANDHELD_MAX_MS: int = 400
const HANDHELD_MERGE_WINDOW_MS: int = 90
const AXIS_ACTIVITY: float = 0.3

static var _joy_device: int = -1
static var _last_was_joy: bool = false
static var _handheld_until_ms: int = 0
static var _handheld_last_amp: float = 0.0


## Records where the last input came from (joypad device vs. touch/mouse/keyboard).
static func note_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_joy_device = event.device
		_last_was_joy = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > AXIS_ACTIVITY:
			_joy_device = event.device
			_last_was_joy = true
	elif event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed() or event is InputEventScreenDrag:
			_last_was_joy = false


## weak = high-frequency motor, strong = low-frequency motor, both 0..1; duration in seconds.
static func rumble(weak: float, strong: float, duration: float) -> void:
	weak = clampf(weak, 0.0, 1.0)
	strong = clampf(strong, 0.0, 1.0)
	if weak <= 0.0 and strong <= 0.0:
		return
	var joy_active: bool = _last_was_joy and _joy_device >= 0 and Input.get_connected_joypads().has(_joy_device)
	var mobile: bool = OS.has_feature("mobile")
	if joy_active and (not mobile or _joy_has_motor(_joy_device)):
		Input.start_joy_vibration(_joy_device, weak, strong, duration)
	if not mobile:
		return
	# On phones the phone motor always fires, also with a clip-on USB-C gamepad (usually motorless): the
	# phone sits between the grips, so its vibration reaches the hands. Gamepads with a motor get both.
	# Joypads in the stock Android layout map to the standard JOY_BUTTON_*/JOY_AXIS_* ids; controllers that
	# send the sticks on non-standard axes are not remapped here.
	var amp: float = clampf(maxf(strong, weak * 0.6), 0.05, 1.0)
	var ms: int = clampi(int(duration * 1000.0), HANDHELD_MIN_MS, HANDHELD_MAX_MS)
	var now: int = Time.get_ticks_msec()
	# Pulses landing inside the one still playing merge into it unless clearly stronger: no buzzing.
	if now < _handheld_until_ms + HANDHELD_MERGE_WINDOW_MS and amp <= _handheld_last_amp * 1.25:
		return
	_handheld_until_ms = now + ms
	_handheld_last_amp = amp
	Input.vibrate_handheld(ms, amp)


static func _joy_has_motor(device: int) -> bool:
	return Input.has_method(&"has_joy_vibration") and bool(Input.call(&"has_joy_vibration", device))


static func last_joypad_device() -> int:
	return _joy_device if _last_was_joy else -1
