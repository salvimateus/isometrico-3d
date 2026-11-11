extends CharacterBody3D

## Player body: camera-relative movement, jump, skid and collisions in `_physics_process`; visual rig,
## dust and footsteps in `_process` from the interpolated transform. Feedback goes to the rig, dust,
## rumble, shared SFX and the optional liquid / camera / bump contracts of other systems.

const T := preload("res://scripts/character/character_tuning.gd")
const PlayerInput := preload("res://scripts/character/player_input.gd")
const Rig := preload("res://scripts/character/character_rig.gd")
const Dust := preload("res://scripts/character/dust_puffs.gd")
const Rumble := preload("res://scripts/character/player_rumble.gd")
const Demo := preload("res://scripts/character/player_demo.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const WATER_FX_PATH: String = "res://scripts/liquid/water_fx.gd"

signal launch_landed(position: Vector3)
signal control_restored()

enum Ride { NONE, MOUNTING, MOUNTED, LAUNCHED, DOWNED, GETUP, SWIM, SHORE_HOP }

const GROUND_PROBE_LENGTH: float = 8.0
const CONTRACT_LOOKUP_INTERVAL: float = 0.5

var rig: Node3D
var _dust: Node3D
var _rumble := Rumble.new()
var _demo: RefCounted = null

var _yaw: float = PI * 0.25
var _prev_yaw: float = PI * 0.25
var _yaw_rate: float = 0.0
var _running: bool = false
var _was_moving: bool = false
var _prev_speed: float = 0.0
var _forward_accel: float = 0.0
var _gravity: float = 9.8 * T.GRAVITY_SCALE
var _jump_velocity: float = 0.0

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _prev_jump_held: bool = false
var _jumping: bool = false
var _jump_cut_done: bool = false
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _airborne: bool = false

var _skidding: bool = false
var _skid_dust_timer: float = 0.0
var _next_skid_sound: float = 0.0

var _ground_gap: float = 0.0
var _ground_collider: Object = null
var _ground_point := Vector3.ZERO

var _camera_rig: Node = null
var _liquid: Node = null
var _water_depth: float = 0.0
var _water_velocity := Vector3.ZERO
var _wade: float = 0.0
var _stumble_timer: float = 0.0
var _next_stumble: float = 0.0
var _contract_timer: float = 0.0

var _collision: CollisionShape3D
var _ride: Ride = Ride.NONE
var _ride_t: float = 0.0
var _seat: Node3D = null
var _mount_from := Vector3.ZERO
var _tumble := Basis.IDENTITY
var _tumble_axis := Vector3.RIGHT
var _down_face: bool = true
var _down_yaw: float = 0.0
var _water_node: Node = null
var _water_surface_y: float = 0.0
var _shore := Vector3.ZERO
var _spat: bool = false
var _shook: bool = false

var _water_fx: Node = null

var _step_log: bool = false
var _step_count: int = 0
var _clock: float = 0.0


func _init() -> void:
	name = "Player"
	collision_layer = T.COLLISION_LAYER
	collision_mask = T.COLLISION_MASK
	floor_snap_length = 0.2
	var shape := CapsuleShape3D.new()
	shape.radius = T.CAPSULE_RADIUS
	shape.height = T.CAPSULE_HEIGHT
	add_to_group(T.PLAYER_GROUP)
	var col := CollisionShape3D.new()
	_collision = col
	col.name = "Collision"
	col.shape = shape
	col.position.y = T.CAPSULE_HEIGHT * 0.5
	add_child(col)
	rig = Rig.new()
	add_child(rig)
	_dust = Dust.new()
	add_child(_dust)


func _ready() -> void:
	PlayerInput.ensure_actions()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * T.GRAVITY_SCALE
	_jump_velocity = sqrt(2.0 * _gravity * T.JUMP_HEIGHT)
	rig.connect(&"footstep", _on_footstep)
	_step_log = T.SFX_LOG_STEPS or OS.get_cmdline_user_args().has("--step-log")
	if T.SFX_ENABLED:
		var presets: Array[StringName] = [&"run_whoosh", &"jump", &"skid", &"thud", &"footstep_water", &"splash_small", &"splash_big", &"viking_scream", &"impact_heavy", &"dizzy_tweet", &"water_drip"]
		for s: StringName in T.SFX_SURFACES:
			presets.append(StringName("step_%s" % s))
			presets.append(StringName("land_%s" % s))
		Sfx.warm(presets.filter(func(p: StringName) -> bool: return Sfx.has_preset(p)))
	if ResourceLoader.exists(WATER_FX_PATH):
		var wfx: Script = load(WATER_FX_PATH)
		if wfx != null and wfx.has_method(&"get_or_create"):
			_water_fx = wfx.call(&"get_or_create", get_tree())
			_prewarm_water_fx.call_deferred()
	if Demo.requested():
		_demo = Demo.new(global_position)
	# The owner usually positions the body right after adding it; don't interpolate from the origin.
	reset_physics_interpolation.call_deferred()
	_sync_rig.call_deferred()


## Catapult contract: hop onto `seat` and ride it (the rig faces the seat's -Z). Control is suspended.
func mount(seat: Node3D) -> void:
	if seat == null or _ride == Ride.LAUNCHED or _ride == Ride.DOWNED or _ride == Ride.GETUP:
		return
	_seat = seat
	_ride = Ride.MOUNTING
	_ride_t = 0.0
	_mount_from = global_position
	_collision.set_deferred(&"disabled", true)
	velocity = Vector3.ZERO
	_skidding = false
	_running = false
	_jumping = false
	_dust.trail(global_position, false)
	rig.jump_kick()
	_play(&"jump", T.SFX_JUMP_VOLUME_DB, 1.1)
	rig.call(&"set_mood", 1)


## Catapult contract: leave the seat in a ballistic arc (own gravity, collides only with layer 1).
func launch(launch_velocity: Vector3) -> void:
	if _ride != Ride.MOUNTED and _ride != Ride.MOUNTING:
		return
	if _seat != null and is_instance_valid(_seat):
		global_position = _seat.global_position
	_seat = null
	reset_physics_interpolation()
	_ride = Ride.LAUNCHED
	_ride_t = 0.0
	velocity = launch_velocity
	collision_mask = 1
	floor_snap_length = 0.0
	_collision.set_deferred(&"disabled", false)
	var flat := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
	if flat.length() > 0.1:
		_yaw = atan2(flat.x, flat.z)
		_prev_yaw = _yaw
	_tumble = Basis.IDENTITY
	_tumble_axis = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	rig.call(&"set_mood", 2)
	_rumble.launch()
	_play(&"viking_scream", T.SFX_SCREAM_DB, 1.0)


func is_mounted() -> bool:
	return _ride == Ride.MOUNTING or _ride == Ride.MOUNTED


func is_launched() -> bool:
	return _ride == Ride.LAUNCHED or _ride == Ride.DOWNED or _ride == Ride.GETUP or _ride == Ride.SWIM or _ride == Ride.SHORE_HOP


## Movement facing in radians (0 = +Z); stable while the rig tumbles or lies down.
func get_facing_yaw() -> float:
	return _yaw


func launch_gravity() -> float:
	return T.LAUNCH_GRAVITY


func _ride_physics(delta: float) -> void:
	_ride_t += delta
	match _ride:
		Ride.MOUNTING:
			if _seat == null or not is_instance_valid(_seat):
				_restore_control()
				return
			var k: float = clampf(_ride_t / T.MOUNT_HOP_TIME, 0.0, 1.0)
			global_position = _mount_from.lerp(_seat.global_position, smoothstep(0.0, 1.0, k)) + Vector3.UP * sin(PI * k) * T.MOUNT_HOP_HEIGHT
			if k >= 1.0:
				_ride = Ride.MOUNTED
				rig.land_kick(2.0)
		Ride.MOUNTED:
			if _seat == null or not is_instance_valid(_seat):
				_restore_control()
				return
			global_position = _seat.global_position
			var sz: Vector3 = -_seat.global_basis.z
			if Vector2(sz.x, sz.z).length() > 0.05:
				_yaw = atan2(sz.x, sz.z)
				_prev_yaw = _yaw
		Ride.LAUNCHED:
			velocity.y -= T.LAUNCH_GRAVITY * delta
			_tumble = Basis(_tumble_axis, T.LAUNCH_TUMBLE_SPEED * delta) * Basis(Vector3.UP, T.LAUNCH_ROLL_SPEED * delta) * _tumble
			var pre_vy: float = velocity.y
			move_and_slide()
			if _ride_t > T.LAUNCH_MIN_AIR_TIME and velocity.y < 0.0 and _check_water_entry():
				_enter_water(-pre_vy)
			elif _ride_t > T.LAUNCH_MIN_AIR_TIME and is_on_floor():
				_sample_water()
				if _in_water() and _water_depth > T.STUMBLE_MIN_DEPTH:
					_water_node = null
					_water_surface_y = global_position.y + _water_depth
					_enter_water(-pre_vy)
				else:
					_crash(-pre_vy)
		Ride.SWIM:
			_swim_step()
		Ride.SHORE_HOP:
			var k: float = clampf(_ride_t / T.SHORE_HOP_TIME, 0.0, 1.0)
			var start := Vector3(_mount_from.x, _water_surface_y, _mount_from.z)
			global_position = start.lerp(_shore, k) + Vector3.UP * sin(PI * k) * T.SHORE_HOP_HEIGHT
			if k >= 1.0:
				global_position = _shore
				reset_physics_interpolation()
				rig.land_kick(4.0)
				_dust.puff(global_position, Vector3.ZERO, 0.8)
				_play(StringName("land_%s" % _ground_surface(global_position)), T.SFX_LAND_VOLUME_DB_MIN + 3.0, 1.0)
				rig.call(&"start_drip", T.DRIP_TIME)
				_restore_control()
		Ride.DOWNED:
			velocity = Vector3.ZERO
			move_and_slide()
			if _ride_t >= T.CRASH_DOWN_TIME:
				_ride = Ride.GETUP
				_ride_t = 0.0
				rig.call(&"set_mood", 4)
				rig.kick_squash(T.SQUASH_START_KICK)
		Ride.GETUP:
			velocity = Vector3.ZERO
			move_and_slide()
			if _ride_t >= T.CRASH_GETUP_TIME:
				_restore_control()


## Finds still water (water_body group) under the flying body; true once it reaches the surface.
func _check_water_entry() -> bool:
	for node: Node in get_tree().get_nodes_in_group(T.WATER_BODY_GROUP):
		if not node.has_method(&"surface_height_at"):
			continue
		var h: float = node.call(&"surface_height_at", global_position)
		if h > -INF and global_position.y <= h:
			_water_node = node
			_water_surface_y = h
			return true
	return false


func _enter_water(fall_speed: float) -> void:
	var at := Vector3(global_position.x, _water_surface_y, global_position.z)
	_ride = Ride.SWIM
	_ride_t = 0.0
	_spat = false
	_shook = false
	velocity = Vector3.ZERO
	_collision.set_deferred(&"disabled", true)
	global_position = at
	_mount_from = at
	_down_yaw = _yaw
	_tumble = Basis.IDENTITY
	rig.call(&"set_mood", 5)
	rig.call(&"set_water_fx", 0.0, 0.0)
	rig.kick_squash(T.CRASH_SQUASH_KICK * 0.6)
	var k: float = clampf(fall_speed / T.BIG_SPLASH_REF_FALL_SPEED, 0.4, 1.0)
	_play(&"splash_big", T.SFX_SPLASH_BIG_DB_MAX, 0.85)
	_wfx_splash(at, clampf(fall_speed / T.BIG_SPLASH_REF_FALL_SPEED, 0.5, 1.5))
	if _water_node != null and is_instance_valid(_water_node) and _water_node.has_method(&"splash"):
		_water_node.call(&"splash", at, T.SPLASH_IN_STRENGTH * (0.6 + 0.6 * k))
	if _liquid != null:
		_liquid.call(&"add_disturbance", at, Vector3.DOWN * fall_speed, T.WATER_LAND_DISTURB_RADIUS * 2.0)
	_rumble.crash()
	_add_camera_trauma(T.CAMERA_TRAUMA_WATER)
	launch_landed.emit(at)
	if _step_log:
		print("[Player] water entry fall=%.2f t=%.2f" % [fall_speed, _clock])


func _swim_step() -> void:
	var t1: float = T.SWIM_SINK_TIME + T.SWIM_UNDER_TIME + T.SWIM_RISE_TIME
	var t2: float = t1 + T.SWIM_SPIT_TIME
	var t3: float = t2 + T.SWIM_SHAKE_TIME
	if _ride_t >= t1 and not _spat:
		_spat = true
		rig.call(&"set_water_fx", 1.0, 0.0)
		_play(&"splash_small", T.SFX_SPIT_DB, 1.5)
		var mouth: Vector3 = Vector3(global_position.x, _water_surface_y, global_position.z) + Vector3.UP * 0.32 + _forward() * 0.22
		if _water_fx != null:
			_water_fx.call(&"squirt", mouth, _forward() + Vector3.UP * 0.75, T.SPIT_JET_TIME, _water_surface_y)
		if _step_log:
			print("[Player] spit t=%.2f" % _clock)
	if _ride_t >= t2 and not _shook:
		_shook = true
		rig.call(&"set_water_fx", 0.0, 1.0)
		_play(&"water_drip", -6.0, 1.0)
	if _ride_t >= t3:
		_shore = _find_shore()
		var flat := Vector3(_shore.x - global_position.x, 0.0, _shore.z - global_position.z)
		if flat.length() > 0.05:
			_yaw = atan2(flat.x, flat.z)
			_prev_yaw = _yaw
		rig.call(&"set_water_fx", 0.0, 0.0)
		rig.call(&"set_mood", 0)
		rig.jump_kick()
		_play(&"jump", T.SFX_JUMP_VOLUME_DB, 1.0)
		_play(&"splash_small", T.SFX_SPLASH_SMALL_DB + 3.0, 1.0)
		_wfx_splash(global_position, 0.8)
		if _water_fx != null:
			_water_fx.call(&"drip_trail", rig, T.SHORE_HOP_TIME + T.DRIP_TIME)
		_ride = Ride.SHORE_HOP
		_ride_t = 0.0
		if _step_log:
			print("[Player] shore hop to %s t=%.2f" % [_shore, _clock])


## Water visuals come from the LIQUID agent's shared water_fx (optional; no-op when absent).
## Fires each water effect once under the ground (drawn but depth-hidden) so their shaders and
## pipelines compile at load instead of on the first real splash.
func _prewarm_water_fx() -> void:
	if _water_fx == null:
		return
	var p: Vector3 = global_position + Vector3.DOWN * 4.0
	_water_fx.call(&"splash", p, 0.5, p.y)
	_water_fx.call(&"ripple_spray", p, 0.5, p.y)
	_water_fx.call(&"squirt", p, Vector3.UP, 0.05, p.y)


func _wfx_splash(surface_pos: Vector3, strength: float) -> void:
	if _water_fx != null:
		_water_fx.call(&"splash", surface_pos, clampf(strength, 0.5, 1.5), surface_pos.y)


func _wfx_ripple(surface_pos: Vector3, strength: float) -> void:
	if _water_fx != null:
		_water_fx.call(&"ripple_spray", surface_pos, strength, surface_pos.y)


func _find_shore() -> Vector3:
	if _water_node != null and is_instance_valid(_water_node) and _water_node.has_method(&"nearest_shore"):
		return _water_node.call(&"nearest_shore", global_position)
	# Liquid sim fallback: walk outward until the field reports no water.
	if _liquid != null:
		for r: float in [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]:
			for i: int in 8:
				var a: float = TAU * float(i) / 8.0
				var p: Vector3 = global_position + Vector3(cos(a), 0.0, sin(a)) * r
				if float(_liquid.call(&"depth_at", p)) <= T.WATER_MIN_DEPTH:
					return Vector3(p.x, global_position.y - _water_depth, p.z)
	return global_position + _forward() * 2.0


func _crash(fall_speed: float) -> void:
	# Face plant when tumbling face-first, otherwise land on the butt.
	var up_now: Vector3 = _tumble * Vector3.UP
	var fwd_now: Vector3 = _tumble * _forward()
	_down_face = fwd_now.y < 0.0 or up_now.y < 0.0
	_down_yaw = _yaw
	_ride = Ride.DOWNED
	_ride_t = 0.0
	velocity = Vector3.ZERO
	collision_mask = T.COLLISION_MASK
	floor_snap_length = 0.2
	rig.call(&"set_mood", 3, _down_face)
	rig.kick_squash(T.CRASH_SQUASH_KICK)
	rig.land_kick(fall_speed)
	_rumble.crash()
	_add_camera_trauma(T.CAMERA_TRAUMA_CRASH)
	_sample_water()
	if _in_water():
		_play(&"splash_big", T.SFX_SPLASH_BIG_DB_MAX, 0.85)
		_wfx_splash(_water_surface(global_position), 1.4)
		_disturb(global_position, Vector3.DOWN * fall_speed, T.WATER_LAND_DISTURB_RADIUS * 2.0)
	else:
		_play(&"impact_heavy", T.SFX_IMPACT_HEAVY_DB, 1.0)
		_dust.crater(global_position, T.CRASH_DUST_RING)
	_play(&"dizzy_tweet", T.SFX_DIZZY_DB, 1.0)
	launch_landed.emit(global_position)
	if _step_log:
		print("[Player] crash fall=%.2f face=%s t=%.2f" % [fall_speed, _down_face, _clock])


func _restore_control() -> void:
	_ride = Ride.NONE
	_seat = null
	collision_mask = T.COLLISION_MASK
	floor_snap_length = 0.2
	_collision.set_deferred(&"disabled", false)
	velocity = Vector3.ZERO
	_was_on_floor = true
	_jump_buffer = 0.0
	rig.call(&"set_mood", 0)
	control_restored.emit()
	if _step_log:
		print("[Player] control restored t=%.2f" % _clock)


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > T.MOVING_EPSILON


## Optional helper: moves the body without an interpolated slide.
func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_sync_rig()


func _input(event: InputEvent) -> void:
	_rumble.note_event(event)


# --- Physics: movement and gameplay events ---

func _physics_process(delta: float) -> void:
	_clock += delta
	_rumble.tick(delta)
	_refresh_contracts(delta)
	if _ride != Ride.NONE:
		_ride_physics(delta)
		return

	var move: Vector3
	var run_held: bool
	var jump_held: bool
	if _demo != null:
		_demo.update(delta, global_position)
		move = _demo.move
		run_held = _demo.run
		jump_held = _demo.jump_held
	else:
		move = _camera_relative(PlayerInput.read_move())
		run_held = PlayerInput.is_run_held()
		jump_held = PlayerInput.is_jump_held()
	_sample_water()
	if _stumble_timer > 0.0:
		_stumble_timer -= delta
		move = Vector3.ZERO
		run_held = false
		jump_held = false
	var amount: float = minf(move.length(), 1.0)
	var wants_run: bool = run_held and amount > 0.3

	var on_floor: bool = is_on_floor()
	if jump_held and not _prev_jump_held:
		_jump_buffer = T.JUMP_BUFFER_TIME
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_prev_jump_held = jump_held
	_coyote = T.COYOTE_TIME if on_floor else maxf(_coyote - delta, 0.0)

	# Horizontal velocity, with skid on a sharp reversal.
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var hspeed: float = hvel.length()
	var move_dir: Vector3 = move.normalized() if amount > 0.0 else Vector3.ZERO
	var reversing: bool = amount > 0.5 and hspeed > 0.01 and move_dir.dot(hvel / hspeed) < T.SKID_REVERSE_DOT
	if on_floor and not _skidding and reversing and hspeed > T.SKID_MIN_SPEED:
		_start_skid()
	if _skidding and (not on_floor or not reversing or hspeed < 0.8):
		_skidding = false
	var target_speed: float = amount * (T.RUN_SPEED if wants_run else T.WALK_SPEED) * lerpf(1.0, T.WADE_MIN_SPEED_MULT, _wade)
	var target_vel: Vector3 = move_dir * target_speed
	var rate: float = T.DECELERATION if target_vel.length() < hspeed else (T.RUN_ACCELERATION if wants_run else T.ACCELERATION)
	rate *= lerpf(1.0, T.WADE_ACCEL_MULT, _wade)
	if _skidding:
		rate = T.SKID_DECELERATION
	if not on_floor:
		rate *= T.AIR_CONTROL
	if _stumble_timer > 0.0:
		rate *= 0.25
	hvel = hvel.move_toward(target_vel, rate * delta)
	if _wade > 0.0:
		var current := Vector3(_water_velocity.x, 0.0, _water_velocity.z)
		hvel += current * T.CURRENT_PUSH * _wade * delta
		hvel = hvel.limit_length(maxf(T.RUN_SPEED, minf(current.length(), T.CURRENT_MAX_DRIFT) + target_speed))
		if on_floor:
			_check_stumble(current, hvel)
	if _stumble_timer <= 0.0 or not _airborne:
		velocity.x = hvel.x
		velocity.z = hvel.z

	# Jump: immediate takeoff, buffered and with coyote time.
	if _jump_buffer > 0.0 and _coyote > 0.0:
		_takeoff()
		on_floor = false
	if _jumping and not jump_held and velocity.y > 0.0 and not _jump_cut_done:
		velocity.y *= T.JUMP_CUT_FACTOR
		_jump_cut_done = true

	if not on_floor:
		var g: float = _gravity
		if absf(velocity.y) < T.APEX_SPEED_THRESHOLD and _jumping:
			g *= T.APEX_GRAVITY_MULT
		elif velocity.y < 0.0:
			g *= T.FALL_GRAVITY_MULT
		velocity.y = maxf(velocity.y - g * delta, -T.MAX_FALL_SPEED)
	elif not _jumping:
		velocity.y = minf(velocity.y, 0.0)

	var pre_vel := velocity
	move_and_slide()
	on_floor = is_on_floor()
	_handle_impacts(Vector3(pre_vel.x, 0.0, pre_vel.z))

	if on_floor and not _was_on_floor:
		_on_landed(-pre_vel.y)
	if on_floor:
		_air_time = 0.0
		if velocity.y <= 0.0:
			_jumping = false
	else:
		_air_time += delta
	_was_on_floor = on_floor
	_airborne = not on_floor and (_air_time > 0.06 or _jumping)

	_probe_ground()
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_update_facing(delta, move, amount)
	if on_floor:
		_update_gait_events(speed, wants_run)
	if _skidding:
		_skid_dust_timer -= delta
		if _skid_dust_timer <= 0.0:
			_skid_dust_timer = T.SKID_DUST_INTERVAL
			_dust.puff(global_position + hvel.normalized() * 0.2, hvel.normalized() * 0.5, 0.9)
	_feed_liquid(speed)

	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var raw_accel: float = (speed - _prev_speed) / maxf(delta, 1e-4)
	_forward_accel = raw_accel * clampf(forward.dot(hvel.normalized()), 0.0, 1.0) if on_floor else 0.0
	_prev_speed = speed


func _camera_relative(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var right := Vector3.RIGHT
	var forward := Vector3.FORWARD
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var b: Basis = cam.global_basis
		var r := Vector3(b.x.x, 0.0, b.x.z)
		var f := Vector3(-b.z.x, 0.0, -b.z.z)
		if f.length() < 0.01:
			f = Vector3(b.y.x, 0.0, b.y.z)
		if r.length() > 0.01 and f.length() > 0.01:
			right = r.normalized()
			forward = f.normalized()
	return right * input.x + forward * (-input.y)


func _update_facing(delta: float, move: Vector3, amount: float) -> void:
	_prev_yaw = _yaw
	if amount > 0.05 and not _skidding:
		var target: float = atan2(move.x, move.z)
		var turn: float = T.TURN_SPEED * (T.AIR_CONTROL if _airborne else 1.0)
		_yaw = lerp_angle(_yaw, target, 1.0 - exp(-turn * delta))
	_yaw_rate = angle_difference(_prev_yaw, _yaw) / maxf(delta, 1e-4)


func _update_gait_events(speed: float, wants_run: bool) -> void:
	var ratio: float = speed / T.WALK_SPEED
	var moving_now: bool = ratio > (T.STOP_SPEED_RATIO if _was_moving else T.START_SPEED_RATIO)
	if moving_now and not _was_moving:
		rig.kick_squash(T.SQUASH_START_KICK)
	elif not moving_now and _was_moving:
		rig.kick_squash(T.SQUASH_STOP_KICK)
		if _running:
			_dust.puff(global_position, Vector3.ZERO, 1.3)
			_dust.puff(global_position + _forward() * 0.15, Vector3.ZERO, 1.0)
	_was_moving = moving_now

	var run_now: bool = wants_run and moving_now
	if run_now and not _running:
		rig.kick_squash(T.SQUASH_RUN_START_KICK)
		_rumble.run_start()
		_play(&"run_whoosh", T.SFX_WHOOSH_VOLUME_DB, 1.0)
		_dust.puff(global_position - _forward() * 0.1, -_forward(), 1.2)
	_running = run_now


func _start_skid() -> void:
	_skidding = true
	_skid_dust_timer = 0.0
	rig.kick_squash(T.SQUASH_STOP_KICK)
	_rumble.skid()
	if _clock >= _next_skid_sound:
		_next_skid_sound = _clock + T.SKID_SOUND_COOLDOWN
		_play(&"skid", T.SFX_SKID_VOLUME_DB, 1.0)
	if _step_log:
		print("[Player] skid t=%.2f" % _clock)


func _takeoff() -> void:
	velocity.y = _jump_velocity
	_jumping = true
	_jump_cut_done = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_skidding = false
	rig.jump_kick()
	_rumble.jump()
	_play(&"jump", T.SFX_JUMP_VOLUME_DB, 1.0)
	if _in_water():
		_play(&"splash_small", T.SFX_SPLASH_SMALL_DB, 1.0)
		_wfx_ripple(_water_surface(global_position), 1.0)
		_disturb(global_position, Vector3.UP * _jump_velocity * 0.3, T.WAKE_RUN_RADIUS)
	else:
		_dust.puff(global_position, Vector3.ZERO, 0.8)
	if _step_log:
		print("[Player] jump t=%.2f" % _clock)


func _on_landed(fall_speed: float) -> void:
	if _air_time < 0.08 and fall_speed < T.LAND_SOFT_SPEED:
		return
	var k: float = clampf((fall_speed - T.LAND_SOFT_SPEED * 0.5) / (T.LAND_HARD_SPEED * 1.3 - T.LAND_SOFT_SPEED * 0.5), 0.0, 1.0)
	rig.land_kick(fall_speed)
	_rumble.land(k)
	var surface: StringName = _surface_at_feet(global_position)
	if surface == &"water":
		_play(&"splash_big", lerpf(T.SFX_SPLASH_BIG_DB_MIN, T.SFX_SPLASH_BIG_DB_MAX, k), 1.05 - 0.1 * k)
		_wfx_splash(_water_surface(global_position), 0.5 + k)
		_disturb(global_position, Vector3.DOWN * fall_speed * T.WATER_LAND_DISTURB_GAIN, T.WATER_LAND_DISTURB_RADIUS * (0.6 + k))
	else:
		_play(StringName("land_%s" % surface), lerpf(T.SFX_LAND_VOLUME_DB_MIN, T.SFX_LAND_VOLUME_DB_MAX, k), 1.0 - 0.06 * k)
		if fall_speed >= T.DUST_RING_MIN_SPEED:
			_dust.ring(global_position, 0.5 + k)
		else:
			_dust.puff(global_position, Vector3.ZERO, 0.8)
	if fall_speed >= T.LAND_HARD_SPEED:
		_add_camera_trauma(T.CAMERA_TRAUMA_HARD_LAND * clampf(fall_speed / T.LAND_HARD_SPEED, 1.0, 1.5))
	if _step_log:
		print("[Player] land fall=%.2f k=%.2f %s t=%.2f" % [fall_speed, k, surface, _clock])


func _handle_impacts(pre_hvel: Vector3) -> void:
	var best: float = 0.0
	var best_normal := Vector3.ZERO
	var best_collider: Object = null
	for i: int in get_slide_collision_count():
		var c: KinematicCollision3D = get_slide_collision(i)
		var collider := c.get_collider() as CollisionObject3D
		if collider == null or (collider.collision_layer & T.OBSTACLE_LAYER_BIT) == 0:
			continue
		var n: Vector3 = c.get_normal()
		n.y = 0.0
		if n.length() < 0.3:
			continue
		n = n.normalized()
		var hit: float = pre_hvel.dot(-n)
		if hit > best:
			best = hit
			best_normal = n
			best_collider = collider
	if best < T.RUMBLE_IMPACT_MIN_SPEED:
		return
	var strength: float = clampf((best - T.RUMBLE_IMPACT_MIN_SPEED) / (T.RUN_SPEED - T.RUMBLE_IMPACT_MIN_SPEED), 0.15, 1.0)
	if not _rumble.impact(strength):
		return
	_play(&"thud", lerpf(T.SFX_THUD_VOLUME_DB_MIN, T.SFX_THUD_VOLUME_DB_MAX, strength), 1.0)
	rig.kick_squash(T.SQUASH_BUMP_KICK * strength)
	_add_camera_trauma(T.CAMERA_TRAUMA_IMPACT_MAX * strength)
	if best_collider != null and best_collider.has_method(&"bump"):
		best_collider.call(&"bump", -best_normal * best * T.BUMP_IMPULSE_GAIN)
	if _step_log:
		print("[Player] impact strength=%.2f t=%.2f" % [strength, _clock])


func _probe_ground() -> void:
	if is_on_floor():
		_ground_gap = 0.0
	var from: Vector3 = global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * GROUND_PROBE_LENGTH, 1)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ground_collider = null
		_ground_gap = GROUND_PROBE_LENGTH if not is_on_floor() else 0.0
		return
	_ground_collider = hit.get("collider")
	_ground_point = hit.get("position", global_position)
	if not is_on_floor():
		_ground_gap = maxf(global_position.y - _ground_point.y, 0.0)


## Ground surface under a point: asks the ground collider via `surface_at(pos) -> StringName`, else default.
func _ground_surface(pos: Vector3) -> StringName:
	if _ground_collider == null or not is_instance_valid(_ground_collider):
		return T.SFX_DEFAULT_SURFACE
	if not _ground_collider.has_method(&"surface_at"):
		return T.SFX_DEFAULT_SURFACE
	var s: Variant = _ground_collider.call(&"surface_at", Vector3(pos.x, _ground_point.y, pos.z))
	if (s is StringName or s is String) and T.SFX_SURFACES.has(StringName(s)):
		return StringName(s)
	return T.SFX_DEFAULT_SURFACE


func _refresh_contracts(delta: float) -> void:
	if _camera_rig != null and not is_instance_valid(_camera_rig):
		_camera_rig = null
	_contract_timer -= delta
	if _liquid != null and not is_instance_valid(_liquid):
		_liquid = null
	if _contract_timer > 0.0 or (_camera_rig != null and _liquid != null):
		return
	_contract_timer = CONTRACT_LOOKUP_INTERVAL
	if _liquid == null:
		var l: Node = get_tree().get_first_node_in_group(T.LIQUID_GROUP)
		if l != null and l.has_method(&"depth_at") and l.has_method(&"velocity_at") and l.has_method(&"add_disturbance"):
			_liquid = l
	if _camera_rig == null:
		var c: Node = get_tree().get_first_node_in_group(T.CAMERA_GROUP)
		if c != null and c.has_method(&"add_trauma"):
			_camera_rig = c


func _sample_water() -> void:
	if _liquid == null:
		_water_depth = 0.0
		_water_velocity = Vector3.ZERO
		_wade = 0.0
		return
	_water_depth = maxf(float(_liquid.call(&"depth_at", global_position)), 0.0)
	_water_velocity = _liquid.call(&"velocity_at", global_position) if _water_depth > T.WATER_MIN_DEPTH else Vector3.ZERO
	_wade = clampf(_water_depth / T.WADE_FULL_DEPTH, 0.0, 1.0) if _water_depth > T.WATER_MIN_DEPTH else 0.0


func _in_water() -> bool:
	return _water_depth > T.WATER_MIN_DEPTH


func _water_surface(pos: Vector3) -> Vector3:
	return Vector3(pos.x, global_position.y + _water_depth, pos.z)


func _disturb(pos: Vector3, vel: Vector3, radius: float) -> void:
	if _liquid != null and _in_water():
		_liquid.call(&"add_disturbance", _water_surface(pos), vel, radius)


func _feed_liquid(speed: float) -> void:
	if speed < T.MOVING_EPSILON or _airborne:
		return
	var radius: float = lerpf(T.WAKE_WALK_RADIUS, T.WAKE_RUN_RADIUS, clampf((speed - T.WALK_SPEED * 0.5) / T.RUN_SPEED, 0.0, 1.0))
	_disturb(global_position, Vector3(velocity.x, 0.0, velocity.z) * T.WAKE_VELOCITY_GAIN, radius)


## A fast wave front that hits harder than the body is moving knocks it off its feet.
func _check_stumble(current: Vector3, hvel: Vector3) -> void:
	if _clock < _next_stumble or _water_depth < T.STUMBLE_MIN_DEPTH or _stumble_timer > 0.0:
		return
	if current.length() < T.STUMBLE_REL_SPEED * 0.6 or (current - hvel).length() < T.STUMBLE_REL_SPEED:
		return
	var dir: Vector3 = current.normalized()
	_stumble_timer = T.STUMBLE_TIME
	_next_stumble = _clock + T.STUMBLE_COOLDOWN
	_skidding = false
	_jumping = false
	velocity = dir * T.STUMBLE_KNOCKBACK + current * 0.3 + Vector3.UP * T.STUMBLE_HOP
	rig.stumble()
	_rumble.stumble()
	_add_camera_trauma(T.CAMERA_TRAUMA_STUMBLE)
	_play(&"splash_big", T.SFX_SPLASH_BIG_DB_MAX - 2.0, 1.0)
	_wfx_splash(_water_surface(global_position), 0.9)
	_disturb(global_position, dir * T.STUMBLE_KNOCKBACK, T.WATER_LAND_DISTURB_RADIUS)
	if _step_log:
		print("[Player] stumble current=%.2f t=%.2f" % [current.length(), _clock])


## Footstep surface: water when wading, else the ground collider's surface.
func _surface_at_feet(pos: Vector3) -> StringName:
	return &"water" if _in_water() else _ground_surface(pos)


func _add_camera_trauma(amount: float) -> void:
	if _camera_rig != null:
		_camera_rig.call(&"add_trauma", amount)


func _forward() -> Vector3:
	return Vector3(sin(_yaw), 0.0, cos(_yaw))


func _play(preset: StringName, volume_db: float, pitch: float) -> void:
	if T.SFX_ENABLED:
		Sfx.play(get_tree(), preset, volume_db, pitch)


# --- Visual: rig, trail and footsteps every rendered frame ---

func _process(delta: float) -> void:
	_sync_rig()
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if _ride != Ride.NONE:
		rig.animate(delta, 0.0, 0.0, 0.0, 0.0, _ride == Ride.LAUNCHED, velocity.y if _ride == Ride.LAUNCHED else 0.0, 0.0, 0.0)
		_dust.trail(rig.global_position, false)
		return
	rig.animate(delta, speed, 1.0 if _running else 0.0, _forward_accel, _yaw_rate, _airborne, velocity.y, 1.0 if _skidding else 0.0, _wade)
	var trail_on: bool = _running and not _airborne and not _in_water() and speed > T.RUN_SPEED * T.TRAIL_MIN_SPEED_RATIO
	_dust.trail(rig.global_position, trail_on)


func _sync_rig() -> void:
	if _ride != Ride.NONE:
		_sync_rig_ride()
		return
	var interp: bool = is_inside_tree() and get_tree().physics_interpolation and is_physics_interpolated_and_enabled()
	var frac: float = Engine.get_physics_interpolation_fraction() if interp else 1.0
	var origin: Vector3 = get_global_transform_interpolated().origin if interp else global_position
	rig.place(origin, lerp_angle(_prev_yaw, _yaw, frac))
	rig.set_ground_gap(_ground_gap if _airborne else 0.0)


func _sync_rig_ride() -> void:
	var lift: float = (character_rig_hip() - 0.06) * T.VISUAL_SCALE
	match _ride:
		Ride.MOUNTED:
			if _seat != null and is_instance_valid(_seat):
				# The seat animates on the physics tick: follow its interpolated transform so the rider doesn't judder.
				var seat_xf: Transform3D = _seat.get_global_transform_interpolated()
				var sb: Basis = seat_xf.basis.orthonormalized() * Basis(Vector3.UP, PI)
				rig.place_transform(Transform3D(sb, seat_xf.origin - sb.y * lift))
				return
		Ride.MOUNTING:
			var origin: Vector3 = get_global_transform_interpolated().origin
			var yaw: float = _yaw
			if _seat != null and is_instance_valid(_seat):
				var z: Vector3 = -_seat.global_basis.z
				yaw = lerp_angle(_yaw, atan2(z.x, z.z), clampf(_ride_t / T.MOUNT_HOP_TIME, 0.0, 1.0))
			rig.place_transform(Transform3D(Basis(Vector3.UP, yaw), origin - Vector3.UP * lift * clampf(_ride_t / T.MOUNT_HOP_TIME, 0.0, 1.0)))
			return
		Ride.LAUNCHED:
			var o: Vector3 = get_global_transform_interpolated().origin
			var center := Vector3.UP * 0.45
			var b: Basis = _tumble * Basis(Vector3.UP, _yaw)
			rig.place_transform(Transform3D(b, o + center - b * center))
			rig.set_ground_gap(0.0)
			return
		Ride.SWIM:
			var t: float = _ride_t
			var sink: float
			if t < T.SWIM_SINK_TIME:
				sink = lerpf(0.0, T.SWIM_SINK_DEPTH, smoothstep(0.0, 1.0, t / T.SWIM_SINK_TIME))
			elif t < T.SWIM_SINK_TIME + T.SWIM_UNDER_TIME:
				sink = T.SWIM_SINK_DEPTH
			else:
				var r: float = clampf((t - T.SWIM_SINK_TIME - T.SWIM_UNDER_TIME) / T.SWIM_RISE_TIME, 0.0, 1.0)
				sink = lerpf(T.SWIM_SINK_DEPTH, T.SWIM_FLOAT_DEPTH, 1.0 - pow(1.0 - r, 3.0)) - 0.06 * sin(PI * r)
			var bob: float = 0.025 * sin(_clock * 3.0) if t > T.SWIM_SINK_TIME + T.SWIM_UNDER_TIME else 0.0
			var base := Vector3(global_position.x, _water_surface_y, global_position.z)
			rig.place_transform(Transform3D(Basis(Vector3.UP, _yaw), base - Vector3.UP * (sink * T.VISUAL_SCALE - bob)))
			rig.set_ground_gap(10.0)
			return
		Ride.SHORE_HOP:
			rig.place(get_global_transform_interpolated().origin, _yaw)
			rig.set_ground_gap(0.0)
			return
		Ride.DOWNED, Ride.GETUP:
			var o: Vector3 = get_global_transform_interpolated().origin
			var k: float = 1.0 if _ride == Ride.DOWNED else 1.0 - smoothstep(0.0, 1.0, _ride_t / T.CRASH_GETUP_TIME)
			var tilt: float = (PI * 0.5 if _down_face else -0.25) * k
			var right := Vector3(cos(_down_yaw), 0.0, -sin(_down_yaw))
			var b: Basis = Basis(right, tilt) * Basis(Vector3.UP, _down_yaw)
			var drop: float = (T.CRASH_LIE_HEIGHT if _down_face else -lift) * k
			rig.place_transform(Transform3D(b, o + Vector3.UP * drop))
			rig.set_ground_gap(0.0)
			return
	rig.place(get_global_transform_interpolated().origin, _yaw)


func character_rig_hip() -> float:
	return Rig.HIP_HEIGHT


func _on_footstep(side: int, foot_position: Vector3, run_blend: float, move_amount: float) -> void:
	var surface: StringName = _surface_at_feet(foot_position)
	var running: bool = _running
	var db: float = (T.SFX_RUN_VOLUME_DB if running else T.SFX_WALK_VOLUME_DB) + linear_to_db(clampf(move_amount, 0.3, 1.0))
	var pitch: float = (T.SFX_RUN_PITCH if running else T.SFX_WALK_PITCH) + (T.SFX_LR_PITCH_OFFSET if side == 0 else -T.SFX_LR_PITCH_OFFSET)
	var ratio: float = Vector2(velocity.x, velocity.z).length() / T.RUN_SPEED
	if surface == &"water":
		_play(&"footstep_water", T.SFX_WATER_STEP_VOLUME_DB + (3.0 if running else 0.0) + linear_to_db(clampf(move_amount, 0.3, 1.0)), pitch - 0.05 * _wade)
		_wfx_ripple(_water_surface(foot_position), 0.5 + 0.4 * run_blend + 0.3 * _wade)
		_rumble.step()
	else:
		_play(StringName("step_%s" % surface), db, pitch)
		if running:
			_rumble.step()
		if (running or T.DUST_WALK) and ratio > T.DUST_MIN_SPEED_RATIO:
			_dust.puff(foot_position, -_forward(), 0.7 + 0.5 * run_blend)
	if _step_log:
		_step_count += 1
		print("[Player] step #%d %s %s %s t=%.3f speed=%.2f" % [_step_count, "L" if side == 0 else "R", "run" if running else "walk", surface, _clock, Vector2(velocity.x, velocity.z).length()])
