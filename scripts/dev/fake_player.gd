extends CharacterBody3D

## Dev stand-in for the CHARACTER player (`-- --fake-player`): walks a loop to exercise camera follow and collisions.

var _t: float = 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.0
	cs.shape = cap
	cs.position.y = 0.5
	add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.0
	mi.mesh = mesh
	mi.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("FF7A3C")
	mi.material_override = mat
	add_child(mi)


func is_moving() -> bool:
	return _t > 0.3


func _physics_process(delta: float) -> void:
	_t += delta
	var dir := Vector3(1, 0, 0.35).normalized() if _t > 0.3 else Vector3.ZERO
	velocity.x = dir.x * 4.0
	velocity.z = dir.z * 4.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
