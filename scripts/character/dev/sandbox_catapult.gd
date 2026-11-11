extends Node3D

## Sandbox stand-in for the CATAPULT agent (`--launch-demo`): a winding arm with a seat. Mounts the player,
## counts down 3 s and fires, exercising the mount / launch / crash contract. Not the real catapult.

const Sfx := preload("res://scripts/audio/sfx.gd")

const MOUNT_AT: float = 0.4
const COUNTDOWN: float = 3.0
const FIRE_TIME: float = 0.18
const FLIGHT_TIME: float = 1.9
const REST_ANGLE: float = 0.2
const WIND_ANGLE: float = 0.45
const RELEASE_ANGLE: float = -1.1

var player: CharacterBody3D
var target := Vector3(-8.0, 0.0, 4.0)
var throw_dir := Vector3(-1.0, 0.0, 0.0)

var _arm: Node3D
var _seat: Node3D
var _t: float = 0.0
var _phase: int = 0
var _next_tick: int = 4
var _creak: Node = null


func _ready() -> void:
	var look := Basis.looking_at(throw_dir, Vector3.UP)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.25, 0.5)
	base.mesh = bm
	base.material_override = _mat(Color("7A4A28"))
	base.position.y = 0.625
	base.basis = look
	add_child(base)
	_arm = Node3D.new()
	_arm.position = Vector3(0.0, 1.25, 0.0)
	add_child(_arm)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.16, 0.12, 1.7)
	beam.mesh = beam_mesh
	beam.material_override = _mat(Color("A8693A"))
	beam.position = Vector3(0.0, 0.0, 0.6)
	_arm.add_child(beam)
	_seat = Node3D.new()
	_seat.name = "Seat"
	_seat.position = Vector3(0.0, 0.16, 1.35)
	_arm.add_child(_seat)
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.42
	bowl_mesh.bottom_radius = 0.3
	bowl_mesh.height = 0.16
	bowl.mesh = bowl_mesh
	bowl.material_override = _mat(Color("7A4A28"))
	bowl.position = Vector3(0.0, -0.1, 0.0)
	_seat.add_child(bowl)
	_look = look
	_set_arm(REST_ANGLE)


var _look := Basis.IDENTITY


func _set_arm(angle: float) -> void:
	_arm.basis = _look * Basis(Vector3.RIGHT, angle)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	match _phase:
		0:
			if _t >= MOUNT_AT:
				player.call(&"mount", _seat)
				_phase = 1
				if Sfx.is_loop(&"rope_creak"):
					_creak = Sfx.play_loop(get_tree(), &"rope_creak", -10.0, global_position)
		1:
			var k: float = clampf((_t - MOUNT_AT) / COUNTDOWN, 0.0, 1.0)
			_set_arm(lerpf(REST_ANGLE, WIND_ANGLE, smoothstep(0.0, 1.0, k)))
			var left: int = ceili(COUNTDOWN - (_t - MOUNT_AT))
			if left < _next_tick and left >= 1:
				_next_tick = left
				_play(&"countdown_tick")
				print("[Catapult] %d" % left)
			if k >= 1.0:
				_phase = 2
				_play(&"countdown_go")
				_play(&"catapult_fire")
				if _creak != null and is_instance_valid(_creak):
					_creak.call(&"stop", 0.2)
		2:
			var f: float = clampf((_t - MOUNT_AT - COUNTDOWN) / FIRE_TIME, 0.0, 1.0)
			_set_arm(lerpf(WIND_ANGLE, RELEASE_ANGLE, f * f))
			if f >= 1.0:
				var g: float = player.call(&"launch_gravity")
				var p0: Vector3 = _seat.global_position
				var v: Vector3 = (target - p0) / FLIGHT_TIME
				v.y = (target.y - p0.y + 0.5 * g * FLIGHT_TIME * FLIGHT_TIME) / FLIGHT_TIME
				player.call(&"launch", v)
				print("[Catapult] launch v=%s" % v)
				_phase = 3
		3:
			_set_arm(lerpf(RELEASE_ANGLE, REST_ANGLE, clampf((_t - MOUNT_AT - COUNTDOWN - FIRE_TIME) / 1.2, 0.0, 1.0)))


func _play(preset: StringName) -> void:
	if Sfx.has_preset(preset):
		Sfx.play(get_tree(), preset)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
