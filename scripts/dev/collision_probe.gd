extends Node3D

## Dev check (`-- --probe-collision`): drives test capsules against the world colliders and prints results.

const TESTS: Array = [
	["to_sea_east", Vector3(12.5, 0.1, 0.0), Vector3(1, 0, 0)],
	["to_sea_north", Vector3(0.0, 0.1, -12.5), Vector3(0, 0, -1)],
	["into_pond", Vector3(-3.0, 0.1, 11.2), Vector3(0, 0, 1)],
	["over_bridge", Vector3(0.0, 0.1, 10.6), Vector3(0, 0, 1)],
	["into_town_hall", Vector3(0.0, 0.1, 3.0), Vector3(0, 0, -1)],
	["gate_corridor", Vector3(-6.5, 0.1, 0.0), Vector3(1, 0, 0)],
]

var _bodies: Array[CharacterBody3D] = []
var _frames: int = 0
var _max_y: Array[float] = []


func _ready() -> void:
	for t: Array in TESTS:
		var body := CharacterBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 1 | 2 | 16
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.0
		cs.shape = cap
		cs.position.y = 0.5
		body.add_child(cs)
		body.position = t[1]
		add_child(body)
		_bodies.append(body)
		_max_y.append(-INF)


func _physics_process(delta: float) -> void:
	_frames += 1
	for i: int in _bodies.size():
		var b: CharacterBody3D = _bodies[i]
		var dir: Vector3 = TESTS[i][2]
		b.velocity.x = dir.x * 3.0
		b.velocity.z = dir.z * 3.0
		b.velocity.y = 0.0 if b.is_on_floor() else b.velocity.y - 9.8 * delta
		b.move_and_slide()
		_max_y[i] = maxf(_max_y[i], b.position.y)
	if _frames == 240:
		var space := get_world_3d().direct_space_state
		for i: int in _bodies.size():
			var b: CharacterBody3D = _bodies[i]
			var q := PhysicsRayQueryParameters3D.create(b.position + Vector3(0, 0.5, 0), b.position + Vector3(0, -1.0, 0), 1)
			q.exclude = [b.get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			var surface: String = "-"
			if not hit.is_empty() and hit["collider"].has_method(&"surface_at"):
				surface = String(hit["collider"].call(&"surface_at", hit["position"]))
			print("[probe] %-15s end=(%.2f, %.2f, %.2f) max_y=%.2f floor=%s surface=%s" % [TESTS[i][0], b.position.x, b.position.y, b.position.z, _max_y[i], b.is_on_floor(), surface])
		get_tree().quit()
