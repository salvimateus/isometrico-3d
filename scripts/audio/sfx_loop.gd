extends Node

## Handle for a looping preset started by sfx.gd play_loop. Owns one AudioStreamPlayer or
## AudioStreamPlayer3D; volume changes are smoothed and stop() fades out, then frees the handle.

const SMOOTH_TAU: float = 0.08
const SILENT_DB: float = -80.0

var _player: Node
var _target_lin: float = 1.0
var _current_lin: float = 1.0
var _fade_total: float = 0.0
var _fade_left: float = 0.0
var _stopping: bool = false
var _on_released: Callable


func setup(player: Node, volume_db: float, on_released: Callable) -> void:
	name = "SfxLoop"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = player
	_on_released = on_released
	_target_lin = db_to_linear(volume_db)
	_current_lin = _target_lin
	_player.set(&"volume_db", volume_db)
	# Same reason as the pool: a player leaving the tree only pauses, which leaks at exit.
	_player.tree_exiting.connect(_release)
	add_child(_player)


func _ready() -> void:
	if _stopping and _fade_left <= 0.0:
		queue_free()
		return
	_player.call(&"play")


func set_volume_db(db: float) -> void:
	_target_lin = db_to_linear(db)


## Fades out over fade_time seconds (0 = immediately) and frees the handle. Safe to call twice:
## a later call can only shorten the remaining fade.
func stop(fade_time: float = 0.3) -> void:
	if is_queued_for_deletion():
		return
	if _stopping:
		if fade_time < _fade_left:
			_fade_left = maxf(fade_time, 0.0)
			_fade_total = maxf(_fade_total, 0.0001)
		return
	_stopping = true
	_fade_total = maxf(fade_time, 0.0001)
	_fade_left = maxf(fade_time, 0.0)
	if _fade_left <= 0.0 and is_inside_tree():
		_finish()


func is_stopping() -> bool:
	return _stopping


func _process(delta: float) -> void:
	_current_lin += (_target_lin - _current_lin) * (1.0 - exp(-delta / SMOOTH_TAU))
	var gain: float = 1.0
	if _stopping:
		_fade_left -= delta
		if _fade_left <= 0.0:
			_finish()
			return
		gain = _fade_left / _fade_total
	var lin: float = _current_lin * gain * gain
	_player.set(&"volume_db", linear_to_db(lin) if lin > 0.0001 else SILENT_DB)


func _finish() -> void:
	set_process(false)
	_player.call(&"stop")
	queue_free()


func _release() -> void:
	if _player.get(&"playing"):
		_on_released.call()
	_player.call(&"stop")
	_player.set(&"stream", null)
