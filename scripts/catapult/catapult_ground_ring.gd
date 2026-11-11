extends MeshInstance3D

## Flat ground marker: landing target (blinks faster and shrinks until impact) or impact shockwave.

const T := preload("res://scripts/catapult/catapult_tuning.gd")
const RingShader := preload("res://shaders/catapult/catapult_ground_ring.gdshader")

enum Mode { TARGET, SHOCKWAVE }

var _mat: ShaderMaterial
var _mode: Mode = Mode.TARGET
var _duration: float = 1.0
var _age: float = 0.0
var _active: bool = false
var _phase: float = 0.0
var _out: float = -1.0


func _init() -> void:
	name = "CatapultGroundRing"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var extent: float = maxf(T.RING_RADIUS_START, T.LAND_SHOCKWAVE_RADIUS) + 0.3
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent) * 2.0
	mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = RingShader
	_mat.set_shader_parameter(&"extent", extent)
	_mat.render_priority = 3
	material_override = _mat
	visible = false
	set_process(false)


## Shows the landing marker at `pos` for `duration` seconds (the expected flight time).
func show_target(pos: Vector3, duration: float) -> void:
	_start(Mode.TARGET, pos, duration)
	_mat.set_shader_parameter(&"mode", 0)
	_mat.set_shader_parameter(&"color", T.RING_COLOR)
	_mat.set_shader_parameter(&"thickness", 0.18)


# Godot re-enables processing on ready when _process exists; stay idle until used.
func _ready() -> void:
	set_process(false)


func shockwave(pos: Vector3, color: Color = Color(1.0, 0.97, 0.88, 0.85)) -> void:
	_start(Mode.SHOCKWAVE, pos, T.LAND_SHOCKWAVE_TIME)
	_mat.set_shader_parameter(&"mode", 1)
	_mat.set_shader_parameter(&"color", color)


## Pops the target marker away (impact or abort).
func dismiss() -> void:
	if _active and _out < 0.0:
		_out = 0.0


func _start(mode: Mode, pos: Vector3, duration: float) -> void:
	_mode = mode
	_duration = maxf(duration, 0.05)
	_age = 0.0
	_phase = 0.0
	_out = -1.0
	_active = true
	global_position = pos + Vector3.UP * T.RING_LIFT
	visible = true
	_update(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / _duration, 0.0, 1.0)
	if _mode == Mode.SHOCKWAVE:
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		_mat.set_shader_parameter(&"radius", lerpf(0.3, T.LAND_SHOCKWAVE_RADIUS, e))
		_mat.set_shader_parameter(&"thickness", lerpf(0.5, 0.06, t))
		_mat.set_shader_parameter(&"opacity", 1.0 - t)
		if t >= 1.0:
			_finish()
		return
	_phase += delta * lerpf(T.RING_BLINK_START, T.RING_BLINK_END, t) * TAU
	var appear: float = clampf(_age / 0.25, 0.0, 1.0)
	var pop: float = 1.0 + 0.5 * (1.0 - appear) * (1.0 - appear)
	var radius: float = lerpf(T.RING_RADIUS_START, T.RING_RADIUS_END, t * t * (3.0 - 2.0 * t)) * pop
	var opacity: float = appear
	if _out >= 0.0:
		_out += delta
		var k: float = clampf(_out / 0.18, 0.0, 1.0)
		radius *= 1.0 + 0.8 * k
		opacity *= 1.0 - k
		if k >= 1.0:
			_finish()
			return
	_mat.set_shader_parameter(&"radius", radius)
	_mat.set_shader_parameter(&"blink", 0.5 + 0.5 * sin(_phase))
	_mat.set_shader_parameter(&"spin", _age * 1.6)
	_mat.set_shader_parameter(&"opacity", opacity)


func _finish() -> void:
	_active = false
	visible = false
	set_process(false)
