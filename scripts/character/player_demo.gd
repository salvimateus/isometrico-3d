extends RefCounted

## Autopilot for `--player-demo`: figure eight around the start point cycling walk, run (with a full
## jump, a short hop and a skid) and idle. `--player-demo-mode=cycle|walk|run|jump|skid|idle` pins a
## behaviour for screenshots.

const T := preload("res://scripts/character/character_tuning.gd")

var move := Vector3.ZERO
var run: bool = false
var jump_held: bool = false

var _center := Vector3.ZERO
var _t: float = 0.0
var _clock: float = 0.0
var _mode: String = "cycle"


static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--player-demo")


func _init(center: Vector3) -> void:
	_center = center
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--player-demo-mode="):
			_mode = arg.trim_prefix("--player-demo-mode=")


func update(delta: float, pos: Vector3) -> void:
	_clock += delta
	jump_held = false
	var gait: String = _mode
	var local: float = _clock
	match _mode:
		"cycle":
			var period: float = T.DEMO_SEGMENT_TIME * 2.0 + T.DEMO_IDLE_TIME
			var k: float = fmod(_clock, period)
			if k < T.DEMO_SEGMENT_TIME:
				gait = "walk"
				local = k
			elif k < T.DEMO_SEGMENT_TIME * 2.0:
				gait = "run"
				local = k - T.DEMO_SEGMENT_TIME
			else:
				gait = "idle"
		"jump":
			gait = "run"
			jump_held = fmod(_clock, 1.1) < 0.35 and _clock > 0.6
		"skid":
			gait = "run"
			local = fmod(_clock, 2.4) + 1.6
	if gait == "idle":
		move = Vector3.ZERO
		run = false
		return
	_follow(pos)
	run = gait == "run"
	if run and _mode != "jump":
		if local > 1.0 and local < 1.35:
			jump_held = true
		elif local > 2.0 and local < 2.06:
			jump_held = true
		elif local > 2.8 and local < 3.25:
			move = -move
	elif gait == "walk" and local > 2.2 and local < 2.5:
		jump_held = true


func _follow(pos: Vector3) -> void:
	var guard: int = 0
	while _flat(_curve(_t) - pos).length() < T.DEMO_LOOKAHEAD and guard < 200:
		_t += 0.02
		guard += 1
	move = _flat(_curve(_t) - pos).normalized()


func _curve(t: float) -> Vector3:
	var r: float = T.DEMO_RADIUS
	return _center + Vector3(r * sin(t), 0.0, r * 0.62 * sin(2.0 * t))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
