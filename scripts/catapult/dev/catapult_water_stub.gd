extends MeshInstance3D

## Sandbox pond implementing the `water_body` contract (group &"water_body"): surface_height_at,
## splash with shader rings, nearest_shore. Rectangular surface centered on the node, at its height.

const WaterShader := preload("res://shaders/catapult/catapult_water_stub.gdshader")
const MAX_SPLASHES: int = 8
const RING_LIFE: float = 1.6
const SHORE_OFFSET: float = 0.6

var half_size := Vector2(2.6, 2.6)
var _mat: ShaderMaterial
var _splashes: Array[Vector4] = []
var _next: int = 0


func _init(size: Vector2 = Vector2(5.2, 5.2)) -> void:
	name = "WaterStub"
	half_size = size * 0.5
	add_to_group(&"water_body")
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = WaterShader
	_mat.set_shader_parameter(&"ring_life", RING_LIFE)
	material_override = _mat
	for i: int in MAX_SPLASHES:
		_splashes.append(Vector4.ZERO)
	_push()


func surface_height_at(pos: Vector3) -> float:
	var l: Vector3 = global_transform.affine_inverse() * pos
	if absf(l.x) > half_size.x or absf(l.z) > half_size.y:
		return -INF
	return global_position.y


func splash(pos: Vector3, strength: float) -> void:
	var l: Vector3 = global_transform.affine_inverse() * pos
	_splashes[_next] = Vector4(l.x, l.z, 0.0, maxf(strength, 0.05))
	_next = (_next + 1) % MAX_SPLASHES
	_push()


## Closest dry point just outside the water rectangle, on the bank (y = 0).
func nearest_shore(pos: Vector3) -> Vector3:
	var l: Vector3 = global_transform.affine_inverse() * pos
	var dx: float = half_size.x - absf(l.x)
	var dz: float = half_size.y - absf(l.z)
	var out := Vector3(l.x, 0.0, l.z)
	if dx < dz:
		out.x = signf(l.x if l.x != 0.0 else 1.0) * (half_size.x + SHORE_OFFSET)
	else:
		out.z = signf(l.z if l.z != 0.0 else 1.0) * (half_size.y + SHORE_OFFSET)
	var world: Vector3 = global_transform * out
	world.y = 0.0
	return world


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in MAX_SPLASHES:
		var s: Vector4 = _splashes[i]
		if s.w > 0.0 and s.z < RING_LIFE:
			s.z += delta
			_splashes[i] = s
			any = true
	if any:
		_push()


func _push() -> void:
	var arr := PackedVector4Array()
	for s: Vector4 in _splashes:
		arr.append(s)
	_mat.set_shader_parameter(&"splashes", arr)
