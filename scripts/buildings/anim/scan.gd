extends Node3D
## Turret idle: turns toward a random heading, pauses, picks another.

const Tuning = preload("res://scripts/buildings/building_tuning.gd")

var _base: Basis
var _yaw: float = 0.0
var _target: float = 0.0
var _wait: float = 0.0


func _ready() -> void:
	_base = basis
	_yaw = deg_to_rad(randf_range(-Tuning.CANNON_ARC_DEG, Tuning.CANNON_ARC_DEG))
	_target = _yaw
	_wait = randf_range(0.0, Tuning.CANNON_PAUSE_MAX)
	basis = _base * Basis(Vector3.UP, _yaw)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_target = deg_to_rad(randf_range(-Tuning.CANNON_ARC_DEG, Tuning.CANNON_ARC_DEG))
		return
	var diff: float = _target - _yaw
	var step: float = Tuning.CANNON_TURN_SPEED * delta * clampf(absf(diff) * 2.5, 0.25, 1.0)
	if absf(diff) <= step:
		_yaw = _target
		_wait = randf_range(Tuning.CANNON_PAUSE_MIN, Tuning.CANNON_PAUSE_MAX)
	else:
		_yaw += signf(diff) * step
	basis = _base * Basis(Vector3.UP, _yaw)
