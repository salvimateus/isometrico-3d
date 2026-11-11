extends Node3D
## Rotational oscillation around a local axis (signs, rocking parts).

@export var axis: Vector3 = Vector3.FORWARD
@export var amplitude_deg: float = 6.0
@export var speed: float = 1.4

var _base: Basis
var _time: float = 0.0


func _ready() -> void:
	_base = basis
	_time = randf() * TAU


func _process(delta: float) -> void:
	_time += delta * speed
	basis = _base * Basis(axis.normalized(), deg_to_rad(amplitude_deg) * sin(_time))
