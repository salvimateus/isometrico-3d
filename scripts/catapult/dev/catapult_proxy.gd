extends RefCounted

## Stand-in catapult model with the BUILDINGS contract nodes (ArmPivot, ArmPivot/Seat, ArmPivot/Bucket,
## Winch, CountdownAnchor, meta fire_angle_deg), used by the sandbox until building_factory ships one.

const FIRE_ANGLE_DEG: float = 115.0
const PIVOT := Vector3(0.0, 1.15, 0.35)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Catapult"
	root.set_meta(&"fire_angle_deg", FIRE_ANGLE_DEG)
	var wood := _mat(Color("A8693A"))
	var dark_wood := _mat(Color("7A4A28"))
	var iron := _mat(Color("5A5F6B"), 0.5, 0.6)
	var rope := _mat(Color("D9C08A"))

	for x: float in [-1.15, 1.15]:
		_box(root, Vector3(x, 0.14, 0.0), Vector3(0.28, 0.28, 3.0), dark_wood)
	for z: float in [-1.2, 0.0, 1.2]:
		_box(root, Vector3(0.0, 0.3, z), Vector3(2.5, 0.2, 0.26), wood)
	for x: float in [-0.95, 0.95]:
		var a := _box(root, Vector3(x, 0.7, PIVOT.z - 0.35), Vector3(0.2, 1.35, 0.2), wood)
		a.rotation.x = deg_to_rad(-18.0)
		var b := _box(root, Vector3(x, 0.7, PIVOT.z + 0.35), Vector3(0.2, 1.35, 0.2), wood)
		b.rotation.x = deg_to_rad(18.0)
	_box(root, Vector3(0.0, 2.25, PIVOT.z + 0.55), Vector3(2.0, 0.22, 0.22), dark_wood)
	for x: float in [-0.95, 0.95]:
		_box(root, Vector3(x, 1.75, PIVOT.z + 0.55), Vector3(0.16, 1.0, 0.16), wood)
	for x: float in [-1.15, 1.15]:
		for z: float in [-1.3, 1.3]:
			_cyl(root, Vector3(x * 1.06, 0.25, z), 0.25, 0.12, iron, Vector3(0.0, 0.0, PI * 0.5))

	var arm := Node3D.new()
	arm.name = "ArmPivot"
	arm.position = PIVOT
	root.add_child(arm)
	_cyl(arm, Vector3.ZERO, 0.11, 2.0, iron, Vector3(0.0, 0.0, PI * 0.5))
	var beam := _box(arm, Vector3(0.0, -0.32, -0.95), Vector3(0.24, 0.2, 2.2), wood)
	beam.rotation.x = deg_to_rad(16.0)
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	bucket.position = Vector3(0.0, -0.62, -1.95)
	arm.add_child(bucket)
	_box(bucket, Vector3(0.0, -0.1, 0.0), Vector3(0.9, 0.12, 0.9), dark_wood)
	for s: float in [-1.0, 1.0]:
		_box(bucket, Vector3(0.45 * s, 0.08, 0.0), Vector3(0.1, 0.36, 0.9), wood)
		_box(bucket, Vector3(0.0, 0.08, 0.45 * s), Vector3(0.9, 0.36, 0.1), wood)
	var seat := Marker3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0.0, -0.66, -1.95)
	seat.rotation.y = PI
	arm.add_child(seat)

	var winch := Node3D.new()
	winch.name = "Winch"
	winch.position = Vector3(0.0, 0.62, -1.05)
	root.add_child(winch)
	_cyl(winch, Vector3.ZERO, 0.2, 1.6, rope, Vector3(0.0, 0.0, PI * 0.5))
	for s: float in [-1.0, 1.0]:
		_cyl(winch, Vector3(0.82 * s, 0.0, 0.0), 0.3, 0.08, dark_wood, Vector3(0.0, 0.0, PI * 0.5))
		for k: int in 4:
			var spoke := _box(winch, Vector3(0.9 * s, 0.0, 0.0), Vector3(0.06, 0.9, 0.08), wood)
			spoke.rotation.x = k * PI * 0.25
	for x: float in [-0.95, 0.95]:
		_box(root, Vector3(x, 0.45, -1.05), Vector3(0.14, 0.5, 0.14), wood)

	var anchor := Marker3D.new()
	anchor.name = "CountdownAnchor"
	anchor.position = Vector3(0.0, 4.4, 0.0)
	root.add_child(anchor)
	return root


static func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, pos: Vector3, radius: float, height: float, m: Material, rot: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _mat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
