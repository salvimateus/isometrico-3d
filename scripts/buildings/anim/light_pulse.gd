extends OmniLight3D
## Energy pulse matching the mana shader rhythm.

const Tuning = preload("res://scripts/buildings/building_tuning.gd")
const Mat = preload("res://scripts/buildings/materials.gd")

var _base_energy: float = 1.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group(Tuning.MANA_LIGHT_GROUP)
	_base_energy = light_energy
	_time = randf() * TAU
	set_enabled(Tuning.lights_enabled)


func set_enabled(on: bool) -> void:
	visible = on
	set_process(on)


func _process(delta: float) -> void:
	_time += delta * Tuning.MANA_PULSE_SPEED
	var night: float = lerpf(1.0, Tuning.NIGHT_MANA_MULTIPLIER, Mat.night_amount)
	light_energy = _base_energy * night * (0.8 + 0.2 * sin(_time))
