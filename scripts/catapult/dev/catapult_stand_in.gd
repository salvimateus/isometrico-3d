extends CharacterBody3D

## Sandbox double of the player with the CHARACTER catapult contract: mount(seat), launch(velocity),
## is_mounted(), is_launched(), launch_gravity(), signals launch_landed / control_restored.

signal launch_landed(position: Vector3)
signal control_restored()

const GRAVITY: float = 15.0
const WALK_SPEED: float = 4.0
const HOP_TIME: float = 0.35
const HOP_HEIGHT: float = 0.6
const DIZZY_TIME: float = 1.6

enum Mode { FREE, HOP, MOUNTED, FLYING, DIZZY }

var _mode: Mode = Mode.FREE
var _seat: Node3D
var _hop_from := Vector3.ZERO
var _t: float = 0.0
var _rig: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _spin := Vector3.ZERO


func _init() -> void:
	name = "StandInPlayer"
	collision_layer = 4
	collision_mask = 1 | 2
	add_to_group(&"player")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.5
	add_child(col)
	_rig = Node3D.new()
	_rig.position.y = 0.5
	add_child(_rig)
	var skin := _mat(Color("F2B98A"))
	var tunic := _mat(Color("3E7FD1"))
	var steel := _mat(Color("B9C0CC"))
	var beard := _mat(Color("E07A2E"))
	_part(_rig, _capsule(0.24, 0.6), Vector3(0, -0.02, 0), tunic)
	_part(_rig, _sphere(0.2), Vector3(0, 0.38, 0), skin)
	_part(_rig, _sphere(0.21), Vector3(0, 0.44, 0), steel)
	_part(_rig, _sphere(0.13), Vector3(0, 0.3, 0.14), beard)
	for s: float in [-1.0, 1.0]:
		var horn := _part(_rig, _cone(0.05, 0.22), Vector3(0.2 * s, 0.56, 0), _mat(Color("F3EBD8")))
		horn.rotation.z = -0.7 * s
		var arm := Node3D.new()
		arm.position = Vector3(0.27 * s, 0.14, 0)
		_rig.add_child(arm)
		_part(arm, _capsule(0.07, 0.36), Vector3(0, -0.16, 0), skin)
		_arms.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * s, -0.28, 0)
		_rig.add_child(leg)
		_part(leg, _capsule(0.08, 0.3), Vector3(0, -0.12, 0), _mat(Color("6B4A2E")))
		_legs.append(leg)


func mount(seat: Node3D) -> void:
	_seat = seat
	_mode = Mode.HOP
	_t = 0.0
	_hop_from = global_position
	velocity = Vector3.ZERO


func launch(v: Vector3) -> void:
	_mode = Mode.FLYING
	_seat = null
	_t = 0.0
	velocity = v
	collision_mask = 1
	_spin = Vector3(randf_range(5.0, 8.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))


func is_mounted() -> bool:
	return _mode == Mode.HOP or _mode == Mode.MOUNTED


func is_launched() -> bool:
	return _mode == Mode.FLYING or _mode == Mode.DIZZY


func launch_gravity() -> float:
	return GRAVITY


func _physics_process(delta: float) -> void:
	_t += delta
	match _mode:
		Mode.FREE:
			var dir := Vector3.ZERO
			if InputMap.has_action(&"player_move_left"):
				var v2: Vector2 = Input.get_vector(&"player_move_left", &"player_move_right", &"player_move_forward", &"player_move_back")
				dir = Vector3(v2.x, 0.0, v2.y).rotated(Vector3.UP, PI * 0.25)
			velocity.x = dir.x * WALK_SPEED
			velocity.z = dir.z * WALK_SPEED
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
			elif InputMap.has_action(&"player_jump") and Input.is_action_just_pressed(&"player_jump"):
				velocity.y = 6.0
			move_and_slide()
		Mode.HOP:
			var k: float = clampf(_t / HOP_TIME, 0.0, 1.0)
			var p: Vector3 = _hop_from.lerp(_seat.global_position, k)
			p.y += sin(k * PI) * HOP_HEIGHT
			global_position = p
			if k >= 1.0:
				_mode = Mode.MOUNTED
		Mode.MOUNTED:
			global_transform = _seat.global_transform
		Mode.FLYING:
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if is_on_floor() and _t > 0.2:
				_mode = Mode.DIZZY
				_t = 0.0
				velocity = Vector3.ZERO
				collision_mask = 1 | 2
				rotation = Vector3(0.0, rotation.y, 0.0)
				launch_landed.emit(global_position)
		Mode.DIZZY:
			if _t >= DIZZY_TIME:
				_mode = Mode.FREE
				control_restored.emit()


func _process(delta: float) -> void:
	var clock: float = Time.get_ticks_msec() * 0.001
	match _mode:
		Mode.FLYING:
			_rig.rotation += _spin * delta
			for i: int in 2:
				_arms[i].rotation.x = sin(clock * 22.0 + i * PI) * 2.2
				_arms[i].rotation.z = (1.0 if i == 0 else -1.0) * (1.6 + 0.6 * sin(clock * 17.0))
				_legs[i].rotation.x = sin(clock * 19.0 + i * PI) * 1.2
		Mode.MOUNTED, Mode.HOP:
			_rig.rotation = Vector3(0.0, 0.0, sin(clock * 30.0) * 0.06)
			for i: int in 2:
				_arms[i].rotation = Vector3(-2.6 + sin(clock * 25.0 + i) * 0.25, 0.0, 0.0)
				_legs[i].rotation = Vector3(-1.3, 0.0, 0.0)
		Mode.DIZZY:
			_rig.rotation = Vector3(sin(clock * 3.0) * 0.15, 0.0, cos(clock * 3.0) * 0.15)
			for i: int in 2:
				_arms[i].rotation = Vector3.ZERO
				_legs[i].rotation = Vector3.ZERO
		_:
			_rig.rotation = Vector3.ZERO
			for i: int in 2:
				_arms[i].rotation = Vector3.ZERO
				_legs[i].rotation = Vector3.ZERO


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


static func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	return m


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
