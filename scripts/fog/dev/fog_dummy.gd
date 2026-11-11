extends CharacterBody3D

## Stand-in body for the fog sandbox: figure eight, alternating walk and run, periodic jumps.
## Drives the fog only through a FogAgitator child, exactly like a real character would.

const Agitator := preload("res://scripts/fog/fog_agitator.gd")

const WALK_SPEED: float = 2.1
const RUN_SPEED: float = 4.6
const JUMP_VELOCITY: float = 5.2
const GRAVITY: float = 14.0
const RADIUS: float = 4.6
const WALK_TIME: float = 3.0
const RUN_TIME: float = 4.0
const IDLE_TIME: float = 1.6

var mode: String = "cycle" # cycle | walk | run | jump | hop | idle | runstop (run 4 s, jump, then rest)
var center := Vector3.ZERO
var jump_period: float = 2.6

var _t: float = 0.0
var _clock: float = 0.0
var _jump_clock: float = 0.0
var _visual: Node3D


func _init() -> void:
	name = "FogDummy"
	collision_layer = 4
	collision_mask = 1 | 2
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.5
	add_child(col)
	_visual = Node3D.new()
	add_child(_visual)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("F2803A")
	mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 0.8
	body.mesh = cap
	body.material_override = mat
	body.position.y = 0.4
	_visual.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	head.mesh = sph
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("FFD7B0")
	head.material_override = head_mat
	head.position.y = 0.9
	_visual.add_child(head)
	add_child(Agitator.new())


func _physics_process(delta: float) -> void:
	_clock += delta
	var gait: String = mode
	if mode == "cycle":
		var k: float = fmod(_clock, WALK_TIME + RUN_TIME + IDLE_TIME)
		gait = "walk" if k < WALK_TIME else ("run" if k < WALK_TIME + RUN_TIME else "idle")
	elif mode == "runstop":
		gait = "jump" if _clock < RUN_TIME else "idle"
	var speed: float = 0.0
	if gait == "walk":
		speed = WALK_SPEED
	elif gait == "run" or gait == "jump":
		speed = RUN_SPEED
	var hv := Vector3.ZERO
	if speed > 0.0:
		var guard: int = 0
		while _flat(_curve(_t) - global_position).length() < 1.2 and guard < 200:
			_t += 0.02
			guard += 1
		hv = _flat(_curve(_t) - global_position).normalized() * speed
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	cur = cur.move_toward(hv, 18.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	if is_on_floor():
		velocity.y = 0.0
		_jump_clock += delta
		if (gait == "jump" or gait == "hop" or mode == "cycle" and gait != "idle") and _jump_clock >= jump_period:
			_jump_clock = 0.0
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if cur.length() > 0.1:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(cur.x, cur.z), 1.0 - exp(-10.0 * delta))


func _curve(t: float) -> Vector3:
	return center + Vector3(RADIUS * sin(t), 0.0, RADIUS * 0.62 * sin(2.0 * t))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
