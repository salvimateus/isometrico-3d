extends Node3D

## Sandbox stand-in for the LIQUID agent's field (`--sandbox-water`): a shallow pool with a periodic fast
## wave front, exposing the `liquid_field` contract: depth_at, velocity_at, add_disturbance.

const POOL := Rect2(1.0, -2.8, 3.8, 5.6)
const DEPTH: float = 0.32
const EDGE: float = 0.35
const WAVE_PERIOD: float = 4.5
const WAVE_SPEED: float = 5.0
const WAVE_FLOW: float = 5.5
const WAVE_HALF_WIDTH: float = 0.45
const DRIFT := Vector3(-0.35, 0.0, 0.0)

var disturbances: int = 0
var _time: float = 0.0
var _front: MeshInstance3D


func _ready() -> void:
	add_to_group(&"liquid_field")
	var water := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(POOL.size.x, DEPTH, POOL.size.y)
	water.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.7, 0.95, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(POOL.get_center().x, DEPTH * 0.5, POOL.get_center().y)
	add_child(water)
	_front = MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.3, DEPTH + 0.12, POOL.size.y)
	_front.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.9, 0.97, 1.0, 0.75)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_front.material_override = fm
	_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_front)


func _physics_process(delta: float) -> void:
	_time += delta
	_front.position = Vector3(_front_x(), (DEPTH + 0.12) * 0.5, POOL.get_center().y)


func depth_at(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	if not POOL.has_point(p):
		return 0.0
	var dx: float = minf(p.x - POOL.position.x, POOL.end.x - p.x)
	var dz: float = minf(p.y - POOL.position.y, POOL.end.y - p.y)
	return DEPTH * smoothstep(0.0, EDGE, minf(dx, dz))


func velocity_at(pos: Vector3) -> Vector3:
	if depth_at(pos) <= 0.0:
		return Vector3.ZERO
	var d: float = absf(pos.x - _front_x())
	if d < WAVE_HALF_WIDTH:
		return Vector3(-WAVE_FLOW * (1.0 - d / WAVE_HALF_WIDTH), 0.0, 0.0)
	return DRIFT


func add_disturbance(_pos: Vector3, _velocity: Vector3, _radius: float) -> void:
	disturbances += 1


func _front_x() -> float:
	var k: float = fmod(_time, WAVE_PERIOD) * WAVE_SPEED
	return POOL.end.x + 1.0 - k
