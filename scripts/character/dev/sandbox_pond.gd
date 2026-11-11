extends Node3D

## Sandbox stand-in for the WORLD's still pond (`--sandbox-pond`): exposes the `water_body` contract
## (surface_height_at, splash, nearest_shore), a sunken floor on layer 1 and an invisible barrier ring on
## layer 5 (value 16) that keeps a walking player out.

const HALF := Vector2(2.2, 1.8)
const SURFACE_Y: float = 0.0
const DEPTH: float = 0.75
const SHORE_MARGIN: float = 0.6

var splashes: int = 0
var _ripples: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"water_body")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -DEPTH - 0.1, 0.0)
	add_child(floor_body)
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(HALF.x * 2.0, 0.2, HALF.y * 2.0)
	fs.shape = fb
	floor_body.add_child(fs)
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = fb.size
	bed.mesh = bm
	bed.material_override = _mat(Color("6C8F7A"), 1.0)
	floor_body.add_child(bed)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = HALF * 2.0
	water.mesh = plane
	water.material_override = _mat(Color(0.25, 0.6, 0.85, 0.7), 0.1)
	water.position.y = SURFACE_Y - 0.02
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	var barrier := StaticBody3D.new()
	barrier.collision_layer = 16
	barrier.collision_mask = 0
	add_child(barrier)
	for side: int in 4:
		var horizontal: bool = side < 2
		var sign: float = 1.0 if side % 2 == 0 else -1.0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(HALF.x * 2.0 + 0.4, 2.0, 0.2) if horizontal else Vector3(0.2, 2.0, HALF.y * 2.0 + 0.4)
		cs.shape = box
		cs.position = Vector3(0.0, 1.0, sign * (HALF.y + 0.1)) if horizontal else Vector3(sign * (HALF.x + 0.1), 1.0, 0.0)
		barrier.add_child(cs)


func surface_height_at(pos: Vector3) -> float:
	var local: Vector3 = pos - global_position
	if absf(local.x) > HALF.x or absf(local.z) > HALF.y:
		return -INF
	return global_position.y + SURFACE_Y


func splash(pos: Vector3, strength: float) -> void:
	splashes += 1
	for i: int in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		ring.mesh = torus
		ring.material_override = _mat(Color(1.0, 1.0, 1.0, 0.6), 0.1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = Vector3(pos.x, global_position.y + SURFACE_Y + 0.01, pos.z)
		ring.scale = Vector3(0.2, 0.05, 0.2)
		var tw := ring.create_tween()
		tw.tween_interval(0.15 * i)
		tw.tween_property(ring, "scale", Vector3(1.6, 0.05, 1.6) * (0.6 + 0.4 * strength), 1.2).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, 1.2)
		tw.tween_callback(ring.queue_free)


func nearest_shore(pos: Vector3) -> Vector3:
	var local: Vector3 = pos - global_position
	var dx: float = HALF.x - absf(local.x)
	var dz: float = HALF.y - absf(local.z)
	var out: Vector3 = local
	if dx < dz:
		out.x = signf(local.x if local.x != 0.0 else 1.0) * (HALF.x + SHORE_MARGIN)
	else:
		out.z = signf(local.z if local.z != 0.0 else 1.0) * (HALF.y + SHORE_MARGIN)
	out.y = 0.0
	return global_position + out


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
