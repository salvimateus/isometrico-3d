extends RefCounted

## Player feedback vibration with per-event cooldowns, routed through the shared haptics helper.
## Cooldowns run even without a joypad so paired feedback (impact SFX, camera trauma) stays in sync.

const T := preload("res://scripts/character/character_tuning.gd")
const Haptics := preload("res://scripts/input/haptics.gd")

var _now: float = 0.0
var _next_step: float = 0.0
var _next_run_start: float = 0.0
var _next_impact: float = 0.0
var _next_land: float = 0.0


func note_event(event: InputEvent) -> void:
	Haptics.note_input(event)


func tick(delta: float) -> void:
	_now += delta


func step() -> bool:
	if _now < _next_step:
		return false
	_next_step = _now + T.RUMBLE_STEP_COOLDOWN
	_vibrate(T.RUMBLE_STEP_WEAK, T.RUMBLE_STEP_STRONG, T.RUMBLE_STEP_DURATION)
	return true


func run_start() -> bool:
	if _now < _next_run_start:
		return false
	_next_run_start = _now + T.RUMBLE_RUN_START_COOLDOWN
	_vibrate(T.RUMBLE_RUN_START_WEAK, T.RUMBLE_RUN_START_STRONG, T.RUMBLE_RUN_START_DURATION)
	return true


func jump() -> void:
	_vibrate(T.RUMBLE_JUMP_WEAK, T.RUMBLE_JUMP_STRONG, T.RUMBLE_JUMP_DURATION)


func stumble() -> void:
	_vibrate(T.RUMBLE_STUMBLE_WEAK, T.RUMBLE_STUMBLE_STRONG, T.RUMBLE_STUMBLE_DURATION)


func launch() -> void:
	_vibrate(T.RUMBLE_LAUNCH_WEAK, T.RUMBLE_LAUNCH_STRONG, T.RUMBLE_LAUNCH_DURATION)


func crash() -> void:
	_vibrate(T.RUMBLE_CRASH_WEAK, T.RUMBLE_CRASH_STRONG, T.RUMBLE_CRASH_DURATION)


func skid() -> void:
	_vibrate(T.RUMBLE_SKID_WEAK, T.RUMBLE_SKID_STRONG, T.RUMBLE_SKID_DURATION)


## strength: 0..1.
func land(strength: float) -> bool:
	if _now < _next_land:
		return false
	_next_land = _now + T.RUMBLE_LAND_COOLDOWN
	var k: float = clampf(strength, 0.0, 1.0)
	_vibrate(T.RUMBLE_LAND_WEAK_MAX * k, T.RUMBLE_LAND_STRONG_MAX * k, lerpf(T.RUMBLE_LAND_DURATION_MIN, T.RUMBLE_LAND_DURATION_MAX, k))
	return true


## strength: 0..1. Returns false while on cooldown.
func impact(strength: float) -> bool:
	if _now < _next_impact:
		return false
	_next_impact = _now + T.RUMBLE_IMPACT_COOLDOWN
	var k: float = clampf(strength, 0.0, 1.0)
	_vibrate(T.RUMBLE_IMPACT_WEAK_MAX * k, T.RUMBLE_IMPACT_STRONG_MAX * k, lerpf(T.RUMBLE_IMPACT_DURATION_MIN, T.RUMBLE_IMPACT_DURATION_MAX, k))
	return true


func _vibrate(weak: float, strong: float, duration: float) -> void:
	if T.RUMBLE_ENABLED:
		Haptics.rumble(weak, strong, duration)
