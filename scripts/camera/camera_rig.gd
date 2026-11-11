extends Node3D

## Camera rig with two modes: isometric diorama (grab-pan with inertia, cursor-anchored zoom, player
## follow) and over-the-shoulder third person. Both share trauma shake and depth of field; switching
## blends look point, rotation (slerp), distance and FOV.

signal clicked(screen_pos: Vector2)
signal mode_changed(shoulder: bool)

const Tuning := preload("res://scripts/tuning.gd")

enum Mode { ISO, SHOULDER }

var camera: Camera3D
var mode: int = Mode.ISO
var pitch_deg: float = Tuning.CAMERA_PITCH_DEG
var distance: float = Tuning.CAMERA_DISTANCE_DEFAULT
var target_distance: float = Tuning.CAMERA_DISTANCE_DEFAULT

var _velocity := Vector3.ZERO
var _dragging: bool = false
var _drag_button: int = 0
var _press_pos := Vector2.ZERO
var _drag_moved: bool = false
var _grab_point := Vector3.ZERO
var _last_drag_time: float = 0.0
var _zoom_anchor: Variant = null
var _focus_target: Variant = null

## Optional node to follow; it may expose `is_moving() -> bool` to re-engage the follow.
var follow_target: Node3D = null
var follow_locked: bool = false
var _following: bool = false
var _follow_prev := Vector3.ZERO
var _lookahead := Vector3.ZERO

# Pose = look point + rotation + distance back along +Z + fov + near plane.
var _out_look := Vector3.ZERO
var _out_quat := Quaternion.IDENTITY
var _out_dist: float = 1.0
var _out_fov: float = Tuning.CAMERA_FOV
var _out_near: float = Tuning.CAMERA_NEAR_ISO
var _from_look := Vector3.ZERO
var _from_quat := Quaternion.IDENTITY
var _from_dist: float = 1.0
var _from_fov: float = Tuning.CAMERA_FOV
var _from_near: float = Tuning.CAMERA_NEAR_ISO
var _blend_t: float = 1.0
var _shoulder_weight: float = 0.0

var _sh_yaw: float = 0.0
var _sh_pitch: float = deg_to_rad(Tuning.SHOULDER_PITCH_DEFAULT_DEG)
var _sh_dist: float = Tuning.SHOULDER_DISTANCE_DEFAULT
var _sh_target_dist: float = Tuning.SHOULDER_DISTANCE_DEFAULT
var _sh_side: float = 1.0
var _sh_side_target: float = 1.0
var _arm_shape := SphereShape3D.new()
var _arm_frac: float = -1.0
var _pitch_lift: float = 0.0
var _yaw_swing: float = 0.0
var _want := Vector2.ZERO
var _candidates: Array[Vector2] = []
var _aim_blend: float = 0.0
var _exclude: Array[RID] = []
var _boxes: Array[AABB] = []
var _boxes_built: bool = false
var _near_boxes: Array[AABB] = []
var _near_frame: int = -1
var _canopies: Array[PackedFloat32Array] = []
var _near_canopies: Array[PackedFloat32Array] = []
var _stick_rate := Vector2.ZERO
var _stick_hold: float = 0.0
var _bob: float = 0.0
var _bob_vel: float = 0.0
var _sway: float = 0.0
var _sway_vel: float = 0.0
var _fov_kick: float = 0.0
var _fov_kick_vel: float = 0.0
var _airborne: bool = false
var _air_min_vy: float = 0.0
var _start_shoulder: bool = false

var _launch_w: float = 0.0
var _chase_w: float = 0.0
var _hold_t: float = 0.0
var _impact := Vector3.ZERO
var _was_seq: bool = false
var _t_land: float = INF
var _launch_look := Vector3.ZERO
var _launch_dist: float = -1.0
var _launch_dist_vel: float = 0.0
var _launch_age: float = 0.0
var _launch_landed: bool = false
var _launch_rest: float = 0.0
var _launch_prev_vy: float = 0.0
var _launch_gravity: float = 9.8
var _launch_dir := Vector3.FORWARD
var _launch_climb: float = 0.0
var _was_launched: bool = false

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _noise := FastNoiseLite.new()

var _attributes := CameraAttributesPractical.new()
var _dof_on: bool = Tuning.DOF_ENABLED
var _focus_distance: float = -1.0
var _mobile: bool = false


func _ready() -> void:
	add_to_group(&"camera_rig")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_start_shoulder = args.has("--cam=follow")
	if args.has("--fake-launch=1"):
		add_child.call_deferred(load("res://scripts/camera/dev_fake_launch.gd").new())
	if args.has("--shoulder=left"):
		_sh_side = -1.0
		_sh_side_target = -1.0
	if args.has("--postfx=0"):
		_dof_on = false

	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.top_level = true
	camera.fov = Tuning.CAMERA_FOV
	camera.near = Tuning.CAMERA_NEAR_ISO
	camera.far = Tuning.CAMERA_FAR
	camera.attributes = _attributes
	_mobile = _quality_tier() == &"mobile"
	if _mobile:
		_dof_on = _dof_on and Tuning.DOF_MOBILE_ENABLED
		RenderingServer.camera_attributes_set_dof_blur_quality(Tuning.DOF_MOBILE_QUALITY as RenderingServer.DOFBlurQuality, false)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	add_child(camera)

	_arm_shape.radius = Tuning.SHOULDER_ARM_RADIUS

	_attributes.dof_blur_far_enabled = false
	_attributes.dof_blur_near_enabled = false
	_set_out_pose(_iso_pose())
	_apply_distance()
	camera.make_current()


# --- Public API ---------------------------------------------------------------------------------

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func is_shoulder() -> bool:
	return mode == Mode.SHOULDER


func toggle_mode() -> void:
	set_mode(Mode.ISO if mode == Mode.SHOULDER else Mode.SHOULDER)


func set_mode(new_mode: int, instant: bool = false) -> void:
	if new_mode == mode:
		return
	if new_mode == Mode.SHOULDER and not _has_player():
		return
	_from_look = _out_look
	_from_quat = _out_quat
	_from_dist = _out_dist
	_from_fov = _out_fov
	_from_near = _out_near
	_blend_t = 1.0 if instant else 0.0
	mode = new_mode
	_dragging = false
	_velocity = Vector3.ZERO
	if mode == Mode.SHOULDER:
		var fwd: Vector3 = -(Basis(_out_quat).z)
		_sh_yaw = atan2(-fwd.x, -fwd.z)
		_sh_pitch = deg_to_rad(Tuning.SHOULDER_PITCH_DEFAULT_DEG)
		_sh_target_dist = Tuning.SHOULDER_DISTANCE_DEFAULT
		_sh_dist = _sh_target_dist
		_arm_frac = -1.0
		_pitch_lift = 0.0
		_yaw_swing = 0.0
		_want = Vector2.ZERO
		_aim_blend = 0.0
		_bob = 0.0
		_bob_vel = 0.0
		_sway = 0.0
		_sway_vel = 0.0
		_fov_kick = 0.0
		_fov_kick_vel = 0.0
		_stick_rate = Vector2.ZERO
	else:
		follow_locked = false
		if _has_player():
			position = _clamp_pan(_player_position())
			_engage_follow(false)
		_apply_distance()
	if instant:
		_set_out_pose(_target_pose())
		_apply_pose_to_camera()
	mode_changed.emit(mode == Mode.SHOULDER)


## Touch API (called by the touch UI). Orbit only applies to the shoulder mode; the iso camera stays
## fixed and follows the player on touch.
func touch_orbit(screen_delta: Vector2) -> void:
	if mode != Mode.SHOULDER:
		return
	var sens: float = deg_to_rad(Tuning.TOUCH_ORBIT_SENSITIVITY_DEG)
	_sh_yaw = wrapf(_sh_yaw - screen_delta.x * sens, -PI, PI)
	_sh_pitch = clampf(_sh_pitch - screen_delta.y * sens, deg_to_rad(Tuning.SHOULDER_PITCH_MIN_DEG), deg_to_rad(Tuning.SHOULDER_PITCH_MAX_DEG))


## Pinch zoom: factor > 1 moves closer.
func touch_zoom(factor: float) -> void:
	if factor <= 0.0:
		return
	if mode == Mode.SHOULDER:
		_sh_target_dist = clampf(_sh_target_dist / factor, Tuning.SHOULDER_DISTANCE_MIN, Tuning.SHOULDER_DISTANCE_MAX)
	else:
		target_distance = clampf(target_distance / factor, Tuning.CAMERA_DISTANCE_MIN, Tuning.CAMERA_DISTANCE_MAX)
		_zoom_anchor = null


func touch_tap(screen_pos: Vector2) -> void:
	clicked.emit(screen_pos)


func swap_shoulder() -> void:
	_sh_side_target = -_sh_side_target


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	if target == null:
		return
	_follow_prev = target.global_position
	var body_rig: Variant = target.get(&"rig")
	if body_rig is Object and (body_rig as Object).has_signal(&"footstep"):
		var sig_owner := body_rig as Object
		if not sig_owner.is_connected(&"footstep", _on_footstep):
			sig_owner.connect(&"footstep", _on_footstep)
	if target is CollisionObject3D:
		_exclude = [(target as CollisionObject3D).get_rid()]
	if target.has_signal(&"launch_landed") and not target.is_connected(&"launch_landed", _on_launch_landed):
		target.connect(&"launch_landed", _on_launch_landed)
	if _start_shoulder:
		_start_shoulder = false
		set_mode(Mode.SHOULDER, true)


func focus_on(point: Vector3, dist: float, instant: bool = false) -> void:
	point.y = 0.0
	target_distance = clampf(dist, Tuning.CAMERA_DISTANCE_MIN, Tuning.CAMERA_DISTANCE_MAX)
	_zoom_anchor = null
	_velocity = Vector3.ZERO
	if instant:
		position = _clamp_pan(point)
		distance = target_distance
		_apply_distance()
		_focus_target = null
	else:
		_focus_target = _clamp_pan(point)


func screen_to_ground(screen_pos: Vector2) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4:
		return null
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


# --- Helpers ------------------------------------------------------------------------------------

static func _quality_tier() -> StringName:
	const PATH := "res://scripts/quality.gd"
	if not ResourceLoader.exists(PATH):
		return &"high"
	var script: Variant = load(PATH)
	if script is GDScript and (script as GDScript).can_instantiate():
		return StringName((script as GDScript).call(&"tier"))
	return &"high"


func _has_player() -> bool:
	return follow_target != null and is_instance_valid(follow_target) and follow_target.is_inside_tree()


func _player_position() -> Vector3:
	return follow_target.get_global_transform_interpolated().origin


func _clamp_pan(p: Vector3) -> Vector3:
	var lim: float = Tuning.CAMERA_PAN_LIMIT + Tuning.LAUNCH_PAN_LIMIT_EXTRA * _launch_w
	return Vector3(clampf(p.x, -lim, lim), 0.0, clampf(p.z, -lim, lim))


func _iso_active() -> bool:
	return mode == Mode.ISO and _blend_t >= 1.0


func _iso_pose() -> Array:
	var yaw: float = deg_to_rad(Tuning.CAMERA_YAW_DEG)
	var pitch: float = deg_to_rad(pitch_deg)
	var dir := Vector3(cos(-pitch) * sin(yaw), sin(-pitch), cos(-pitch) * cos(yaw))
	var q: Quaternion = Basis.looking_at(-dir, Vector3.UP).get_rotation_quaternion()
	var look: Vector3 = global_position
	var dist: float = distance
	if _launch_w > 0.0 and _launch_dist > 0.0:
		var e: float = _launch_w * _launch_w * (3.0 - 2.0 * _launch_w)
		look = look.lerp(_launch_look, e)
		dist = lerpf(distance, _launch_dist, e)
	return [look, q, dist, Tuning.CAMERA_FOV, Tuning.CAMERA_NEAR_ISO]


func _target_pose() -> Array:
	return _shoulder_pose() if mode == Mode.SHOULDER and _has_player() else _iso_pose()


func _set_out_pose(pose: Array) -> void:
	_out_look = pose[0]
	_out_quat = pose[1]
	_out_dist = pose[2]
	_out_fov = pose[3]
	_out_near = pose[4]


func _apply_pose_to_camera() -> void:
	var b := Basis(_out_quat)
	camera.global_transform = Transform3D(b, _out_look + b.z * _out_dist)
	camera.fov = _out_fov
	camera.near = _out_near


## Keeps the camera in sync with the iso pivot right away, so ground picking during zoom is exact.
func _apply_distance() -> void:
	if _iso_active():
		_set_out_pose(_iso_pose())
		_apply_pose_to_camera()


func _engage_follow(reset_distance: bool = true) -> void:
	_following = true
	_focus_target = null
	_velocity = Vector3.ZERO
	if reset_distance and target_distance > Tuning.CAMERA_FOLLOW_ENGAGE_MAX_DISTANCE:
		target_distance = Tuning.CAMERA_FOLLOW_DISTANCE
		_zoom_anchor = null


static func _ease_in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5


static func _strongest_axis(axis: JoyAxis) -> float:
	var best: float = 0.0
	for device: int in Input.get_connected_joypads():
		var v: float = Input.get_joy_axis(device, axis)
		if absf(v) > absf(best):
			best = v
	return best


static func _any_joy_button(button: JoyButton) -> bool:
	for device: int in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, button):
			return true
	return false


# --- Input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Touch drives the camera through the touch_* API; mouse events emulated from touch are ignored.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_F2:
					_dof_on = not _dof_on
				KEY_RIGHT:
					toggle_mode()
				KEY_TAB:
					if mode == Mode.SHOULDER:
						swap_shoulder()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			if jb.button_index == JOY_BUTTON_DPAD_RIGHT:
				toggle_mode()
			elif jb.button_index == JOY_BUTTON_RIGHT_STICK and mode == Mode.SHOULDER:
				swap_shoulder()
		return
	if mode == Mode.SHOULDER:
		_shoulder_mouse(event)
	else:
		_iso_mouse(event)


func _shoulder_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var dir: float = -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				_sh_target_dist = clampf(_sh_target_dist * pow(1.0 + Tuning.CAMERA_ZOOM_STEP, dir), Tuning.SHOULDER_DISTANCE_MIN, Tuning.SHOULDER_DISTANCE_MAX)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed and not _dragging:
				_dragging = true
				_drag_button = mb.button_index
				_press_pos = mb.position
				_drag_moved = false
			elif not mb.pressed and _dragging and mb.button_index == _drag_button:
				_dragging = false
				if not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
					clicked.emit(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_press_pos) < Tuning.CLICK_MAX_DRAG_PX:
			return
		_drag_moved = true
		var sens: float = deg_to_rad(Tuning.SHOULDER_MOUSE_SENSITIVITY_DEG)
		_sh_yaw -= mm.relative.x * sens
		_sh_pitch = clampf(_sh_pitch - mm.relative.y * sens, deg_to_rad(Tuning.SHOULDER_PITCH_MIN_DEG), deg_to_rad(Tuning.SHOULDER_PITCH_MAX_DEG))


func _iso_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var dir: float = -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				var factor: float = pow(1.0 + Tuning.CAMERA_ZOOM_STEP, dir * clampf(mb.factor, 1.0, 4.0))
				target_distance = clampf(target_distance * factor, Tuning.CAMERA_DISTANCE_MIN, Tuning.CAMERA_DISTANCE_MAX)
				_zoom_anchor = mb.position
				_focus_target = null
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed and not _dragging:
				var hit: Variant = screen_to_ground(mb.position)
				if hit == null:
					return
				_dragging = true
				_drag_button = mb.button_index
				_following = false
				_press_pos = mb.position
				_drag_moved = false
				_grab_point = hit
				_velocity = Vector3.ZERO
				_focus_target = null
				_last_drag_time = Time.get_ticks_msec() / 1000.0
			elif not mb.pressed and _dragging and mb.button_index == _drag_button:
				_dragging = false
				if Time.get_ticks_msec() / 1000.0 - _last_drag_time > 0.08:
					_velocity = Vector3.ZERO
				if not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
					_velocity = Vector3.ZERO
					clicked.emit(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_press_pos) < Tuning.CLICK_MAX_DRAG_PX:
			return
		_drag_moved = true
		_following = false
		var hit: Variant = screen_to_ground(mm.position)
		if hit == null:
			return
		var delta: Vector3 = _grab_point - (hit as Vector3)
		delta.y = 0.0
		var before: Vector3 = position
		position = _clamp_pan(position + delta)
		_apply_distance()
		var now: float = Time.get_ticks_msec() / 1000.0
		var dt: float = maxf(now - _last_drag_time, 1.0 / 240.0)
		_velocity = _velocity.lerp((position - before) / dt, 0.5)
		_last_drag_time = now


# --- Frame update -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if mode == Mode.SHOULDER and not _has_player():
		set_mode(Mode.ISO)
	_trauma = maxf(_trauma - Tuning.CAMERA_TRAUMA_DECAY * delta, 0.0)
	_shake_time += delta
	_update_held_zoom(delta)
	_update_launch(delta)
	_update_iso(delta)
	if mode == Mode.SHOULDER:
		_update_shoulder_controls(delta)
		_update_shoulder_juice(delta)
	else:
		_update_stick_zoom(delta)

	var target: Array = _target_pose()
	var w: float = 1.0
	if _blend_t < 1.0:
		_blend_t = minf(_blend_t + delta / Tuning.CAMERA_MODE_BLEND_TIME, 1.0)
		w = _ease_in_out(_blend_t)
		_out_look = _from_look.lerp(target[0], w)
		_out_quat = _from_quat.slerp(target[1], w)
		_out_dist = exp(lerpf(log(_from_dist), log(float(target[2])), w))
		_out_fov = lerpf(_from_fov, target[3], w)
		_out_near = lerpf(_from_near, target[4], w)
	else:
		_set_out_pose(target)
	_shoulder_weight = w if mode == Mode.SHOULDER else 1.0 - w
	_apply_pose_to_camera()
	_apply_shake()
	_update_dof(delta)
	if Engine.get_process_frames() in [380, 440, 492] and _has_player() and OS.get_cmdline_user_args().has("--cam-debug"):
		print("[dist] f=%d pivot=%.2f viking=%.2f" % [Engine.get_process_frames(), _out_dist, camera.global_position.distance_to(_player_position())])


func _is_launched() -> bool:
	if not _has_player():
		return false
	if bool(follow_target.get_meta(&"launched", false)):
		return true
	return follow_target.has_method(&"is_launched") and bool(follow_target.call(&"is_launched"))


## Flight = launch flag (meta or is_launched()) until the body is back on the ground.
func _flight_state(delta: float, raw: bool) -> bool:
	if not raw:
		_launch_rest = 0.0
		_launch_age = 0.0
		_launch_landed = false
		return false
	_launch_age += delta
	if _launch_landed:
		return false
	var body := follow_target as CharacterBody3D
	if body == null or _launch_age < Tuning.LAUNCH_LAND_GRACE:
		return true
	# A body that stopped moving (splashed down, held by a script) has landed too.
	if body.velocity.length() < Tuning.LAUNCH_REST_SPEED:
		_launch_rest += delta
	else:
		_launch_rest = 0.0
	var grounded: bool = (body.is_physics_processing() and body.is_on_floor()) or _launch_rest >= Tuning.LAUNCH_REST_TIME
	if not grounded and body.velocity.y <= Tuning.LAUNCH_LAND_MAX_VY:
		var from: Vector3 = body.global_position + Vector3.UP * 0.1
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_player_ray(from, from + Vector3.DOWN * (0.1 + Tuning.LAUNCH_LAND_PROBE)))
		grounded = not hit.is_empty()
	if grounded:
		_launch_landed = true
		return false
	return true


func _is_mounted() -> bool:
	return _has_player() and follow_target.has_method(&"is_mounted") and bool(follow_target.call(&"is_mounted"))


func _on_launch_landed(_pos: Vector3) -> void:
	_launch_landed = true


## Catapult sequence: mount/countdown -> flight -> impact hold -> swim/shore -> control back.
## `_launch_w` spans the whole sequence (iso close-up); `_chase_w` only flight + impact hold (shoulder).
func _update_launch(delta: float) -> void:
	var raw: bool = _is_launched()
	var mounted: bool = _is_mounted()
	var launched: bool = _flight_state(delta, raw)
	var body := follow_target as CharacterBody3D
	if _was_launched and not launched:
		_hold_t = Tuning.LAUNCH_IMPACT_HOLD
		_impact = _player_position() if _has_player() else _launch_look
		add_trauma(Tuning.LAUNCH_IMPACT_TRAUMA)
	_hold_t = maxf(_hold_t - delta, 0.0)
	var holding: bool = _hold_t > 0.0
	var seq: bool = mounted or raw or launched or holding
	var rate: float = Tuning.LAUNCH_BLEND_IN if seq else Tuning.LAUNCH_BLEND_OUT
	_launch_w = move_toward(_launch_w, 1.0 if seq else 0.0, rate * delta)
	_chase_w = move_toward(_chase_w, 1.0 if (launched or holding) else 0.0, (Tuning.LAUNCH_CHASE_BLEND_IN if launched or holding else Tuning.LAUNCH_BLEND_OUT) * delta)
	if _launch_w < 0.001:
		_launch_w = 0.0
		_launch_dist = -1.0
	if _launch_w > 0.0 and _has_player():
		if _launch_dist < 0.0:
			_launch_dist = _out_dist if mode == Mode.ISO else distance
			_launch_look = _out_look if mode == Mode.ISO else global_position
			_launch_dist_vel = 0.0
		var look: Vector3 = _player_position()
		if launched and body != null:
			look = _flight_look(delta, body)
		elif holding:
			look = _impact
		elif mounted:
			look += Vector3.UP * Tuning.LAUNCH_MOUNT_LOOK_LIFT
		# Punch in for the impact, starting just before touchdown so the splash already reads close.
		var impact: bool = holding or (launched and _t_land < Tuning.LAUNCH_IMPACT_LEAD)
		var target_dist: float = Tuning.LAUNCH_IMPACT_DISTANCE if impact else Tuning.LAUNCH_ISO_DISTANCE
		var k: float = Tuning.LAUNCH_IMPACT_ZOOM_STIFFNESS if impact else Tuning.LAUNCH_ZOOM_STIFFNESS
		var c: float = Tuning.LAUNCH_IMPACT_ZOOM_DAMPING if impact else Tuning.LAUNCH_ZOOM_DAMPING
		_launch_dist_vel += (k * (target_dist - _launch_dist) - c * _launch_dist_vel) * delta
		_launch_dist += _launch_dist_vel * delta
		_launch_look = _launch_look.lerp(look, 1.0 - exp(-Tuning.LAUNCH_FOLLOW_SMOOTHING * delta))
	if body != null and (launched or (raw and not holding)):
		var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if hv.length() > 1.0:
			var heading: float = lerp_angle(atan2(_launch_dir.x, _launch_dir.z), atan2(hv.x, hv.z), 1.0 - exp(-Tuning.LAUNCH_DIR_SMOOTHING * delta))
			_launch_dir = Vector3(sin(heading), 0.0, cos(heading))
			if launched:
				_launch_climb = lerpf(_launch_climb, clampf(body.velocity.y / hv.length(), -1.5, 1.5), 1.0 - exp(-Tuning.LAUNCH_DIR_SMOOTHING * delta))
	if launched and not _was_launched:
		_launch_dir = (Basis(_out_quat) * Vector3.FORWARD * Vector3(1, 0, 1)).normalized()
		_launch_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		if body != null:
			_launch_prev_vy = body.velocity.y
			if Vector2(body.velocity.x, body.velocity.z).length() > 1.0:
				_launch_dir = Vector3(body.velocity.x, 0.0, body.velocity.z).normalized()
	# After the impact hold, the shoulder rides behind the swim/shore direction and settles back to
	# the default framing (with occlusion) once control returns.
	if mode == Mode.SHOULDER and raw and not launched and not holding:
		_sh_yaw = lerp_angle(_sh_yaw, atan2(-_launch_dir.x, -_launch_dir.z), 1.0 - exp(-Tuning.LAUNCH_POST_YAW_SMOOTHING * delta))
		_sh_pitch = lerpf(_sh_pitch, deg_to_rad(Tuning.SHOULDER_PITCH_DEFAULT_DEG), 1.0 - exp(-Tuning.LAUNCH_POST_YAW_SMOOTHING * delta))
	if _was_seq and not seq and mode == Mode.SHOULDER:
		_want = Vector2.ZERO
		_pitch_lift = 0.0
		_yaw_swing = 0.0
		_arm_frac = -1.0
	_was_launched = launched
	_was_seq = seq


## Iso flight look point: between the player and the predicted landing, leaning toward the landing
## only as far as keeps the player inside the central band at LAUNCH_ISO_DISTANCE.
func _flight_look(delta: float, body: CharacterBody3D) -> Vector3:
	var v: Vector3 = body.velocity
	var g_obs: float = (_launch_prev_vy - v.y) / maxf(delta, 1e-4)
	_launch_prev_vy = v.y
	if g_obs > 1.0 and g_obs < 200.0:
		_launch_gravity = lerpf(_launch_gravity, g_obs, 1.0 - exp(-Tuning.LAUNCH_GRAVITY_SMOOTHING * delta))
	var p: Vector3 = _player_position()
	var g: float = maxf(_launch_gravity, 0.1)
	var t_land: float = (v.y + sqrt(maxf(v.y * v.y + 2.0 * g * maxf(p.y, 0.0), 0.0))) / g
	var landing := Vector3(p.x + v.x * t_land, 0.0, p.z + v.z * t_land)
	_t_land = t_land
	var basis := Basis(Quaternion(_iso_pose()[1]))
	var sep: Vector3 = p - landing
	var sx: float = absf(sep.dot(basis.x))
	var sy: float = absf(sep.dot(basis.y))
	var tan_v: float = tan(deg_to_rad(Tuning.CAMERA_FOV) * 0.5)
	var tan_h: float = tan_v * _aspect()
	var d_now: float = minf(Tuning.LAUNCH_ISO_DISTANCE, _launch_dist) if _launch_dist > 0.0 else Tuning.LAUNCH_ISO_DISTANCE
	var b: float = Tuning.LAUNCH_LANDING_BIAS
	if sy > 0.01:
		b = minf(b, Tuning.LAUNCH_CENTER_NDC * d_now * tan_v / sy)
	if sx > 0.01:
		b = minf(b, Tuning.LAUNCH_CENTER_NDC * d_now * tan_h / sx)
	return p.lerp(landing, b)


func _update_held_zoom(delta: float) -> void:
	var z: float = 0.0
	if Input.is_physical_key_pressed(KEY_UP) or _any_joy_button(JOY_BUTTON_DPAD_UP):
		z -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or _any_joy_button(JOY_BUTTON_DPAD_DOWN):
		z += 1.0
	if z == 0.0:
		return
	if mode == Mode.SHOULDER:
		_sh_target_dist = clampf(_sh_target_dist * exp(z * Tuning.SHOULDER_KEY_ZOOM_SPEED * delta), Tuning.SHOULDER_DISTANCE_MIN, Tuning.SHOULDER_DISTANCE_MAX)
		return
	target_distance = clampf(target_distance * exp(z * Tuning.CAMERA_KEY_ZOOM_SPEED * delta), Tuning.CAMERA_DISTANCE_MIN, Tuning.CAMERA_DISTANCE_MAX)
	_zoom_anchor = null
	if _has_player():
		follow_locked = false
		if not _following:
			_engage_follow(false)


func _update_iso(delta: float) -> void:
	_update_follow(delta)
	if not _dragging and _velocity.length_squared() > 0.0001:
		position = _clamp_pan(position + _velocity * delta)
		_velocity *= exp(-Tuning.CAMERA_INERTIA_DAMPING * delta)

	if _focus_target != null:
		position = position.lerp(_focus_target, 1.0 - exp(-Tuning.CAMERA_FOCUS_SMOOTHING * delta))
		if position.distance_to(_focus_target) < 0.01:
			_focus_target = null

	if absf(distance - target_distance) > 0.001:
		var anchor_before: Variant = screen_to_ground(_zoom_anchor) if _zoom_anchor != null and _iso_active() else null
		distance = lerpf(distance, target_distance, 1.0 - exp(-Tuning.CAMERA_ZOOM_SMOOTHING * delta))
		if absf(distance - target_distance) < 0.005:
			distance = target_distance
		_apply_distance()
		if anchor_before != null:
			var anchor_after: Variant = screen_to_ground(_zoom_anchor)
			if anchor_after != null:
				var shift: Vector3 = (anchor_before as Vector3) - (anchor_after as Vector3)
				position = _clamp_pan(position + Vector3(shift.x, 0, shift.z))
		if distance == target_distance:
			_zoom_anchor = null
	_apply_distance()


func _update_follow(delta: float) -> void:
	if not _has_player() or (follow_locked and _launch_w <= 0.0):
		_following = false
		return
	var pos: Vector3 = _player_position()
	if _launch_w > 0.0 and not _following:
		_engage_follow(false)
	var moving: bool = follow_target.has_method(&"is_moving") and bool(follow_target.call(&"is_moving"))
	if moving and not _following and not _dragging:
		_engage_follow()
	var vel: Vector3 = (pos - _follow_prev) / maxf(delta, 1e-4)
	_follow_prev = pos
	vel.y = 0.0
	var w: float = _launch_w
	var ahead: Vector3 = (vel * Tuning.CAMERA_LOOKAHEAD_TIME).limit_length(Tuning.CAMERA_LOOKAHEAD_MAX) * (1.0 - w)
	_lookahead = _lookahead.lerp(ahead, 1.0 - exp(-Tuning.CAMERA_LOOKAHEAD_SMOOTHING * delta))
	if not _following:
		return
	var lim: float = Tuning.CAMERA_PAN_LIMIT + Tuning.LAUNCH_PAN_LIMIT_EXTRA * w
	var target: Vector3 = Vector3(pos.x, 0.0, pos.z) + _lookahead
	var desired := Vector3(clampf(target.x, -lim, lim), 0.0, clampf(target.z, -lim, lim))
	position = position.lerp(desired, 1.0 - exp(-lerpf(Tuning.CAMERA_FOLLOW_SMOOTHING, Tuning.LAUNCH_FOLLOW_SMOOTHING, w) * delta))


func _update_stick_zoom(delta: float) -> void:
	var axis: float = _strongest_axis(JOY_AXIS_RIGHT_Y)
	if absf(axis) < Tuning.STICK_ZOOM_DEADZONE:
		return
	var k: float = (absf(axis) - Tuning.STICK_ZOOM_DEADZONE) / (1.0 - Tuning.STICK_ZOOM_DEADZONE) * signf(axis)
	target_distance = clampf(target_distance * exp(k * Tuning.STICK_ZOOM_SPEED * delta), Tuning.CAMERA_DISTANCE_MIN, Tuning.CAMERA_DISTANCE_MAX)
	_zoom_anchor = null


# --- Shoulder mode ------------------------------------------------------------------------------

func _update_shoulder_controls(delta: float) -> void:
	var stick := Vector2(_strongest_axis(JOY_AXIS_RIGHT_X), _strongest_axis(JOY_AXIS_RIGHT_Y))
	var mag: float = stick.length()
	var target_rate := Vector2.ZERO
	if mag > Tuning.SHOULDER_STICK_DEADZONE:
		var shaped: float = pow(clampf((mag - Tuning.SHOULDER_STICK_DEADZONE) / (1.0 - Tuning.SHOULDER_STICK_DEADZONE), 0.0, 1.0), Tuning.SHOULDER_STICK_CURVE)
		_stick_hold = minf(_stick_hold + delta, Tuning.SHOULDER_STICK_BOOST_TIME)
		var boost: float = lerpf(1.0, Tuning.SHOULDER_STICK_BOOST, smoothstep(0.0, Tuning.SHOULDER_STICK_BOOST_TIME, _stick_hold) * shaped)
		var d: Vector2 = stick / mag * shaped
		target_rate = Vector2(d.x * Tuning.SHOULDER_STICK_YAW_SPEED_DEG * boost, d.y * Tuning.SHOULDER_STICK_PITCH_SPEED_DEG)
	else:
		_stick_hold = 0.0
	_stick_rate = _stick_rate.lerp(target_rate, 1.0 - exp(-Tuning.SHOULDER_STICK_SMOOTHING * delta))
	_sh_yaw -= deg_to_rad(_stick_rate.x) * delta
	_sh_pitch = clampf(_sh_pitch - deg_to_rad(_stick_rate.y) * delta, deg_to_rad(Tuning.SHOULDER_PITCH_MIN_DEG), deg_to_rad(Tuning.SHOULDER_PITCH_MAX_DEG))
	_sh_yaw = wrapf(_sh_yaw, -PI, PI)
	_sh_dist = lerpf(_sh_dist, _sh_target_dist, 1.0 - exp(-Tuning.SHOULDER_DISTANCE_SMOOTHING * delta))
	_sh_side = lerpf(_sh_side, _sh_side_target, 1.0 - exp(-Tuning.SHOULDER_SWAP_SMOOTHING * delta))


func _update_shoulder_juice(delta: float) -> void:
	var vel := Vector3.ZERO
	var body := follow_target as CharacterBody3D
	if body != null:
		vel = body.velocity
		var on_floor: bool = body.is_on_floor()
		if not on_floor:
			_airborne = true
			_air_min_vy = minf(_air_min_vy, vel.y)
		elif _airborne:
			_airborne = false
			var impact: float = -_air_min_vy
			_air_min_vy = 0.0
			if impact > Tuning.SHOULDER_LAND_MIN_SPEED:
				_bob_vel -= minf(impact * Tuning.SHOULDER_LAND_DIP_PER_SPEED, Tuning.SHOULDER_LAND_DIP_MAX)
	var hspeed: float = Vector2(vel.x, vel.z).length()
	var run: float = smoothstep(Tuning.SHOULDER_RUN_SPEED_LOW, Tuning.SHOULDER_RUN_SPEED_HIGH, hspeed)
	var k: float = Tuning.SHOULDER_SPRING_STIFFNESS
	var c: float = Tuning.SHOULDER_SPRING_DAMPING
	_bob_vel += (-k * _bob - c * _bob_vel) * delta
	_bob += _bob_vel * delta
	_sway_vel += (-k * _sway - c * _sway_vel) * delta
	_sway += _sway_vel * delta
	var fk: float = Tuning.SHOULDER_FOV_SPRING_STIFFNESS
	_fov_kick_vel += (fk * (run * Tuning.SHOULDER_RUN_FOV_KICK - _fov_kick) - Tuning.SHOULDER_FOV_SPRING_DAMPING * _fov_kick_vel) * delta
	_fov_kick += _fov_kick_vel * delta


func _on_footstep(side: int, _foot_position: Vector3, run_blend: float, move_amount: float) -> void:
	if mode != Mode.SHOULDER:
		return
	var amt: float = clampf(move_amount, 0.0, 1.0)
	_bob_vel -= lerpf(Tuning.SHOULDER_BOB_KICK_WALK, Tuning.SHOULDER_BOB_KICK_RUN, run_blend) * amt
	var s: float = 1.0 if side > 0 else -1.0
	_sway_vel += s * lerpf(Tuning.SHOULDER_SWAY_KICK_WALK, Tuning.SHOULDER_SWAY_KICK_RUN, run_blend) * amt


func _shoulder_basis(pitch: float, swing: float = 0.0) -> Basis:
	return Basis(Vector3.UP, _sh_yaw + swing) * Basis(Vector3.RIGHT, pitch)


## (tilt, swing) pairs in radians, cheapest first; built once from tuning.
func _occlusion_candidates() -> Array[Vector2]:
	if _candidates.is_empty():
		var raw: Array[Vector3] = []
		for lift_deg: float in Tuning.SHOULDER_OCCLUSION_LIFTS_DEG:
			for swing_deg: float in Tuning.SHOULDER_OCCLUSION_SWINGS_DEG:
				raw.append(Vector3(lift_deg, swing_deg, lift_deg + absf(swing_deg) * Tuning.SHOULDER_OCCLUSION_SWING_COST))
		raw.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.z < y.z)
		for r: Vector3 in raw:
			_candidates.append(Vector2(deg_to_rad(r.x), deg_to_rad(r.y)))
	return _candidates


## Camera position that puts `anchor` at the composition point for this view basis.
func _composed_position(anchor: Vector3, basis: Basis) -> Vector3:
	var tan_v: float = tan(deg_to_rad(Tuning.SHOULDER_FOV + _fov_kick) * 0.5)
	var tan_h: float = tan_v * _aspect()
	var ndc_x: float = (Tuning.SHOULDER_SCREEN_X * 2.0 - 1.0) * _sh_side
	var ndc_y: float = 1.0 - Tuning.SHOULDER_SCREEN_Y * 2.0
	var local := Vector3(ndc_x * tan_h * _sh_dist, ndc_y * tan_v * _sh_dist, -_sh_dist)
	return anchor - basis * local + basis.x * _sway


func _aspect() -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


func _candidate_fraction(anchor: Vector3, head: Vector3, cand: Vector2) -> float:
	var b: Basis = _shoulder_basis(maxf(_sh_pitch - cand.x, deg_to_rad(-80.0)), cand.y)
	return _sweep_fraction(head, _composed_position(anchor, b))


func _candidate_clear(anchor: Vector3, head: Vector3, cand: Vector2) -> bool:
	return _candidate_fraction(anchor, head, cand) >= Tuning.SHOULDER_CLEAR_FRACTION


## Fraction of the sweep from `from` to `to` that a camera-sized sphere can travel freely.
func _sweep_fraction(from: Vector3, to: Vector3) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _arm_shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = Tuning.SHOULDER_COLLISION_MASK
	query.exclude = _exclude
	var res: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var frac: float = 1.0 if res.is_empty() else res[0]
	return minf(frac, _visual_fraction(from, to))


## Building models overhang their trimmed colliders (roofs, beams), so the camera also avoids each
## building's full visual bounds, grown by the sweep radius.
func _visual_fraction(from: Vector3, to: Vector3) -> float:
	var length: float = from.distance_to(to)
	if length < 1e-4:
		return 1.0
	var best: float = 1.0
	for box: AABB in _boxes_near_player():
		if box.has_point(from):
			continue
		var hit: Variant = box.intersects_segment(from, to)
		if hit != null:
			best = minf(best, maxf(from.distance_to(hit as Vector3) / length, 0.0))
	var steps: int = Tuning.CANOPY_SAMPLES
	for c: PackedFloat32Array in _near_canopies:
		if _in_canopy(c, from):
			continue
		for i: int in range(1, steps + 1):
			var t: float = float(i) / float(steps)
			if t >= best:
				break
			if _in_canopy(c, from.lerp(to, t)):
				best = float(i - 1) / float(steps)
				break
	return best


## Canopy as a cone: full radius at its bottom, tapering to the tip, grown by the sweep radius.
static func _in_canopy(c: PackedFloat32Array, q: Vector3) -> bool:
	if q.y < c[2] or q.y > c[3]:
		return false
	var r: float = c[4] * (1.0 - (q.y - c[2]) / maxf(c[3] - c[2], 0.01)) + Tuning.SHOULDER_ARM_RADIUS
	return Vector2(q.x - c[0], q.z - c[1]).length_squared() < r * r


## Visual boxes within reach of the camera this frame (filtered once per frame).
func _boxes_near_player() -> Array[AABB]:
	var frame: int = Engine.get_process_frames()
	if frame == _near_frame:
		return _near_boxes
	_near_frame = frame
	_near_boxes.clear()
	_near_canopies.clear()
	if not _has_player():
		return _near_boxes
	var p: Vector3 = _player_position()
	var reach: float = Tuning.SHOULDER_DISTANCE_MAX + 3.0
	for c: PackedFloat32Array in _canopies:
		if absf(c[0] - p.x) - c[4] < reach and absf(c[1] - p.z) - c[4] < reach:
			_near_canopies.append(c)
	for box: AABB in _visual_boxes():
		var c: Vector3 = box.get_center()
		var half: Vector3 = box.size * 0.5
		if absf(c.x - p.x) - half.x < reach and absf(c.z - p.z) - half.z < reach:
			_near_boxes.append(box)
	return _near_boxes


func _visual_boxes() -> Array[AABB]:
	if _boxes_built:
		return _boxes
	_boxes_built = true
	var spawner: Variant = get_parent().get(&"spawner") if get_parent() != null else null
	if not (spawner is Object):
		return _boxes
	var list: Variant = (spawner as Object).get(&"buildings")
	if not (list is Array):
		return _boxes
	for b: Variant in list:
		if not (b is Dictionary):
			continue
		var slot := (b as Dictionary).get("slot") as Node3D
		var local: Variant = (b as Dictionary).get("aabb")
		if slot == null or not (local is AABB):
			continue
		_boxes.append((slot.global_transform * (local as AABB)).grow(Tuning.SHOULDER_VISUAL_MARGIN))
	_collect_canopies(get_parent())
	return _boxes


## Trees only collide at the trunk; their canopy is approximated from the trunk cylinder
## (tall, thin cylinders on the obstacle layer).
func _collect_canopies(node: Node) -> void:
	for child: Node in node.get_children():
		if child is StaticBody3D and ((child as StaticBody3D).collision_layer & 2) != 0:
			for cs: Node in child.get_children():
				var shape_node := cs as CollisionShape3D
				if shape_node == null or not (shape_node.shape is CylinderShape3D):
					continue
				var cyl := shape_node.shape as CylinderShape3D
				if cyl.height / maxf(cyl.radius, 0.01) < Tuning.CANOPY_MIN_ASPECT:
					continue
				var base: Vector3 = shape_node.global_position - Vector3.UP * cyl.height * 0.5
				_canopies.append(PackedFloat32Array([base.x, base.z, base.y + cyl.height * Tuning.CANOPY_BOTTOM_FRAC,
					base.y + cyl.height * Tuning.CANOPY_TOP_FRAC, cyl.radius * Tuning.CANOPY_RADIUS_SCALE]))
		elif child.get_child_count() > 0:
			_collect_canopies(child)


func _shoulder_pose() -> Array:
	if _chase_w >= 0.999:
		return _chase_pose()
	var pose: Array = _shoulder_framing_pose()
	if _chase_w <= 0.0:
		return pose
	var chase: Array = _chase_pose()
	var w: float = _chase_w
	return [(pose[0] as Vector3).lerp(chase[0], w), (pose[1] as Quaternion).slerp(chase[1], w),
		lerpf(pose[2], chase[2], w), lerpf(pose[3], chase[3], w), pose[4]]


## Behind the flight direction and a bit above, aiming slightly ahead along the arc.
func _chase_pose() -> Array:
	var p: Vector3 = _player_position() + Vector3.UP * Tuning.SHOULDER_ANCHOR_HEIGHT
	var cam: Vector3 = p - _launch_dir * Tuning.LAUNCH_CHASE_DISTANCE + Vector3.UP * Tuning.LAUNCH_CHASE_HEIGHT
	cam = p.lerp(cam, maxf(_sweep_fraction(p, cam), Tuning.SHOULDER_VIS_MIN_DISTANCE / maxf(p.distance_to(cam), 0.01)))
	var aim: Vector3 = p + (_launch_dir + Vector3.UP * (_launch_climb * Tuning.LAUNCH_CHASE_CLIMB_INFLUENCE - Tuning.LAUNCH_CHASE_DOWN_TILT)).normalized() * Tuning.LAUNCH_CHASE_AIM_AHEAD
	var q: Quaternion = Basis.looking_at((aim - cam).normalized(), Vector3.UP).get_rotation_quaternion()
	var d: float = cam.distance_to(aim)
	return [aim, q, d, Tuning.LAUNCH_CHASE_FOV, Tuning.SHOULDER_NEAR]


func _shoulder_framing_pose() -> Array:
	var delta: float = get_process_delta_time()
	var feet: Vector3 = _player_position()
	var anchor: Vector3 = feet + Vector3.UP * (Tuning.SHOULDER_ANCHOR_HEIGHT + _bob)
	var head: Vector3 = feet + Vector3.UP * Tuning.SHOULDER_PIVOT_HEIGHT

	# Default framing wins whenever it is clear; otherwise keep the current fallback while it stays
	# clear (no flip-flopping), else pick the cheapest clear (tilt down, yaw swing).
	var want_lift: float = _want.x
	var want_swing: float = _want.y
	if _candidate_clear(anchor, head, Vector2.ZERO):
		want_lift = 0.0
		want_swing = 0.0
	elif _want == Vector2.ZERO or not _candidate_clear(anchor, head, _want):
		var best_frac: float = -1.0
		for cand: Vector2 in _occlusion_candidates():
			var frac: float = _candidate_fraction(anchor, head, cand)
			if frac > best_frac + 0.05:
				best_frac = frac
				want_lift = cand.x
				want_swing = cand.y
			if frac >= Tuning.SHOULDER_CLEAR_FRACTION:
				want_lift = cand.x
				want_swing = cand.y
				break
	_want = Vector2(want_lift, want_swing)
	var lift_rate: float = Tuning.SHOULDER_LIFT_RISE_SMOOTHING if want_lift > _pitch_lift else Tuning.SHOULDER_LIFT_FALL_SMOOTHING
	_pitch_lift = lerpf(_pitch_lift, want_lift, 1.0 - exp(-lift_rate * delta))
	var swing_rate: float = Tuning.SHOULDER_LIFT_RISE_SMOOTHING if absf(want_swing) > absf(_yaw_swing) else Tuning.SHOULDER_LIFT_FALL_SMOOTHING
	_yaw_swing = lerp_angle(_yaw_swing, want_swing, 1.0 - exp(-swing_rate * delta))

	var basis: Basis = _shoulder_basis(maxf(_sh_pitch - _pitch_lift, deg_to_rad(-80.0)), _yaw_swing)
	var desired: Vector3 = _composed_position(anchor, basis)
	var frac_now: float = _sweep_fraction(head, desired)
	if _arm_frac < 0.0 or frac_now < _arm_frac:
		_arm_frac = frac_now
	else:
		_arm_frac = lerpf(_arm_frac, frac_now, 1.0 - exp(-Tuning.SHOULDER_ARM_RETURN_SMOOTHING * delta))
	var cam_pos: Vector3 = head.lerp(desired, _arm_frac)

	# The player must stay visible: if something still sits between camera and chest, move in front of it.
	var to_cam: Vector3 = cam_pos - anchor
	var vis: Dictionary = get_world_3d().direct_space_state.intersect_ray(_player_ray(anchor, cam_pos))
	var vis_len: float = to_cam.length()
	if not vis.is_empty():
		vis_len = anchor.distance_to(vis["position"]) - Tuning.SHOULDER_ARM_RADIUS
	vis_len = minf(vis_len, to_cam.length() * _visual_fraction(anchor, cam_pos))
	if vis_len < to_cam.length():
		cam_pos = anchor + to_cam.normalized() * maxf(vis_len, Tuning.SHOULDER_VIS_MIN_DISTANCE)
	# Last resort: never end up inside the player's own head; staying readable beats a foliage graze.
	var from_anchor: Vector3 = cam_pos - anchor
	if from_anchor.length() < Tuning.SHOULDER_VIS_MIN_DISTANCE:
		var away: Vector3 = from_anchor.normalized() if from_anchor.length() > 0.05 else basis.z
		cam_pos = anchor + away * Tuning.SHOULDER_VIS_MIN_DISTANCE

	# Re-aim at the anchor when the camera had to leave the composed spot.
	var off: float = clampf(cam_pos.distance_to(desired) / maxf(_sh_dist * 0.5, 0.01), 0.0, 1.0)
	_aim_blend = lerpf(_aim_blend, off, 1.0 - exp(-Tuning.SHOULDER_AIM_SMOOTHING * delta))
	var q: Quaternion = basis.get_rotation_quaternion()
	var to_anchor: Vector3 = anchor - cam_pos
	if _aim_blend > 0.001 and to_anchor.length() > 0.05:
		var look_q: Quaternion = Basis.looking_at(to_anchor.normalized(), Vector3.UP).get_rotation_quaternion()
		q = q.slerp(look_q, _aim_blend)
	var fwd: Vector3 = -(Basis(q).z)
	var look_dist: float = maxf(to_anchor.length(), 0.5)
	return [cam_pos + fwd * look_dist, q, look_dist, Tuning.SHOULDER_FOV + _fov_kick, Tuning.SHOULDER_NEAR]


# --- Shake and depth of field -------------------------------------------------------------------

func _apply_shake() -> void:
	var s: float = _trauma * _trauma
	if s <= 0.0:
		return
	var t: float = _shake_time * Tuning.CAMERA_SHAKE_FREQUENCY
	var n := Vector3(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(t, 37.0), _noise.get_noise_2d(t, 91.0))
	var fov_scale: float = camera.fov / Tuning.CAMERA_SHAKE_REF_FOV
	var ang: Vector3 = n * Tuning.CAMERA_SHAKE_MAX_ANGLE_DEG * (s * fov_scale)
	var xf: Transform3D = camera.global_transform
	var offset := Vector3(_noise.get_noise_2d(t, 143.0), _noise.get_noise_2d(t, 211.0), 0.0) * Tuning.CAMERA_SHAKE_MAX_OFFSET * s
	xf.origin += xf.basis * offset
	xf.basis = xf.basis * Basis.from_euler(Vector3(deg_to_rad(ang.x), deg_to_rad(ang.y), deg_to_rad(ang.z)))
	camera.global_transform = xf
	camera.fov *= 1.0 - s * Tuning.CAMERA_SHAKE_ZOOM_PUNCH


func _player_ray(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to, Tuning.SHOULDER_COLLISION_MASK)
	if follow_target is CollisionObject3D:
		query.exclude = [(follow_target as CollisionObject3D).get_rid()]
	return query


func _shoulder_focus(cam_xf: Transform3D) -> float:
	var from: Vector3 = cam_xf.origin
	var to: Vector3 = from - cam_xf.basis.z * Tuning.DOF_SHOULDER_RAY_LENGTH
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_player_ray(from, to))
	if hit.is_empty():
		return Tuning.DOF_SHOULDER_RAY_LENGTH
	return maxf(from.distance_to(hit["position"]), Tuning.DOF_SHOULDER_FOCUS_MIN)


func _update_dof(delta: float) -> void:
	if not _dof_on:
		_attributes.dof_blur_far_enabled = false
		_attributes.dof_blur_near_enabled = false
		return
	var cam_xf: Transform3D = camera.global_transform
	var w: float = _shoulder_weight
	var iso_point: Vector3 = _player_position() if (_following or _launch_w > 0.0) and _has_player() else global_position
	var f_iso: float = cam_xf.origin.distance_to(iso_point)
	var target: float = f_iso
	if w > 0.0 and _has_player():
		target = lerpf(f_iso, _shoulder_focus(cam_xf), w)
	if _focus_distance < 0.0:
		_focus_distance = target
	else:
		_focus_distance = lerpf(_focus_distance, target, 1.0 - exp(-Tuning.DOF_FOCUS_SMOOTHING * delta))
	var f: float = _focus_distance
	var zoom_t: float = clampf(inverse_lerp(Tuning.CAMERA_DISTANCE_MAX, Tuning.CAMERA_DISTANCE_MIN, _out_dist if mode == Mode.ISO else distance), 0.0, 1.0)
	var iso_amount: float = lerpf(Tuning.DOF_ISO_AMOUNT_ZOOMED_OUT, Tuning.DOF_ISO_AMOUNT_ZOOMED_IN, zoom_t) * lerpf(1.0, Tuning.LAUNCH_DOF_STRENGTH_SCALE, _launch_w)
	var sh_far: float = f + maxf(Tuning.DOF_SHOULDER_FAR_OFFSET_MIN, f * Tuning.DOF_SHOULDER_FAR_OFFSET_FRAC)
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_far_distance = lerpf(f * (1.0 + Tuning.DOF_ISO_FAR_START_FRAC), sh_far, w)
	_attributes.dof_blur_far_transition = lerpf(f * Tuning.DOF_ISO_FAR_TRANSITION_FRAC, Tuning.DOF_SHOULDER_FAR_TRANSITION, w)
	_attributes.dof_blur_near_enabled = w < 0.5
	_attributes.dof_blur_near_distance = f * (1.0 - Tuning.DOF_ISO_NEAR_START_FRAC)
	_attributes.dof_blur_near_transition = f * Tuning.DOF_ISO_NEAR_TRANSITION_FRAC
	_attributes.dof_blur_amount = lerpf(iso_amount, Tuning.DOF_SHOULDER_AMOUNT, w) * (Tuning.DOF_MOBILE_AMOUNT_SCALE if _mobile else 1.0)
