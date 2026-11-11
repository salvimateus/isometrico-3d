extends Node3D
## Sine offset along a local axis (pistons, floating bits).

@export var axis: Vector3 = Vector3.UP
@export var amplitude: float = 0.1
@export var speed: float = 2.0
@export var random_phase: bool = true

var _base: Vector3
var _time: float = 0.0


func _ready() -> void:
	_base = position
	if random_phase:
		_time = randf() * TAU


func _process(delta: float) -> void:
	_time += delta * speed
	position = _base + axis * (amplitude * sin(_time))
