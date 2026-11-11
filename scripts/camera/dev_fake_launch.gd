extends Node

## Dev only (`--fake-launch=1`, optional `--fake-launch-speed=N`): throws the player on a ballistic arc
## from the catapult toward the `catapult_target` marker (fallback FALLBACK_END) so the camera's flight framing can be checked without the catapult.
## Gravity is solved so the arc lands on the target. Marks the flight with meta `launched`.

const START := Vector3(-8.5, 0.0, -8.5)
const FALLBACK_END := Vector3(8.8, 0.0, 8.8)
const ANGLE_DEG: float = 50.0
const DELAY_FRAMES: int = 60

var _frame: int = 0
var _flying: bool = false
var _done: bool = false
var _gravity: float = 9.8
var _vel := Vector3.ZERO
var _speed: float = 17.0
var _body: CharacterBody3D
var _end := FALLBACK_END


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-launch-speed="):
			_speed = float(arg.get_slice("=", 1))


func _physics_process(delta: float) -> void:
	_frame += 1
	if _done or _frame < DELAY_FRAMES:
		return
	if not _flying:
		_body = get_tree().get_first_node_in_group(&"player") as CharacterBody3D
		if _body == null:
			_body = get_parent().get(&"follow_target") as CharacterBody3D
		if _body == null:
			_done = true
			return
		var target := get_tree().get_first_node_in_group(&"catapult_target") as Node3D
		if target != null:
			_end = target.global_position
		var flat: Vector3 = Vector3(_end.x - START.x, 0.0, _end.z - START.z)
		var angle: float = deg_to_rad(ANGLE_DEG)
		_gravity = _speed * _speed * sin(2.0 * angle) / flat.length()
		_vel = flat.normalized() * _speed * cos(angle) + Vector3.UP * _speed * sin(angle)
		_body.set_physics_process(false)
		_body.global_position = START + Vector3.UP * 0.05
		_body.reset_physics_interpolation()
		_body.velocity = _vel
		_body.set_meta(&"launched", true)
		_flying = true
		print("[FakeLaunch] speed=%.1f gravity=%.1f target=%s" % [_speed, _gravity, str(_end)])
		return
	_vel.y -= _gravity * delta
	var pos: Vector3 = _body.global_position + _vel * delta
	_body.velocity = _vel
	if pos.y <= _end.y + 0.05 and _vel.y < 0.0:
		pos.y = _end.y + 0.05
		_body.global_position = pos
		_body.velocity = Vector3.ZERO
		_body.set_meta(&"launched", false)
		_body.set_physics_process(true)
		_done = true
		return
	_body.global_position = pos
