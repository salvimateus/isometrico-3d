extends Node3D
## Continuous rotation around a local axis.

@export var axis: Vector3 = Vector3.UP
@export var speed: float = 1.0

var _base: Basis
var _angle: float = 0.0


func _ready() -> void:
	_base = basis
	_angle = randf() * TAU


func _process(delta: float) -> void:
	_angle = fmod(_angle + speed * delta, TAU)
	basis = _base * Basis(axis.normalized(), _angle)
