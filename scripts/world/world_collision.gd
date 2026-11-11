extends RefCounted

## Physics for the walkable world. Layer 1: ground and bridge deck. Layer 5 (value 16): invisible
## barriers (island rim, pond rim); bridge rails are real geometry and stay on layer 1 that walking bodies collide with and flying ones ignore.
## Layer 2: obstacles (trees, big rocks); buildings and walls add their own layer-2 bodies.

const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const SurfaceBody := preload("res://scripts/world/surface_body.gd")
const GroundData := preload("res://scripts/world/ground_data.gd")
const NatureBody := preload("res://scripts/world/nature_body.gd")

const LAYER_GROUND: int = 1
const LAYER_OBSTACLE: int = 2
const LAYER_BARRIER: int = 16
const RIM_INSET: float = 0.55
const BARRIER_HEIGHT: float = 3.0


static func build(parent: Node3D, ground_data: GroundData, ground_mesh: Mesh, bridge_length: float, bridge_width: float, bridge_rise: float, shakers: Array[Dictionary], rocks: Array[Vector3]) -> void:
	var ground := SurfaceBody.new()
	ground.ground = ground_data
	ground.name = "WorldCollision"
	ground.collision_layer = LAYER_GROUND
	ground.collision_mask = 0
	parent.add_child(ground)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = ground_mesh.create_trimesh_shape()
	ground.add_child(floor_shape)
	var barriers := StaticBody3D.new()
	barriers.name = "WalkBarriers"
	barriers.collision_layer = LAYER_BARRIER
	barriers.collision_mask = 0
	parent.add_child(barriers)
	_island_rim(barriers)
	_pond_rim(barriers, bridge_width)
	var bridge := SurfaceBody.new()
	bridge.name = "BridgeCollision"
	bridge.fixed_surface = &"wood"
	bridge.collision_layer = LAYER_GROUND
	bridge.collision_mask = 0
	parent.add_child(bridge)
	_bridge(bridge, barriers, bridge_length, bridge_width, bridge_rise)

	var obstacles := Node3D.new()
	obstacles.name = "NatureObstacles"
	parent.add_child(obstacles)
	for s: Dictionary in shakers:
		var scale: float = s["scale"]
		var is_tree: bool = s["kind"] == &"tree"
		if not is_tree and scale < 1.05:
			continue
		var body := _nature_body(obstacles, s["pos"], (0.28 if is_tree else 0.42) * scale, (2.0 if is_tree else 0.7) * scale)
		body.multimesh = s["multimesh"]
		body.index = s["index"]
		body.base_custom = s["custom"]
		body.top_height = (1.5 if is_tree else 0.5) * scale
	for r: Vector3 in rocks:
		if r.z >= 0.9:
			var rock := _nature_body(obstacles, Vector2(r.x, r.y), 0.38 * r.z, 0.8 * r.z)
			rock.leafy = false


static func _nature_body(parent: Node3D, p: Vector2, radius: float, height: float) -> NatureBody:
	var body := NatureBody.new()
	body.collision_layer = LAYER_OBSTACLE
	body.collision_mask = 0
	body.position = Vector3(p.x, Shape.ground_height(p), p.y)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	body.add_child(cs)
	parent.add_child(body)
	return body


static func _wall_segment(body: StaticBody3D, a: Vector2, b: Vector2, y: float, height: float, thickness: float) -> void:
	var len: float = a.distance_to(b)
	if len < 0.01:
		return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(thickness, height, len + 0.05)
	cs.shape = box
	var mid: Vector2 = (a + b) * 0.5
	var dir: Vector2 = (b - a) / len
	cs.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, y + height * 0.5, mid.y))
	body.add_child(cs)


static func _island_rim(body: StaticBody3D) -> void:
	var segs: int = 96
	var prev: Vector2 = Vector2.ZERO
	for i: int in segs + 1:
		var theta: float = TAU * float(i % segs) / segs
		var p: Vector2 = Shape.outline_point(theta) - Vector2(cos(theta), sin(theta)) * RIM_INSET
		if i > 0:
			_wall_segment(body, prev, p, -1.0, BARRIER_HEIGHT, 0.4)
		prev = p


static func _pond_rim(body: StaticBody3D, bridge_width: float) -> void:
	var gap: float = bridge_width * 0.5 + 0.05
	for lobe: Vector3 in Layout.POND_LOBES:
		var segs: int = 40
		var r: float = lobe.z + 0.05
		var prev: Vector2 = Vector2.ZERO
		var prev_ok: bool = false
		for i: int in segs + 1:
			var a: float = TAU * float(i) / segs
			var p := Vector2(lobe.x, lobe.y) + Vector2(cos(a), sin(a)) * r
			var ok: bool = Layout.pond_sdf(p) > -0.2 and absf(p.x - Layout.BRIDGE_CENTER.x) > gap
			if i > 0 and ok and prev_ok:
				_wall_segment(body, prev, p, -1.0, BARRIER_HEIGHT, 0.25)
			prev = p
			prev_ok = ok


static func _bridge(body: StaticBody3D, barriers: StaticBody3D, length: float, width: float, rise: float) -> void:
	var c: Vector3 = Layout.BRIDGE_CENTER
	var steps: int = 10
	var top_rise: float = rise + 0.1
	for i: int in steps:
		var t0: float = float(i) / steps
		var t1: float = float(i + 1) / steps
		var p0 := Vector3(0, top_rise * sin(PI * t0), (t0 - 0.5) * (length + 0.6))
		var p1 := Vector3(0, top_rise * sin(PI * t1), (t1 - 0.5) * (length + 0.6))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.12, p0.distance_to(p1) + 0.04)
		cs.shape = box
		var basis := Basis.looking_at(p1 - p0, Vector3.UP)
		cs.transform = Transform3D(basis, c + (p0 + p1) * 0.5 - basis.y * 0.06)
		body.add_child(cs)
	for side: float in [-1.0, 1.0]:
		var x: float = c.x + side * (width * 0.5 + 0.02)
		_wall_segment(body, Vector2(x, c.z - length * 0.5), Vector2(x, c.z + length * 0.5), -0.5, 1.15, 0.14)
