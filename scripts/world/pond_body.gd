extends Node3D

## The pond as a water body (group &"water_body"): surface queries, splash FX and a safe shore point.
## Splash rings and lily/reed bobbing read the `pond_splash` global (x, z, start world_time, strength).

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")
const WATER_FX_PATH: String = "res://scripts/liquid/water_fx.gd"


func _ready() -> void:
	add_to_group(&"water_body")


func surface_height_at(pos: Vector3) -> float:
	if Layout.pond_sdf(Vector2(pos.x, pos.z)) < 0.0:
		return Shape.POND_WATER_Y
	return -INF


func splash(pos: Vector3, strength: float) -> void:
	var s: float = clampf(strength, 0.1, 2.0)
	var fx: Node = get_tree().get_first_node_in_group(&"world_fx")
	var now: float = float(fx.get(&"time")) if fx != null else 0.0
	RenderingServer.global_shader_parameter_set(&"pond_splash", Vector4(pos.x, pos.z, now, s))
	var water_fx: Node = _water_fx()
	if water_fx != null:
		water_fx.call(&"splash", Vector3(pos.x, Shape.POND_WATER_Y, pos.z), s, Shape.POND_WATER_Y)
	elif fx != null:
		fx.call(&"splash_drops", Vector3(pos.x, Shape.POND_WATER_Y, pos.z), s)
	Sfx.play(get_tree(), &"splash_big", lerpf(-6.0, 0.0, clampf(s, 0.0, 1.0)), randf_range(0.9, 1.05))


func _water_fx() -> Node:
	if not ResourceLoader.exists(WATER_FX_PATH):
		return null
	var script: Resource = load(WATER_FX_PATH)
	if not (script is GDScript) or not (script as GDScript).can_instantiate():
		return null
	return (script as GDScript).call(&"get_or_create", get_tree())


## Closest walkable land point outside the pond barrier, clear of layer-2 obstacles.
func nearest_shore(pos: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = Tuning.POND_SHORE_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 2
	var view_probe := SphereShape3D.new()
	view_probe.radius = Tuning.POND_SHORE_CAMERA_ROOM
	var view_query := PhysicsShapeQueryParameters3D.new()
	view_query.shape = view_probe
	view_query.collision_mask = 1 | 2
	var best := Vector3.ZERO
	var best_d: float = INF
	for lobe: Vector3 in Layout.POND_LOBES:
		var center := Vector2(lobe.x, lobe.y)
		for i: int in 48:
			var a: float = TAU * i / 48.0
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * (lobe.z + Tuning.POND_SHORE_OFFSET)
			if Layout.pond_sdf(p) < Tuning.POND_SHORE_OFFSET * 0.8 or Shape.inside_margin(p) < 1.2:
				continue
			var y: float = Shape.ground_height(p)
			query.transform = Transform3D(Basis(), Vector3(p.x, y + 0.6, p.y))
			if not space.intersect_shape(query, 1).is_empty():
				continue
			# Leave ~1.5 of free air above and behind the shore point for the shoulder camera.
			view_query.transform = Transform3D(Basis(), Vector3(p.x, y + 0.6 + Tuning.POND_SHORE_CAMERA_ROOM, p.y))
			if not space.intersect_shape(view_query, 1).is_empty():
				continue
			if _near_visual_building(p):
				continue
			var d: float = Vector2(pos.x, pos.z).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = Vector3(p.x, y, p.y)
	return best if best_d < INF else Vector3(Layout.BRIDGE_CENTER.x, 0.0, Layout.BRIDGE_CENTER.z - 3.0)


func _near_visual_building(p: Vector2) -> bool:
	var main: Node = get_tree().current_scene
	var spawner: Object = main.get(&"spawner") if main != null else null
	if spawner == null:
		return false
	for b: Dictionary in spawner.get(&"buildings"):
		var aabb: AABB = b["aabb"]
		var slot: Node3D = b["slot"]
		var r := Rect2(Vector2(slot.position.x + aabb.position.x, slot.position.z + aabb.position.z), Vector2(aabb.size.x, aabb.size.z)).grow(Tuning.POND_SHORE_CAMERA_ROOM)
		if r.has_point(p):
			return true
	return false
