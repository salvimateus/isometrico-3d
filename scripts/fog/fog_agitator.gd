extends Node

## Optional helper: add as a child of a CharacterBody3D and it drives the fog API from the body's
## motion (wake while moving, puff on takeoff, ring on landing). Finds the field by group &"fog_field".

const FT := preload("res://scripts/fog/fog_tuning.gd")

var _body: CharacterBody3D
var _field: Node
var _was_on_floor: bool = true
var _air_min_vy: float = 0.0
var _clock: float = 0.0
var _air_time: float = 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	process_physics_priority = 100 # after the body moved this frame


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if not is_instance_valid(_field):
		_field = get_tree().get_first_node_in_group(&"fog_field")
		if _field == null:
			return
	_clock += delta
	var pos: Vector3 = _body.global_position
	var vel: Vector3 = _body.velocity
	var on_floor: bool = _body.is_on_floor()

	if not on_floor:
		_air_min_vy = minf(_air_min_vy, vel.y)
		_air_time += delta
	if _was_on_floor and not on_floor and vel.y > 0.5:
		_field.add_burst(pos, FT.TAKEOFF_STRENGTH, FT.TAKEOFF_RADIUS)
	elif not _was_on_floor and on_floor and _air_time >= FT.LANDING_MIN_AIR_TIME:
		var k: float = clampf(-_air_min_vy / FT.LANDING_FALL_SPEED_FULL, 0.0, 1.0)
		_field.add_burst(pos, lerpf(FT.LANDING_STRENGTH_MIN, FT.LANDING_STRENGTH_MAX, k), FT.LANDING_RADIUS)
	if on_floor:
		_air_min_vy = 0.0
		_air_time = 0.0
	_was_on_floor = on_floor

	if pos.y > FT.AGITATE_MAX_HEIGHT:
		return
	var hv := Vector3(vel.x, 0.0, vel.z)
	var speed: float = hv.length()
	if speed < 0.05:
		return
	var run: float = clampf(speed / FT.AGITATE_RUN_SPEED, 0.0, 1.0)
	var radius: float = lerpf(FT.AGITATE_RADIUS_WALK, FT.AGITATE_RADIUS_RUN, run)
	var height_fade: float = 1.0 - clampf(pos.y / FT.AGITATE_MAX_HEIGHT, 0.0, 1.0)
	_field.add_impulse(pos, hv * height_fade, radius)
	if run > 0.6:
		# Alternating side kicks seed the staggered vortex street of a running wake.
		var fwd: Vector3 = hv / speed
		var side := Vector3(-fwd.z, 0.0, fwd.x)
		var s: float = sin(_clock * TAU * FT.AGITATE_SIDE_FREQUENCY)
		var sgn: float = signf(s)
		var kick: Vector3 = (side * sgn * FT.AGITATE_SIDE_KICK - fwd * 0.2) * speed * absf(s) * height_fade
		_field.add_impulse(pos - fwd * 0.25 + side * sgn * FT.AGITATE_SIDE_OFFSET, kick, radius * 0.7)
