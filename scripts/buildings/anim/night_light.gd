extends OmniLight3D
## Warm lamp that switches on past its own random night threshold, pops in and flickers softly.

const Tuning = preload("res://scripts/buildings/building_tuning.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const GROUP: StringName = &"building_night_lights"

var _threshold: float = 0.5
var _on: bool = false
var _pop: float = 0.0
var _time: float = 0.0
var _enabled: bool = true


func _ready() -> void:
	add_to_group(GROUP)
	_threshold = randf_range(Tuning.NIGHT_LIGHT_THRESHOLD_MIN, Tuning.NIGHT_LIGHT_THRESHOLD_MAX)
	_time = randf() * 100.0
	light_energy = 0.0
	visible = false
	set_process(false)
	_enabled = Tuning.lights_enabled
	apply_night(Mat.night_amount, true)


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on and _on
	set_process(on and _on)


func apply_night(amount: float, instant: bool = false) -> void:
	var want: bool = amount >= _threshold
	if want == _on:
		return
	_on = want
	visible = want and _enabled
	set_process(want and _enabled)
	_pop = 0.0 if instant else Tuning.NIGHT_LIGHT_POP_TIME
	if not want:
		light_energy = 0.0


func _process(delta: float) -> void:
	_time += delta
	var flicker: float = 1.0 + Tuning.NIGHT_LIGHT_FLICKER * (sin(_time * 13.0) * 0.5 + sin(_time * 7.3 + 1.7) * 0.35 + sin(_time * 23.0) * 0.15)
	var pop: float = 1.0
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta)
		var k: float = 1.0 - _pop / Tuning.NIGHT_LIGHT_POP_TIME
		pop = k * (1.0 + 0.8 * sin(k * PI))
	light_energy = Tuning.NIGHT_LIGHT_ENERGY * flicker * pop
