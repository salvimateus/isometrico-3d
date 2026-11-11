extends Node3D

## Catapult ride: mount prompt, juicy 3 s countdown with winch tension, arm whip that launches the
## player onto a validated landing point, flight trail and landing marker, landing burst and rearm.
## Child of the catapult (origin at the footprint center); see catapult_factory.gd.

signal fired(target: Vector3)

const T := preload("res://scripts/catapult/catapult_tuning.gd")
const Ballistics := preload("res://scripts/catapult/catapult_ballistics.gd")
const Prompt := preload("res://scripts/catapult/catapult_prompt.gd")
const Countdown := preload("res://scripts/catapult/catapult_countdown.gd")
const Dust := preload("res://scripts/catapult/catapult_dust.gd")
const GroundRing := preload("res://scripts/catapult/catapult_ground_ring.gd")
const FlightFx := preload("res://scripts/catapult/catapult_flight_fx.gd")

enum State { READY, MOUNTING, COUNTDOWN, FIRING, REARMING }

## Landing distance range along the catapult's +Z; the integrator may override per catapult.
var launch_distance_min: float = T.LAUNCH_DISTANCE_MIN
var launch_distance_max: float = T.LAUNCH_DISTANCE_MAX
var rng := RandomNumberGenerator.new()

var _catapult: Node3D
var _arm: Node3D
var _seat: Node3D
var _winch: Node3D
var _anchor: Node3D
var _bucket: Node3D
var _bucket_scale := Vector3.ONE
var _footprint_half := T.DEFAULT_FOOTPRINT * 0.5
var _fire_angle: float = deg_to_rad(T.DEFAULT_FIRE_ANGLE_DEG)

var _state: State = State.READY
var _state_time: float = 0.0
var _arm_angle: float = 0.0
var _arm_vel: float = 0.0
var _arm_display: float = 0.0
var _tremble_phase: float = 0.0
var _winch_vel: float = 0.0
var _squash_age: float = 99.0
var _countdown_step: int = -1
var _dust_timer: float = 0.0
var _contact: bool = false
var _contact_time: float = 0.0
var _released: bool = false
var _go_left: bool = false
var _target := Vector3.ZERO
var _water_target: bool = false
var _rearm_settled: bool = false

var _player: Node3D
var _player_lookup: float = 0.0
var _camera_rig: Node
var _sfx: Script
var _haptics: Script
var _mobile: bool = false
var _last_touch: bool = false
var _creak: Node

var _flying: bool = false
var _flight_timeout: float = 0.0

var _prompt: Node3D
var _countdown: Node3D
var _dust: Node3D
var _target_ring: MeshInstance3D
var _shock_ring: MeshInstance3D
var _flight_fx: Node3D


## Called by catapult_factory.attach before the controller enters the tree.
func setup(catapult: Node3D) -> void:
	name = "CatapultController"
	_catapult = catapult
	_arm = catapult.get_node_or_null(^"ArmPivot") as Node3D
	_seat = catapult.get_node_or_null(^"ArmPivot/Seat") as Node3D
	_winch = catapult.get_node_or_null(^"Winch") as Node3D
	_anchor = catapult.get_node_or_null(^"CountdownAnchor") as Node3D
	if _arm == null or _seat == null:
		push_error("catapult_controller: '%s' lacks ArmPivot or ArmPivot/Seat" % catapult.name)
	if _arm != null:
		_bucket = _arm.get_node_or_null(^"Bucket") as Node3D
		if _bucket != null:
			_bucket_scale = _bucket.scale
	_fire_angle = deg_to_rad(float(catapult.get_meta(&"fire_angle_deg", T.DEFAULT_FIRE_ANGLE_DEG)))
	_footprint_half = _footprint() * 0.5
	rng.randomize()

	var anchor_local := Vector3(0.0, 4.0, 0.0)
	if _anchor != null:
		anchor_local = _relative_xform(_anchor, catapult).origin
	_countdown = Countdown.new()
	_countdown.position = anchor_local + Vector3.UP * T.NUMBER_HEIGHT_OFFSET
	add_child(_countdown)
	_prompt = Prompt.new()
	_prompt.position = anchor_local + Vector3.UP * T.PROMPT_HEIGHT_OFFSET
	add_child(_prompt)
	_dust = Dust.new()
	add_child(_dust)
	_target_ring = GroundRing.new()
	add_child(_target_ring)
	_shock_ring = GroundRing.new()
	add_child(_shock_ring)
	_flight_fx = FlightFx.new()
	add_child(_flight_fx)


func _ready() -> void:
	if ResourceLoader.exists(T.SFX_PATH):
		_sfx = load(T.SFX_PATH) as Script
	_warm_sfx()
	if ResourceLoader.exists(T.HAPTICS_PATH):
		_haptics = load(T.HAPTICS_PATH) as Script
	_mobile = OS.has_feature("mobile")
	if ResourceLoader.exists(T.QUALITY_PATH):
		var quality: Script = load(T.QUALITY_PATH) as Script
		if quality != null and quality.has_method(&"is_mobile"):
			_mobile = bool(quality.call(&"is_mobile"))
	_prompt.call(&"set_touch", _mobile)
	_prewarm_visuals.call_deferred()


## Fires every effect once under the catapult (hidden by the ground; depth-test-free UI fully
## transparent) so materials and particle meshes are built and compiled at load, not on the first ride.
func _prewarm_visuals() -> void:
	if not is_inside_tree():
		return
	var hidden: Vector3 = _catapult.global_position + Vector3.DOWN * T.PREWARM_DEPTH
	_dust.call(&"puff", hidden, 2, 0.1, 0.05)
	_dust.call(&"wave", hidden)
	_dust.call(&"spray", hidden)
	_target_ring.call(&"show_target", hidden, 0.1)
	_shock_ring.call(&"shockwave", hidden)
	var dummy := Node3D.new()
	dummy.top_level = true
	add_child(dummy)
	dummy.global_position = hidden
	_flight_fx.call(&"follow", dummy)
	_countdown.call(&"prewarm", T.PREWARM_FRAMES)
	for i: int in T.PREWARM_FRAMES:
		await get_tree().process_frame
	_flight_fx.call(&"release")
	dummy.queue_free()


func _warm_sfx() -> void:
	if _sfx == null:
		return
	var presets: Array[StringName] = []
	for p: StringName in T.SFX_WARM:
		if bool(_sfx.call(&"has_preset", p)):
			presets.append(p)
	_sfx.call(&"warm", presets)


# --- Public API ---

## Mounts the nearby player (mouse click on the catapult, interact action, jump into the bucket).
## Tracks whether the last real input was a touch (mouse events are ignored: touch emulates them).
func _input(event: InputEvent) -> void:
	var touch: bool = _last_touch
	if event is InputEventScreenTouch:
		touch = true
	elif event is InputEventKey or event is InputEventJoypadButton:
		touch = false
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		touch = false
	if touch != _last_touch:
		_last_touch = touch
		_prompt.call(&"set_touch", _mobile or touch)


func try_mount() -> bool:
	if _state != State.READY or _seat == null:
		return false
	var p: Node3D = _get_player()
	if p == null or _player_busy(p):
		return false
	if _footprint_distance(p.global_position) > T.CLICK_MOUNT_RANGE:
		return false
	_begin_mount(p)
	return true


func is_ready() -> bool:
	return _state == State.READY


# --- Simulation ---

func _physics_process(delta: float) -> void:
	_state_time += delta
	var p: Node3D = _get_player()
	match _state:
		State.READY:
			_update_ready(p)
		State.MOUNTING:
			_update_mounting(p)
		State.COUNTDOWN:
			_update_countdown(p, delta)
		State.FIRING:
			_update_firing(p, delta)
		State.REARMING:
			_update_rearm(delta)
	_integrate_arm(delta)
	_update_flight(delta)


func _set_state(s: State) -> void:
	_state = s
	_state_time = 0.0


func _update_ready(p: Node3D) -> void:
	var near: bool = false
	if p != null and not _player_busy(p):
		near = _footprint_distance(p.global_position) <= T.PROMPT_RANGE
		if _jumped_into_bucket(p):
			_begin_mount(p)
			return
		if near and InputMap.has_action(T.INTERACT_ACTION) and Input.is_action_just_pressed(T.INTERACT_ACTION):
			_begin_mount(p)
			return
	_prompt.call(&"set_shown", near)


func _begin_mount(p: Node3D) -> void:
	_prompt.call(&"set_shown", false)
	_set_state(State.MOUNTING)
	if p.has_method(&"mount"):
		p.call(&"mount", _seat)
	_play(&"ui_pop", -6.0, 0.9)


func _update_mounting(p: Node3D) -> void:
	var arrived: bool = p != null and p.global_position.distance_to(_seat.global_position) < T.MOUNT_SETTLE_DISTANCE
	if (_state_time >= T.MOUNT_SETTLE_MIN and arrived) or _state_time >= T.MOUNT_SETTLE_MAX:
		_arm_vel += T.MOUNT_DIP_IMPULSE
		_squash_age = 0.0
		_play(&"thud", -8.0, 0.8)
		_dust.call(&"puff", _seat.global_position + Vector3.DOWN * 0.2, 6, 0.8, T.DUST_SIZE * 0.6)
		_countdown_step = -1
		_dust_timer = 0.0
		_start_creak(T.CREAK_DB_START)
		_set_state(State.COUNTDOWN)


func _update_countdown(_p: Node3D, delta: float) -> void:
	var total: float = T.COUNTDOWN_STEPS * T.COUNTDOWN_STEP_TIME
	var k: float = clampf(_state_time / total, 0.0, 1.0)
	var step: int = int(floor(_state_time / T.COUNTDOWN_STEP_TIME))
	if step != _countdown_step and step < T.COUNTDOWN_STEPS:
		_countdown_step = step
		var color: Color = T.NUMBER_COLORS[mini(step, T.NUMBER_COLORS.size() - 1)]
		_countdown.call(&"show_step", str(T.COUNTDOWN_STEPS - step), color, 1.0 + 0.12 * step)
		_play(&"countdown_tick", T.SFX_TICK_DB, 1.0 + T.SFX_TICK_PITCH_STEP * step)
		var growth: float = 1.0 + T.RUMBLE_TICK_GROWTH * step
		_rumble(T.RUMBLE_TICK.x * growth, T.RUMBLE_TICK.y * growth, T.RUMBLE_TICK.z)
		_trauma(T.TRAUMA_TICK * growth)
	_winch_vel = lerpf(T.WINCH_SPEED_START, T.WINCH_SPEED_END, k)
	_trauma(lerpf(T.TRAUMA_RATE_START, T.TRAUMA_RATE_END, k * k) * delta)
	if _creak != null and is_instance_valid(_creak):
		_creak.call(&"set_volume_db", lerpf(T.CREAK_DB_START, T.CREAK_DB_END, k))
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = lerpf(T.DUST_INTERVAL_START, T.DUST_INTERVAL_END, k)
		_dust.call(&"puff", _base_point(), 3 + int(5.0 * k), 0.5 + 0.9 * k, T.DUST_SIZE * (0.5 + 0.6 * k))
	if _state_time >= total:
		_countdown.call(&"show_step", T.GO_TEXT, T.GO_COLOR, T.GO_SCALE)
		_play(&"countdown_go", T.SFX_GO_DB, 1.0)
		_stop_creak()
		_begin_fire()


func _begin_fire() -> void:
	_set_state(State.FIRING)
	_contact = false
	_released = false
	_go_left = false
	_winch_vel = T.WINCH_UNSPOOL_SPEED
	_target = _pick_target()


func _update_firing(p: Node3D, delta: float) -> void:
	if not _go_left and _state_time >= T.GO_HOLD:
		_go_left = true
		_countdown.call(&"leave")
	_winch_vel = lerpf(_winch_vel, 0.0, 1.0 - exp(-T.WINCH_UNSPOOL_DECAY * delta))
	if not _released and _arm_angle >= _fire_angle * T.RELEASE_FRACTION:
		_released = true
		_launch(p)
	if not _contact and _arm_angle >= _fire_angle:
		_contact = true
		_contact_time = _state_time
		_on_arm_contact()
	if _contact and _state_time - _contact_time >= T.FIRE_HOLD:
		_rearm_settled = false
		_start_creak(T.REARM_CREAK_DB)
		_set_state(State.REARMING)


func _on_arm_contact() -> void:
	_play(&"catapult_fire", T.SFX_FIRE_DB, 1.0)
	_trauma(T.TRAUMA_FIRE)
	_rumble(T.RUMBLE_FIRE.x, T.RUMBLE_FIRE.y, T.RUMBLE_FIRE.z)
	var fwd: Vector3 = _forward()
	var base: Vector3 = _catapult.global_position
	_dust.call(&"wave", base)
	for i: int in 4:
		_dust.call(&"puff", _base_point(), 10, 2.4, T.DUST_SIZE * 1.4, fwd * 3.0)
	_dust.call(&"puff", base + fwd * 1.6, 14, 3.0, T.DUST_SIZE * 1.6, fwd * 4.0)
	_fog_burst(base, 1.0, 3.0)


func _update_rearm(_delta: float) -> void:
	_winch_vel = T.REARM_WINCH_SPEED
	var k: float = clampf(_state_time / T.REARM_TIME, 0.0, 1.0)
	if k < 1.0:
		var e: float = k * k * k * (k * (k * 6.0 - 15.0) + 10.0)
		_arm_angle = lerpf(_fire_angle, 0.0, e)
		_arm_vel = 0.0
		return
	if not _rearm_settled:
		_rearm_settled = true
		_arm_angle = 0.0
		_arm_vel = -T.REARM_SETTLE_IMPULSE
		_winch_vel = 0.0
		_stop_creak()
		_play(&"thud", -6.0, 1.1)
		_dust.call(&"puff", _base_point(), 8, 1.2, T.DUST_SIZE)
		_set_state(State.READY)


func _integrate_arm(delta: float) -> void:
	if _arm == null:
		return
	var tremble: float = 0.0
	match _state:
		State.FIRING:
			if not _contact:
				_arm_vel += T.FIRE_ACCEL * delta
			else:
				_arm_vel += (-T.FIRE_STOP_STIFFNESS * (_arm_angle - _fire_angle) - T.FIRE_STOP_DAMPING * _arm_vel) * delta
			_arm_angle += _arm_vel * delta
		State.REARMING:
			pass
		_:
			var target: float = 0.0
			if _state == State.COUNTDOWN:
				var k: float = clampf(_state_time / (T.COUNTDOWN_STEPS * T.COUNTDOWN_STEP_TIME), 0.0, 1.0)
				target = deg_to_rad(T.TENSION_PULL_DEG) * k
				_tremble_phase += delta * lerpf(T.TREMBLE_FREQ_MIN, T.TREMBLE_FREQ_MAX, k)
				var amp: float = deg_to_rad(lerpf(T.TREMBLE_DEG_MIN, T.TREMBLE_DEG_MAX, k * k))
				tremble = amp * (sin(_tremble_phase * TAU) * 0.7 + sin(_tremble_phase * TAU * 2.37 + 1.3) * 0.3)
				tremble += amp * 0.4 * rng.randf_range(-1.0, 1.0)
			_arm_vel += (-T.ARM_STIFFNESS * (_arm_angle - target) - T.ARM_DAMPING * _arm_vel) * delta
			_arm_angle += _arm_vel * delta
	_arm_display = _arm_angle + tremble
	_arm.rotation.x = _arm_display
	if _winch != null:
		_winch.rotation.x = wrapf(_winch.rotation.x + _winch_vel * delta, -PI, PI)
	if _bucket != null:
		_squash_age += delta
		var s: float = T.BUCKET_SQUASH * exp(-T.BUCKET_SQUASH_DECAY * _squash_age) * cos(T.BUCKET_SQUASH_FREQ * _squash_age)
		_bucket.scale = _bucket_scale * Vector3(1.0 + s * 0.6, 1.0 - s, 1.0 + s * 0.6)


# --- Launch, flight and landing ---

func _pick_target() -> Vector3:
	var origin: Vector3 = _catapult.global_position
	_water_target = false
	var marker := get_tree().get_first_node_in_group(T.TARGET_GROUP) as Node3D
	if marker != null:
		# The pond is the target: aim at the water surface, no ground validation.
		_water_target = true
		var radius: float = float(marker.get_meta(&"radius", T.TARGET_DEFAULT_RADIUS)) * T.TARGET_JITTER_FRACTION
		var r: float = radius * sqrt(rng.randf())
		var a: float = rng.randf() * TAU
		return marker.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var yaw: float = deg_to_rad(rng.randf_range(-T.LAUNCH_YAW_JITTER_DEG, T.LAUNCH_YAW_JITTER_DEG))
	var dir: Vector3 = _forward().rotated(Vector3.UP, yaw)
	var desired: Vector3 = origin + dir * rng.randf_range(launch_distance_min, launch_distance_max)
	var space: PhysicsDirectSpaceState3D = _catapult.get_world_3d().direct_space_state
	var found: Vector3 = Ballistics.find_landing(space, desired, origin)
	if found.is_finite():
		return found
	push_warning("catapult_controller: no valid landing near %s, using the raw point" % desired)
	return Vector3(desired.x, origin.y, desired.z)


func _launch(p: Node3D) -> void:
	if p == null or not is_instance_valid(p) or not p.has_method(&"launch"):
		return
	var from: Vector3 = p.global_position
	var g: float = T.DEFAULT_GRAVITY
	if p.has_method(&"launch_gravity"):
		g = maxf(float(p.call(&"launch_gravity")), 0.1)
	var apex: float = Ballistics.pick_apex(from.y, _target.y, g)
	var vel: Vector3 = Ballistics.launch_velocity(from, _target, apex, g)
	var t: float = Ballistics.flight_time(from.y, _target.y, apex, g)
	p.call(&"launch", vel)
	if p.has_signal(&"launch_landed") and not p.is_connected(&"launch_landed", _on_landed):
		p.connect(&"launch_landed", _on_landed, CONNECT_ONE_SHOT)
	_flying = true
	_flight_timeout = t + T.LANDING_TIMEOUT_EXTRA
	_target_ring.call(&"show_target", _marker_point(_target), t)
	_flight_fx.call(&"follow", p)
	fired.emit(_target)


func _update_flight(delta: float) -> void:
	if not _flying:
		return
	_flight_timeout -= delta
	if _flight_timeout <= 0.0:
		var p: Node3D = _get_player()
		_on_landed(p.global_position if p != null else _target)


func _on_landed(pos: Vector3) -> void:
	if not _flying:
		return
	_flying = false
	var p: Node3D = _player
	if p != null and is_instance_valid(p) and p.is_connected(&"launch_landed", _on_landed):
		p.disconnect(&"launch_landed", _on_landed)
	_target_ring.call(&"dismiss")
	_flight_fx.call(&"release")
	var surface: float = _water_surface(pos)
	if surface > -INF:
		var on_water := Vector3(pos.x, surface, pos.z)
		_shock_ring.call(&"shockwave", on_water + Vector3.UP * T.WATER_RING_LIFT, T.WATER_RING_COLOR)
		_dust.call(&"spray", on_water)
	else:
		_shock_ring.call(&"shockwave", _marker_point(pos))
		_dust.call(&"wave", pos)
		_dust.call(&"puff", pos, 18, 3.2, T.DUST_SIZE * 1.8)
	_fog_burst(pos, T.FOG_BURST_STRENGTH, T.FOG_BURST_RADIUS)


## Water surface height at `pos` (water target, water_body or liquid_field), or -INF on dry ground.
func _water_surface(pos: Vector3) -> float:
	for w: Node in get_tree().get_nodes_in_group(T.WATER_GROUP):
		if w.has_method(&"surface_height_at"):
			var h: float = float(w.call(&"surface_height_at", pos))
			if h > -INF:
				return h
	var liquid: Node = get_tree().get_first_node_in_group(T.LIQUID_GROUP)
	if liquid != null and liquid.has_method(&"depth_at"):
		var depth: float = float(liquid.call(&"depth_at", pos))
		if depth > T.WATER_MIN_DEPTH:
			return pos.y + depth
	if _water_target:
		return _target.y
	return -INF


## Ground point raised to the water surface where the liquid field reports depth.
func _marker_point(p: Vector3) -> Vector3:
	if _water_target:
		return Vector3(p.x, _target.y, p.z)
	var liquid: Node = get_tree().get_first_node_in_group(T.LIQUID_GROUP)
	if liquid != null and liquid.has_method(&"depth_at"):
		var depth: float = float(liquid.call(&"depth_at", p))
		if depth > 0.0:
			return p + Vector3.UP * depth
	return p


# --- Helpers ---

func _get_player() -> Node3D:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = null
	_player_lookup -= get_physics_process_delta_time()
	if _player_lookup > 0.0:
		return null
	_player_lookup = T.PLAYER_LOOKUP_INTERVAL
	_player = get_tree().get_first_node_in_group(T.PLAYER_GROUP) as Node3D
	return _player


func _player_busy(p: Node3D) -> bool:
	var mounted: bool = p.has_method(&"is_mounted") and bool(p.call(&"is_mounted"))
	var launched: bool = p.has_method(&"is_launched") and bool(p.call(&"is_launched"))
	return mounted or launched


func _jumped_into_bucket(p: Node3D) -> bool:
	var body := p as CharacterBody3D
	if body == null or body.is_on_floor() or body.velocity.y > 0.0:
		return false
	var rel: Vector3 = p.global_position - _seat.global_position
	if rel.y < -T.BUCKET_JUMP_BELOW or rel.y > T.BUCKET_JUMP_ABOVE:
		return false
	return Vector2(rel.x, rel.z).length() <= T.BUCKET_JUMP_RADIUS


func _footprint_distance(world_pos: Vector3) -> float:
	var local: Vector3 = _catapult.global_transform.affine_inverse() * world_pos
	var dx: float = maxf(absf(local.x) - _footprint_half.x, 0.0)
	var dz: float = maxf(absf(local.z) - _footprint_half.y, 0.0)
	return Vector2(dx, dz).length()


func _footprint() -> Vector2:
	if ResourceLoader.exists(T.BUILDING_FACTORY_PATH):
		var factory: Script = load(T.BUILDING_FACTORY_PATH) as Script
		var consts: Dictionary = factory.get_script_constant_map()
		var table: Variant = consts.get("_FOOTPRINTS", {})
		if table is Dictionary and (table as Dictionary).has(&"catapult"):
			var fp: Vector2i = (table as Dictionary)[&"catapult"]
			return Vector2(fp)
	return T.DEFAULT_FOOTPRINT


func _forward() -> Vector3:
	var z: Vector3 = _catapult.global_basis.z
	z.y = 0.0
	return z.normalized() if z.length_squared() > 1e-6 else Vector3.BACK


## Random point on the footprint perimeter, on the ground.
func _base_point() -> Vector3:
	var hx: float = _footprint_half.x
	var hz: float = _footprint_half.y
	var local: Vector3
	if rng.randf() < 0.5:
		local = Vector3(rng.randf_range(-hx, hx), 0.05, hz * (1.0 if rng.randf() < 0.5 else -1.0))
	else:
		local = Vector3(hx * (1.0 if rng.randf() < 0.5 else -1.0), 0.05, rng.randf_range(-hz, hz))
	return _catapult.global_transform * (local * 0.9)


static func _relative_xform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _play(preset: StringName, db: float, pitch: float) -> void:
	if _sfx == null:
		return
	if bool(_sfx.call(&"has_preset", preset)):
		_sfx.call(&"play", get_tree(), preset, db, pitch)


func _start_creak(db: float) -> void:
	_stop_creak()
	if _sfx == null or not bool(_sfx.call(&"is_loop", T.SFX_CREAK_LOOP)):
		return
	_creak = _sfx.call(&"play_loop", get_tree(), T.SFX_CREAK_LOOP, db, _catapult.global_position) as Node


func _stop_creak() -> void:
	if _creak != null and is_instance_valid(_creak):
		_creak.call(&"stop", T.CREAK_STOP_FADE)
	_creak = null


func _trauma(amount: float) -> void:
	if _camera_rig == null or not is_instance_valid(_camera_rig):
		_camera_rig = get_tree().get_first_node_in_group(T.CAMERA_GROUP)
	if _camera_rig != null and _camera_rig.has_method(&"add_trauma"):
		_camera_rig.call(&"add_trauma", amount)


func _rumble(weak: float, strong: float, duration: float) -> void:
	if _haptics != null:
		_haptics.call(&"rumble", clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
		return
	for id: int in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


func _fog_burst(pos: Vector3, strength: float, radius: float) -> void:
	for f: Node in get_tree().get_nodes_in_group(T.FOG_GROUP):
		if f.has_method(&"add_burst"):
			f.call(&"add_burst", pos, strength, radius)
