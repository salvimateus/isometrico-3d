extends Node3D

## Procedural visual of the viking: builds the body from rounded primitives and animates gait, air,
## skid, idle fidgets, squash/stretch and secondary motion. Pure visual, top-level and not physics
## interpolated: the owner places it every rendered frame with `place()` and drives it with `animate()`.

signal footstep(side: int, foot_position: Vector3, run_blend: float, move_amount: float)

const T := preload("res://scripts/character/character_tuning.gd")
const Mats := preload("res://scripts/character/character_materials.gd")

const Sculpt := preload("res://scripts/character/sculpt_mesh.gd")
const Q := preload("res://scripts/character/char_quality.gd")
const Baker := preload("res://scripts/character/rig_baker.gd")
const HAIR_TOP: Color = Color("F2C14E")
const HAIR_BOTTOM: Color = Color("BF8020")

const HIP_HEIGHT: float = 0.33
const SHIELD_TILT_DEG: float = 12.0
const AXE_PITCH_DEG: float = -95.0
const BROW_PIVOT := Vector3(0.08, 0.25, 0.2)
const STACHE_PIVOT := Vector3(0.0, 0.112, 0.236)
const JAW_HINGE := Vector3(0.0, 0.17, 0.0)
# Haft angled outward so the blade face shows in three-quarters even when he faces the camera.
const AXE_OUT_DEG: float = -55.0
const AXE_ROLL_DEG: float = 0.0
const ARM_OUT_MAX: float = 0.75
const FUR_ROOT: Color = Color("7A4A28")
const FUR_ROOT_ALT: Color = Color("9C6436")
const FUR_TIP: Color = Color("EAD6B0")
const FUR_BODY_TOP: Color = Color("9C6436")
const FUR_BODY_BOTTOM: Color = Color("7A4A28")
const HAIR_LIGHT: Color = Color("F5BE3A")

enum Fidget { NONE, FLEX, AXE_TWIRL, WEIGHT_SHIFT, FOOT_TAP }
enum Mood { NORMAL, NERVOUS, FLAIL, DOWNED, GETUP, SWIM }

static var _mesh_cache: Dictionary = {}

var _blob: MeshInstance3D
var _squash_node: Node3D
var _hips: Node3D
var _torso: Node3D
var _chest: Node3D
var _head: Node3D
var _shield: Node3D
var _axe: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _boot_l: Node3D
var _boot_r: Node3D
var _braids: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _scleras: Array[Node3D] = []
var _mouth: Node3D
var _jaw: Node3D
var _stache_l: Node3D
var _stache_r: Node3D
var _brow_l: Node3D
var _brow_r: Node3D
var _scream: float = 0.0
var _spit: float = 0.0
var _shake: float = 0.0
var _drip_left: float = 0.0
var _drip: CPUParticles3D
var _stars: Node3D
var _sweat: CPUParticles3D
var _mood: Mood = Mood.NORMAL
var _mood_t: float = 0.0
var _mood_w: float = 0.0
var _down_face: bool = true
var _scared: float = 0.0
# Spring-driven locks: {node, layer, root, basis}.
var _locks: Array[Dictionary] = []
# One pivot per (parent, layer) once the locks are grouped: {node, layer, origin}.
var _hair_pivots: Array[Dictionary] = []
var _hair_x: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hair_xv: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hair_lift: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hair_liftv: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hair_sway: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _hair_swayv: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _lock_rng := RandomNumberGenerator.new()

var _phase: float = 0.0
var _move_amount: float = 0.0
var _run_blend: float = 0.0
var _air: float = 0.0
var _skid: float = 0.0
var _wade: float = 0.0
var _stumble_t: float = -1.0
var _time: float = 0.0
var _squash: float = 0.0
var _squash_vel: float = 0.0
var _jiggle: float = 0.0
var _jiggle_vel: float = 0.0
var _lean: float = 0.0
var _bank: float = 0.0
var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _look_timer: float = T.IDLE_LOOK_INTERVAL
var _look_target: float = 0.0
var _look: float = 0.0
var _fidget: Fidget = Fidget.NONE
var _fidget_t: float = 0.0
var _fidget_timer: float = 3.0
var _fidget_side: float = 1.0
var _rng := RandomNumberGenerator.new()
var _prewarm_frames: int = 3


func _ready() -> void:
	_set_prewarm(true)


## Shows every mood-only part (scream mouth, split mustache pose, wide eyes, stars, sweat drops) for the
## first frames, shrunk inside the head, so their shaders compile at load and not mid-flight.
func _set_prewarm(on: bool) -> void:
	_mouth.visible = on
	_stars.visible = on
	for sc: Node3D in _scleras:
		sc.visible = on
	if on:
		_stars.scale = Vector3.ONE * 0.01
		var warm := MeshInstance3D.new()
		warm.name = "PrewarmSweat"
		warm.mesh = _sweat.mesh
		warm.scale = Vector3.ONE * 0.01
		warm.position = Vector3(0.0, 0.17, 0.0)
		_head.add_child(warm)
		var warm_drip := warm.duplicate() as MeshInstance3D
		warm_drip.name = "PrewarmDrip"
		warm_drip.mesh = _drip.mesh
		_head.add_child(warm_drip)
	else:
		_stars.scale = Vector3.ONE
		for n: String in ["PrewarmSweat", "PrewarmDrip"]:
			var w: Node = _head.get_node_or_null(n)
			if w != null:
				w.queue_free()


func _init() -> void:
	name = "Rig"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	_build()
	_group_locks()
	_bake()


## Places the rig at the feet with a facing yaw (radians, 0 = +Z).
func place(feet: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * T.VISUAL_SCALE), feet)


## Places the rig with a full orientation (used while riding, tumbling or lying down).
func place_transform(xf: Transform3D) -> void:
	global_transform = Transform3D(xf.basis.orthonormalized().scaled(Vector3.ONE * T.VISUAL_SCALE), xf.origin)


func kick_squash(amount: float) -> void:
	_squash_vel += amount


## Takeoff: a visual-only squash preset that springs straight into a stretch.
func jump_kick() -> void:
	_squash = T.SQUASH_JUMP_PRESET
	_squash_vel = T.SQUASH_JUMP_KICK
	for l: int in _hair_liftv.size():
		_hair_liftv[l] += T.HAIR_JUMP_KICK * T.HAIR_GAIN[l] * 10.0


## Knocked off balance by a wave: a short flailing wobble.
func stumble() -> void:
	_stumble_t = 0.0
	_squash_vel += T.SQUASH_BUMP_KICK


## Catapult ride states. `face_down` only matters for DOWNED (face plant vs. landing on the butt).
func set_mood(mood: Mood, face_down: bool = true) -> void:
	if mood == _mood:
		return
	_mood = mood
	_mood_t = 0.0
	_down_face = face_down
	if mood == Mood.NORMAL:
		_mood_w = 0.0


## Water-landing face controls while in SWIM: spit (mouth squirt, 0..1) and shake (head shake + spray, 0..1).
func set_water_fx(spit: float, shake: float) -> void:
	_spit = spit
	_shake = shake


## Drops falling off the body for `seconds` (after climbing out of water).
func start_drip(seconds: float) -> void:
	_drip_left = seconds


func get_mood() -> Mood:
	return _mood


func land_kick(fall_speed: float) -> void:
	_squash_vel = minf(_squash_vel, 0.0) + T.SQUASH_LAND_KICK_PER_SPEED * fall_speed
	_jiggle_vel -= fall_speed * 0.05
	for l: int in _hair_liftv.size():
		_hair_liftv[l] += T.HAIR_LAND_KICK * T.HAIR_GAIN[l] * fall_speed


## height: distance from the feet to the ground below (0 when grounded). Keeps the blob shadow on the ground.
func set_ground_gap(height: float) -> void:
	var h: float = maxf(height, 0.0)
	_blob.position.y = 0.015 - h / T.VISUAL_SCALE
	var k: float = clampf(1.0 - h * 0.35, 0.45, 1.0)
	_blob.scale = Vector3(k, 1.0, k)


## speed: horizontal m/s. run_target/skid_target/wade_target: 0..1. forward_accel: m/s² along facing. yaw_rate: rad/s.
func animate(delta: float, speed: float, run_target: float, forward_accel: float, yaw_rate: float, airborne: bool, vertical_speed: float, skid_target: float, wade_target: float = 0.0) -> void:
	_time += delta
	var target_move: float = clampf(speed / T.WALK_SPEED, 0.0, 1.0)
	_move_amount = lerpf(_move_amount, target_move, 1.0 - exp(-T.GAIT_BLEND_SPEED * delta))
	_run_blend = lerpf(_run_blend, run_target, 1.0 - exp(-T.RUN_BLEND_SPEED * delta))
	_air = lerpf(_air, 1.0 if airborne else 0.0, 1.0 - exp(-T.AIR_BLEND_SPEED * delta))
	_skid = lerpf(_skid, skid_target, 1.0 - exp(-12.0 * delta))
	_wade = lerpf(_wade, wade_target, 1.0 - exp(-T.WADE_BLEND_SPEED * delta))
	var stumble_e: float = 0.0
	if _stumble_t >= 0.0:
		_stumble_t += delta
		var sk: float = _stumble_t / T.STUMBLE_TIME
		if sk >= 1.0:
			_stumble_t = -1.0
		else:
			stumble_e = sin(PI * sk)
	var wade: float = _wade
	var air: float = _air
	var ground: float = 1.0 - air
	var mv: float = _move_amount * (1.0 - _skid * 0.6)
	var rb: float = _run_blend
	var idle_w: float = (1.0 - _move_amount) * ground

	var stride: float = lerpf(T.WALK_STRIDE, T.RUN_STRIDE, rb)
	var prev_phase: float = _phase
	_phase += speed * delta / stride * PI * ground * (1.0 - _skid)
	if not airborne:
		_emit_contacts(prev_phase, _phase, rb, mv)

	var p: float = _phase
	var s: float = sin(p) * ground
	var c: float = cos(p)

	# Squash spring plus vertical-speed stretch in the air.
	var acc: float = -T.SQUASH_STIFFNESS * _squash - T.SQUASH_DAMPING * _squash_vel
	_squash_vel += acc * delta
	_squash = clampf(_squash + _squash_vel * delta, -T.SQUASH_MAX, T.SQUASH_MAX)
	var fidget_e: float = _update_fidget(delta, idle_w)
	var stretch: float = _squash + absf(vertical_speed) * T.AIR_STRETCH_PER_SPEED * air
	if _fidget == Fidget.FLEX:
		stretch += 0.05 * fidget_e
	stretch = clampf(stretch, -T.SQUASH_MAX, T.SQUASH_MAX)
	_squash_node.scale = Vector3(1.0 - stretch * 0.5, 1.0 + stretch, 1.0 - stretch * 0.5)

	# Lean, skid lean-back, air tilt and bank into turns.
	var lean_target: float = deg_to_rad(lerpf(T.WALK_LEAN_DEG, T.RUN_LEAN_DEG, rb)) * _move_amount * ground
	lean_target += clampf(deg_to_rad(T.ACCEL_LEAN_DEG) * forward_accel, -deg_to_rad(T.MAX_ACCEL_LEAN_DEG), deg_to_rad(T.MAX_ACCEL_LEAN_DEG)) * ground
	lean_target -= deg_to_rad(T.SKID_LEAN_BACK_DEG) * _skid
	lean_target += deg_to_rad(8.0) * air * clampf(-vertical_speed * 0.3, -1.0, 1.0)
	lean_target += deg_to_rad(T.WADE_LEAN_DEG) * wade * _move_amount
	lean_target -= deg_to_rad(22.0) * stumble_e
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-10.0 * delta))
	var bank_target: float = clampf(-yaw_rate * deg_to_rad(T.BANK_DEG_PER_RAD_S) * _move_amount, -deg_to_rad(T.MAX_BANK_DEG), deg_to_rad(T.MAX_BANK_DEG))
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-8.0 * delta))

	var bob: float = lerpf(T.WALK_BOB, T.RUN_BOB, rb) * mv * absf(c) * ground
	var breath: float = sin(_time * T.BREATH_RATE)
	var shift: float = fidget_e * _fidget_side if _fidget == Fidget.WEIGHT_SHIFT else 0.0
	_hips.position = Vector3(0.035 * shift, HIP_HEIGHT + bob - 0.012 * breath * idle_w, 0.0)
	_hips.rotation = Vector3(
		_lean,
		s * deg_to_rad(T.HIP_TWIST_DEG) * mv,
		_bank + sin(_time * 0.9) * deg_to_rad(T.IDLE_SWAY_DEG) * idle_w + 0.09 * shift
	)

	# Shoulders swing against the hips; heavier with the run.
	var shoulder_k: float = mv * (0.5 + rb)
	_chest.rotation = Vector3(
		0.0,
		-s * deg_to_rad(T.SHOULDER_TWIST_DEG) * shoulder_k - _hips.rotation.y,
		sin(p * 2.0) * deg_to_rad(T.SHOULDER_ROLL_DEG) * rb * mv * ground
	)
	var breath_k: float = T.BREATH_AMOUNT * breath * idle_w
	_torso.scale = Vector3(1.0 + 0.4 * breath_k, 1.0 + breath_k, 1.0 + 0.4 * breath_k)

	# Legs: negative X rotation swings the foot forward.
	var leg_amp: float = deg_to_rad(lerpf(T.WALK_LEG_SWING_DEG, T.RUN_LEG_SWING_DEG, rb)) * mv
	var lift: float = (lerpf(T.WALK_FOOT_LIFT, T.RUN_FOOT_LIFT, rb) + T.WADE_FOOT_LIFT * wade) * mv * ground
	var leg_l_x: float = -s * leg_amp - _lean * 0.8
	var leg_r_x: float = s * leg_amp - _lean * 0.8
	leg_l_x = lerpf(leg_l_x, -0.75, air)
	leg_r_x = lerpf(leg_r_x, 0.4, air)
	leg_l_x = lerpf(leg_l_x, -0.7, _skid)
	leg_r_x = lerpf(leg_r_x, 0.25, _skid)
	if _fidget == Fidget.FOOT_TAP:
		leg_r_x -= 0.35 * fidget_e * maxf(0.0, sin(_fidget_t / T.FIDGET_DURATION * TAU * 3.0))
	_leg_l.rotation = Vector3(leg_l_x, -_hips.rotation.y, 0.0)
	_leg_r.rotation = Vector3(leg_r_x, -_hips.rotation.y, 0.0)
	_leg_l.position.y = maxf(0.0, c) * lift + 0.06 * air
	_leg_r.position.y = maxf(0.0, -c) * lift + 0.02 * air

	# Arms pump in counter-phase; flail up in the air and on a skid.
	var arm_amp: float = deg_to_rad(lerpf(T.WALK_ARM_SWING_DEG, T.RUN_ARM_SWING_DEG, rb)) * mv
	var arm_bias: float = -deg_to_rad(T.RUN_ARM_BEND_DEG) * rb * mv
	var arm_out: float = deg_to_rad(12.0 + 3.0 * breath * idle_w + 6.0 * rb * mv)
	var air_arm_x: float = 0.35 if vertical_speed > 0.0 else -0.9
	var arm_l_x: float = lerpf(s * arm_amp + arm_bias, air_arm_x, air)
	var arm_r_x: float = lerpf(-s * arm_amp + arm_bias, air_arm_x, air)
	arm_out = lerpf(arm_out, 0.6, air)
	arm_l_x = lerpf(arm_l_x, 0.6, _skid)
	arm_r_x = lerpf(arm_r_x, 0.6, _skid)
	arm_out = lerpf(arm_out, 0.9, _skid)
	# Wading: arms held up and out of the water; stumbling: windmill flail.
	arm_out += deg_to_rad(T.WADE_ARM_RAISE_DEG) * wade + 0.9 * stumble_e
	arm_l_x = lerpf(arm_l_x, -0.35 + 0.25 * s, wade * 0.7) - 1.6 * stumble_e * (0.5 + 0.5 * sin(_time * 22.0))
	arm_r_x = lerpf(arm_r_x, -0.35 - 0.25 * s, wade * 0.7) - 1.6 * stumble_e * (0.5 + 0.5 * cos(_time * 22.0))
	var arm_l_z: float = arm_out
	var arm_r_z: float = -arm_out
	if _fidget == Fidget.FLEX:
		arm_l_z += 1.3 * fidget_e
		arm_r_z -= 1.3 * fidget_e
		arm_l_x -= 0.25 * fidget_e
		arm_r_x -= 0.25 * fidget_e
	elif _fidget == Fidget.AXE_TWIRL:
		arm_r_x -= 0.55 * fidget_e
	# Never a T: cap how far the upper arms lift sideways and always keep the elbows bent.
	_arm_l.rotation = Vector3(arm_l_x, 0.0, minf(arm_l_z, ARM_OUT_MAX))
	_arm_r.rotation = Vector3(arm_r_x, 0.0, maxf(arm_r_z, -ARM_OUT_MAX))
	var elbow: float = lerpf(0.3, 0.45, mv) + 0.85 * rb * mv
	elbow = lerpf(elbow, 1.0, air)
	elbow = lerpf(elbow, 0.8, _skid)
	elbow = lerpf(elbow, 1.1, wade) + 0.5 * stumble_e
	var flex_bend: float = 1.5 * fidget_e if _fidget == Fidget.FLEX else 0.0
	_fore_l.rotation.x = -(elbow + 0.2 * rb * mv * maxf(0.0, s) + flex_bend)
	_fore_r.rotation.x = -(elbow + 0.2 * rb * mv * maxf(0.0, -s) + flex_bend)

	# Head: counter twist, idle look-around, nod with the bob.
	_update_look(delta, idle_w)
	_head.rotation = Vector3(
		-_lean * 0.45 + bob * 1.2 - 0.15 * air * clampf(vertical_speed, -1.0, 1.0),
		-_chest.rotation.y * 0.6 - _hips.rotation.y * 0.5 + _look,
		-_bank * 0.4 + 0.25 * stumble_e * sin(_time * 17.0)
	)

	# Secondary motion: spring that lags the bob, lean and vertical speed.
	var jiggle_target: float = bob + _lean * 0.05 - vertical_speed * 0.012 * air
	var jacc: float = -T.JIGGLE_STIFFNESS * (_jiggle - jiggle_target) - T.JIGGLE_DAMPING * _jiggle_vel
	_jiggle_vel += jacc * delta
	_jiggle += _jiggle_vel * delta
	var lag: float = deg_to_rad(T.JIGGLE_GAIN_DEG) * (_jiggle - jiggle_target)
	_shield.rotation.x = deg_to_rad(SHIELD_TILT_DEG) + lag * 0.5 - _lean * 0.15
	for braid: Node3D in _braids:
		braid.rotation.x = clampf(lag * 1.4 + _lean * 1.1 + rb * mv * 0.4, -0.6, 1.4)
	var twirl: float = 0.0
	if _fidget == Fidget.AXE_TWIRL:
		twirl = TAU * smoothstep(0.2, 0.8, _fidget_t / T.FIDGET_DURATION)
	_axe.basis = Basis(Vector3.UP, deg_to_rad(AXE_OUT_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(AXE_PITCH_DEG) + lag * 0.6 + twirl) * Basis(Vector3.UP, deg_to_rad(AXE_ROLL_DEG))
	_mood_t += delta
	_apply_mood(delta)
	if _prewarm_frames > 0:
		_prewarm_frames -= 1
		if _prewarm_frames == 0:
			_set_prewarm(false)
		else:
			_mouth.visible = true
			_stars.visible = true
	_update_locks(delta, mv, rb, air, vertical_speed)

	_update_blink(delta)
	_update_face(delta)


func _update_locks(delta: float, mv: float, rb: float, air: float, vertical_speed: float) -> void:
	for l: int in _hair_x.size():
		var g: float = T.HAIR_GAIN[l]
		var k: float = T.HAIR_STIFFNESS[l]
		var c: float = T.HAIR_DAMPING[l]
		var lag_t: float = (T.HAIR_LAG_MOVE * mv + T.HAIR_LAG_RUN * rb * mv + _lean * T.HAIR_LAG_LEAN) * g
		var lift_t: float = clampf(-vertical_speed * T.HAIR_LIFT_PER_FALL_SPEED * air, -0.3, T.HAIR_LIFT_MAX) * g
		var wind: float = deg_to_rad(T.HAIR_WIND_DEG) * sin(_time * T.HAIR_WIND_FREQ * (1.0 + 0.17 * l) + l * 1.7)
		if _mood == Mood.FLAIL:
			lift_t = (0.5 + 0.15 * sin(_time * 11.0 + l)) * _mood_w
			wind += 0.35 * sin(_time * 9.0 + l * 2.1) * _mood_w
		var sway_t: float = (-_bank * T.HAIR_SWAY_BANK + wind) * g
		_hair_xv[l] += (-k * (_hair_x[l] - lag_t) - c * _hair_xv[l]) * delta
		_hair_x[l] += _hair_xv[l] * delta
		_hair_liftv[l] += (-k * (_hair_lift[l] - lift_t) - c * _hair_liftv[l]) * delta
		_hair_lift[l] = clampf(_hair_lift[l] + _hair_liftv[l] * delta, -0.5, 0.9)
		_hair_swayv[l] += (-k * (_hair_sway[l] - sway_t) - c * _hair_swayv[l]) * delta
		_hair_sway[l] += _hair_swayv[l] * delta
	# Each layer moves as one piece: swing and sway about its pivot, and lift flares it outward.
	for hp: Dictionary in _hair_pivots:
		var l: int = hp["layer"]
		var lift: float = _hair_lift[l]
		var flare: float = clampf(1.0 + 0.35 * lift, 0.85, 1.4)
		var b: Basis = Basis(Vector3.RIGHT, _hair_x[l] - 0.35 * lift) * Basis(Vector3.BACK, _hair_sway[l]) * Basis.from_scale(Vector3(flare, 1.0 - 0.12 * lift, flare))
		(hp["node"] as Node3D).transform = Transform3D(b, hp["origin"])


func _apply_mood(delta: float) -> void:
	var target_w: float = 0.0 if _mood == Mood.NORMAL else 1.0
	if _mood == Mood.GETUP:
		target_w = 1.0 - clampf(_mood_t / T.CRASH_GETUP_TIME, 0.0, 1.0)
		_mood_w = target_w
	else:
		_mood_w = lerpf(_mood_w, target_w, 1.0 - exp(-12.0 * delta))
	var w: float = _mood_w
	var t: float = _mood_t
	var scared_t: float = 0.0
	var scream_t: float = 0.0
	_stars.visible = _mood == Mood.DOWNED or (_mood == Mood.GETUP and w > 0.3)
	_sweat.emitting = false
	_drip_left = maxf(_drip_left - delta, 0.0)
	_drip.emitting = _drip_left > 0.0
	_sweat.initial_velocity_max = 1.1
	_sweat.spread = 60.0
	_mouth.visible = false
	if w < 0.001:
		_scared = lerpf(_scared, 0.0, 1.0 - exp(-8.0 * delta))
		_scream = lerpf(_scream, 0.0, 1.0 - exp(-12.0 * delta))
		return
	match _mood:
		Mood.NERVOUS:
			var n: float = clampf(t / T.NERVOUS_RAMP_TIME, 0.15, 1.0)
			var tremble: float = sin(_time * T.NERVOUS_TREMBLE_FREQ) * deg_to_rad(T.NERVOUS_TREMBLE_DEG) * n
			_pose_sit(w, -0.12 + tremble * 0.5, tremble)
			_blend(_arm_l, Vector3(-0.5, 0.0, 0.55), w)
			_blend(_arm_r, Vector3(-0.5, 0.0, -0.55), w)
			_blend(_fore_l, Vector3(-1.0 - 0.1 * sin(_time * 31.0) * n, 0.0, 0.0), w)
			_blend(_fore_r, Vector3(-1.0 - 0.1 * cos(_time * 29.0) * n, 0.0, 0.0), w)
			var glance: float = sin(t * (1.6 + 2.8 * n)) * 0.7 * n
			var up: float = -0.45 * smoothstep(0.2, 0.8, sin(t * 0.9 + 1.0)) * n
			_blend(_head, Vector3(up + tremble, glance, tremble * 0.5), w)
			_sweat.emitting = n > 0.3
			scared_t = 0.4 + 0.6 * n
		Mood.FLAIL:
			var arm_a: float = _time * T.FLAIL_ARM_SPEED
			_blend(_arm_l, Vector3(-arm_a, 0.0, 0.4), w, true)
			_blend(_arm_r, Vector3(-arm_a + PI, 0.0, -0.4), w, true)
			_blend(_fore_l, Vector3(-0.45, 0.0, 0.0), w)
			_blend(_fore_r, Vector3(-0.45, 0.0, 0.0), w)
			var pedal: float = _time * T.FLAIL_LEG_SPEED
			_blend(_leg_l, Vector3(-0.5 + 0.9 * sin(pedal), 0.0, 0.0), w)
			_blend(_leg_r, Vector3(-0.5 - 0.9 * sin(pedal), 0.0, 0.0), w)
			_leg_l.position.y = lerpf(_leg_l.position.y, 0.05 * maxf(0.0, cos(pedal)), w)
			_leg_r.position.y = lerpf(_leg_r.position.y, 0.05 * maxf(0.0, -cos(pedal)), w)
			_blend(_hips, Vector3(-0.15, 0.0, 0.1 * sin(_time * 7.0)), w)
			_blend(_chest, Vector3(0.0, 0.2 * sin(_time * 6.0), 0.0), w)
			_blend(_head, Vector3(-0.35 + 0.1 * sin(_time * 9.0), 0.25 * sin(_time * 5.0), 0.15 * sin(_time * 7.0)), w)
			for braid: Node3D in _braids:
				braid.rotation.x = lerpf(braid.rotation.x, 0.9 + 0.5 * sin(_time * 12.0 + braid.position.x * 40.0), w)
			scream_t = 0.85 + 0.15 * sin(_time * 9.0)
			scared_t = 1.0
		Mood.SWIM:
			# Floating chest-deep: doggy paddle, small kicks, chin up; spit and head shake on cue.
			var paddle: float = _time * 7.0
			_blend(_hips, Vector3(0.15, 0.0, 0.0), w)
			_blend(_chest, Vector3.ZERO, w)
			_blend(_arm_l, Vector3(-1.1 + 0.45 * sin(paddle), 0.0, 0.45), w)
			_blend(_arm_r, Vector3(-1.1 - 0.45 * sin(paddle), 0.0, -0.45), w)
			_blend(_fore_l, Vector3(-0.8, 0.0, 0.0), w)
			_blend(_fore_r, Vector3(-0.8, 0.0, 0.0), w)
			_blend(_leg_l, Vector3(-0.3 + 0.5 * sin(paddle * 1.3), 0.0, 0.1), w)
			_blend(_leg_r, Vector3(-0.3 - 0.5 * sin(paddle * 1.3), 0.0, -0.1), w)
			var shake: float = 0.7 * sin(_time * 30.0) * _shake
			_blend(_head, Vector3(-0.25 - 0.15 * _spit, shake, 0.2 * shake), w)
			if _shake > 0.3:
				_sweat.emitting = true
				_sweat.initial_velocity_max = 2.6
				_sweat.spread = 180.0
			scream_t = _spit * 0.7
			scared_t = 0.35 * (1.0 - _shake)
		Mood.DOWNED, Mood.GETUP:
			if _down_face:
				_blend(_hips, Vector3(0.0, 0.0, 0.0), w)
				_blend(_leg_l, Vector3(0.15, 0.0, 0.12), w)
				_blend(_leg_r, Vector3(0.2, 0.0, -0.12), w)
				_blend(_arm_l, Vector3(-2.7, 0.0, 0.35), w)
				_blend(_arm_r, Vector3(-2.6, 0.0, -0.35), w)
				_blend(_fore_l, Vector3(-0.3, 0.0, 0.0), w)
				_blend(_fore_r, Vector3(-0.3, 0.0, 0.0), w)
			else:
				_pose_sit(w, -0.35, 0.0)
				_blend(_arm_l, Vector3(0.7, 0.0, 0.45), w)
				_blend(_arm_r, Vector3(0.7, 0.0, -0.45), w)
				_blend(_fore_l, Vector3(-0.3, 0.0, 0.0), w)
				_blend(_fore_r, Vector3(-0.3, 0.0, 0.0), w)
			var wob: float = 0.25 * (1.0 if _mood == Mood.DOWNED else 0.0)
			var shake: float = 0.5 * sin(t * 26.0) if _mood == Mood.GETUP else 0.0
			var face_up: float = -0.9 if _down_face else 0.0
			_head.rotation = Vector3(
				lerpf(_head.rotation.x, face_up + wob * sin(_time * 3.0), w),
				shake + lerpf(_head.rotation.y, wob * cos(_time * 3.0), w),
				lerpf(_head.rotation.z, wob * sin(_time * 3.0 + 1.0), w))
			_stars.rotation.y = _time * T.STARS_SPEED
			for i: int in _stars.get_child_count():
				var st: Node3D = _stars.get_child(i)
				st.rotation.z = _time * 3.0 + i
				st.position.y = 0.04 * sin(_time * 5.0 + i * 1.3)
	_scared = lerpf(_scared, scared_t, 1.0 - exp(-10.0 * delta))
	_scream = lerpf(_scream, scream_t * w, 1.0 - exp(-14.0 * delta))


func _pose_sit(w: float, lean_back: float, roll: float) -> void:
	_blend(_hips, Vector3(lean_back, 0.0, roll), w)
	_blend(_chest, Vector3.ZERO, w)
	_blend(_leg_l, Vector3(-1.4, 0.0, 0.12), w)
	_blend(_leg_r, Vector3(-1.4, 0.0, -0.12), w)
	_leg_l.position.y = lerpf(_leg_l.position.y, 0.0, w)
	_leg_r.position.y = lerpf(_leg_r.position.y, 0.0, w)


func _blend(node: Node3D, target: Vector3, w: float, wrap: bool = false) -> void:
	var r: Vector3 = node.rotation
	if wrap:
		r.x = lerp_angle(r.x, target.x, w)
		r.y = lerp_angle(r.y, target.y, w)
		r.z = lerp_angle(r.z, target.z, w)
		node.rotation = r
	else:
		node.rotation = r.lerp(target, w)


## Scared: wide whites with small dark pupils that tremble and brows raised and tilted up in the middle.
## Scream: the jaw drops with the beard, the mustache halves lift apart and the mouth opens.
func _update_face(_delta: float) -> void:
	var k: float = _scared
	for i: int in _eyes.size():
		var eye: Node3D = _eyes[i]
		_scleras[i].visible = k > 0.05
		_scleras[i].scale = Vector3.ONE * lerpf(0.6, 1.05, k)
		var pupil: Node3D = _pupils[i]
		pupil.scale = Vector3.ONE * lerpf(1.0, 0.5, k)
		var jitter := Vector3(sin(_time * 47.0 + i), cos(_time * 53.0 + i * 2.0), 0.0) * 0.004 * k
		pupil.position = Vector3(0.0, 0.0, 0.026 * k) + jitter
		if k > 0.05:
			eye.scale.y = maxf(eye.scale.y, 1.0)
		if _mood == Mood.DOWNED and _mood_w > 0.5:
			eye.scale.y = 0.35
	var raise: float = 0.035 * k
	var tilt: float = deg_to_rad(24.0) * k
	_brow_l.position = BROW_PIVOT + Vector3(0.0, raise, 0.004 * k)
	_brow_l.rotation = Vector3(0.0, 0.0, -tilt)
	_brow_r.position = Vector3(-BROW_PIVOT.x, BROW_PIVOT.y, BROW_PIVOT.z) + Vector3(0.0, raise, 0.004 * k)
	_brow_r.rotation = Vector3(0.0, 0.0, tilt)
	var o: float = _scream
	var hinge := Transform3D(Basis.IDENTITY, JAW_HINGE)
	_jaw.transform = hinge * Transform3D(Basis(Vector3.RIGHT, 0.22 * o), Vector3(0.0, -0.075 * o, 0.012 * o)) * hinge.affine_inverse()
	_stache_l.position = STACHE_PIVOT + Vector3(0.0, 0.022 * o, 0.006 * o)
	_stache_r.position = STACHE_PIVOT + Vector3(0.0, 0.022 * o, 0.006 * o)
	_stache_l.rotation = Vector3(0.0, 0.0, 0.45 * o)
	_stache_r.rotation = Vector3(0.0, 0.0, -0.45 * o)
	_mouth.visible = o > 0.05
	_mouth.scale = Vector3(lerpf(0.6, 1.0, o), lerpf(0.3, 1.0, o), 1.0)


func _emit_contacts(prev_phase: float, phase: float, rb: float, mv: float) -> void:
	if mv < 0.2:
		return
	var prev_k: int = floori((prev_phase - PI * 0.5) / PI)
	var k: int = floori((phase - PI * 0.5) / PI)
	while prev_k < k:
		prev_k += 1
		var side: int = posmod(prev_k, 2)
		var boot: Node3D = _boot_l if side == 0 else _boot_r
		var pos: Vector3 = boot.global_position
		pos.y = global_position.y
		footstep.emit(side, pos, rb, mv)


func _update_fidget(delta: float, idle_w: float) -> float:
	if _fidget == Fidget.NONE:
		if idle_w > 0.9:
			_fidget_timer -= delta
		else:
			_fidget_timer = maxf(_fidget_timer, T.FIDGET_DELAY_MIN)
		if _fidget_timer <= 0.0:
			_fidget = _rng.randi_range(1, 4) as Fidget
			_fidget_t = 0.0
			_fidget_side = 1.0 if _rng.randf() < 0.5 else -1.0
		return 0.0
	_fidget_t += delta
	if _fidget_t >= T.FIDGET_DURATION or idle_w < 0.5:
		_fidget = Fidget.NONE
		_fidget_timer = _rng.randf_range(T.FIDGET_DELAY_MIN, T.FIDGET_DELAY_MAX)
		return 0.0
	return sin(PI * _fidget_t / T.FIDGET_DURATION) * idle_w


func _update_look(delta: float, idle_w: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = T.IDLE_LOOK_INTERVAL * _rng.randf_range(0.6, 1.5)
		_look_target = deg_to_rad(T.IDLE_LOOK_DEG) * _rng.randf_range(-1.0, 1.0) if _rng.randf() < 0.7 else 0.0
	var target: float = _look_target * clampf(idle_w * 1.4 - 0.4, 0.0, 1.0)
	_look = lerpf(_look, target, 1.0 - exp(-4.0 * delta))


func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_timer = _rng.randf_range(T.BLINK_INTERVAL_MIN, T.BLINK_INTERVAL_MAX)
		if _rng.randf() < 0.2:
			_blink_timer = 0.25
	var open: float = 1.0
	if _blink_t >= 0.0:
		_blink_t += delta
		var k: float = _blink_t / T.BLINK_DURATION
		if k >= 1.0:
			_blink_t = -1.0
		else:
			open = absf(k * 2.0 - 1.0)
	for eye: Node3D in _eyes:
		eye.scale.y = maxf(0.08, open)


# --- Construction ---

func _build() -> void:
	_blob = MeshInstance3D.new()
	_blob.name = "BlobShadow"
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.85, 0.85)
	_blob.mesh = quad
	_blob.material_override = Mats.get_blob_shadow_material()
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.position.y = 0.015
	add_child(_blob)

	_squash_node = _node(self, "Squash", Vector3.ZERO)
	_hips = _node(_squash_node, "Hips", Vector3(0.0, HIP_HEIGHT, 0.0))

	_leg_l = _build_leg(0.1)
	_leg_r = _build_leg(-0.1)
	_boot_l = _leg_l.get_node("Foot")
	_boot_r = _leg_r.get_node("Foot")

	_torso = _node(_hips, "Torso", Vector3.ZERO)
	_part(_torso, _cylinder(0.175, 0.225, 0.16), &"leather", Vector3(0.0, 0.03, 0.0))
	_part(_torso, _torus(0.19, 0.232), &"leather_dark", Vector3(0.0, -0.05, 0.0), Vector3(1.0, 0.55, 1.0))
	for i: int in 6:
		var a: float = TAU * (float(i) + 0.5) / 6.0
		_part(_torso, _box(Vector3(0.018, 0.15, 0.012)), &"leather_dark", Vector3(sin(a) * 0.205, 0.015, cos(a) * 0.205), Vector3.ONE, Vector3(-14.0, rad_to_deg(a), 0.0))
	_part(_torso, _sphere(0.19), &"skin", Vector3(0.0, 0.2, 0.0), Vector3(1.05, 1.0, 0.88))
	_part(_torso, _cylinder(0.19, 0.193, 0.085), &"leather_dark", Vector3(0.0, 0.115, 0.0), Vector3(1.0, 1.0, 0.9))
	_part(_torso, _box(Vector3(0.11, 0.085, 0.035)), &"gold", Vector3(0.0, 0.115, 0.172))
	_part(_torso, _box(Vector3(0.05, 0.035, 0.02)), &"leather_dark", Vector3(0.0, 0.115, 0.19))

	_chest = _node(_torso, "Chest", Vector3(0.0, 0.2, 0.0))
	_part(_chest, _sphere(0.2), &"skin", Vector3(0.0, 0.13, 0.0), Vector3(1.22, 0.82, 0.86))
	_part(_chest, _sphere(0.085), &"skin", Vector3(0.075, 0.14, 0.12), Vector3(1.15, 0.8, 0.6))
	_part(_chest, _sphere(0.085), &"skin", Vector3(-0.075, 0.14, 0.12), Vector3(1.15, 0.8, 0.6))
	_part(_chest, _sculpt(&"pelt"), &"vcolor", Vector3.ZERO)
	_lock_rng.seed = 1234
	var tuft_deg: float = 46.0
	while tuft_deg <= 314.0:
		var a: float = deg_to_rad(tuft_deg + _lock_rng.randf_range(-2.0, 2.0))
		var radial := Vector3(sin(a), 0.0, cos(a))
		var root := Vector3(radial.x * 0.29, 0.245 - 0.075 * maxf(0.0, -radial.z), radial.z * 0.215 - 0.03)
		var fur_root: Color = FUR_ROOT.lerp(FUR_ROOT_ALT, _lock_rng.randf())
		_add_lock(_chest, 3, root, radial, _lock_rng.randf_range(0.085, 0.11), 0.085, 0.036, deg_to_rad(_lock_rng.randf_range(30.0, 38.0)), 0.1, 0.2, fur_root, FUR_TIP, 12, 5.0)
		tuft_deg += 26.0

	_shield = _node(_chest, "Shield", Vector3(0.0, 0.02, -0.205))
	_shield.rotation_degrees.x = SHIELD_TILT_DEG
	_part(_shield, _cylinder(0.2, 0.2, 0.04), &"wood", Vector3.ZERO, Vector3.ONE, Vector3(90.0, 0.0, 0.0))
	_part(_shield, _box(Vector3(0.012, 0.38, 0.01)), &"wood_dark", Vector3(0.065, 0.0, -0.021))
	_part(_shield, _box(Vector3(0.012, 0.38, 0.01)), &"wood_dark", Vector3(-0.065, 0.0, -0.021))
	_part(_shield, _box(Vector3(0.36, 0.075, 0.012)), &"paint_red", Vector3(0.0, 0.0, -0.023))
	_part(_shield, _box(Vector3(0.075, 0.36, 0.012)), &"paint_red", Vector3(0.0, 0.0, -0.023))
	_part(_shield, _torus(0.185, 0.218), &"metal_dark", Vector3.ZERO, Vector3(1.0, 1.4, 1.0), Vector3(90.0, 0.0, 0.0))
	_part(_shield, _hemisphere(0.055), &"gold", Vector3(0.0, 0.0, -0.022), Vector3.ONE, Vector3(-90.0, 0.0, 0.0))

	_arm_l = _build_arm(0.25)
	_arm_r = _build_arm(-0.25)
	_fore_l = _arm_l.get_node("Forearm")
	_fore_r = _arm_r.get_node("Forearm")
	_axe = _node(_fore_r, "Axe", Vector3(0.0, -0.105, 0.0))
	_axe.basis = Basis(Vector3.UP, deg_to_rad(AXE_OUT_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(AXE_PITCH_DEG)) * Basis(Vector3.UP, deg_to_rad(AXE_ROLL_DEG))
	# Haft runs along local -Y from the grip; the bearded blade hangs along local -Z.
	_part(_axe, _capsule(0.03, 0.47), &"wood", Vector3(0.0, -0.12, 0.0))
	for wy: float in [0.065, 0.03, -0.005, -0.04]:
		_part(_axe, _cylinder(0.036, 0.036, 0.022), &"leather_dark", Vector3(0.0, wy, 0.0), Vector3.ONE, Vector3(0.0, wy * 900.0, 8.0))
	_part(_axe, _sculpt(&"axe_pommel"), &"leather_dark", Vector3(0.0, 0.115, 0.0))
	_part(_axe, _sculpt(&"axe_socket"), &"steel", Vector3(0.0, -0.3, 0.0))
	_part(_axe, _sculpt(&"axe_blade"), &"steel", Vector3(0.0, -0.3, 0.0))
	_part(_axe, _sculpt(&"axe_edge"), &"metal_edge", Vector3(0.0, -0.3, 0.0))

	_head = _node(_chest, "Head", Vector3(0.0, 0.27, 0.0))
	var skull := _part(_head, _sphere(0.22), &"skin", Vector3(0.0, 0.17, 0.0))
	skull.material_override = Mats.get_head_skin_material()
	_part(_head, _sculpt(&"nose"), &"skin", Vector3.ZERO)
	for x: float in [0.075, -0.075]:
		var eye := _node(_head, "Eye", Vector3(x, 0.195, 0.195))
		var sclera := _part(eye, _sculpt(&"sclera"), &"eye_glint", Vector3(0.0, 0.0, -0.004))
		sclera.visible = false
		_scleras.append(sclera)
		var pupil := _node(eye, "Pupil", Vector3.ZERO)
		_part(pupil, _sphere(0.04), &"eye", Vector3.ZERO, Vector3(0.82, 1.25, 0.55))
		_part(pupil, _sphere(0.013), &"eye_glint", Vector3(0.011, 0.018, 0.02))
		_pupils.append(pupil)
		_eyes.append(eye)
	_brow_l = _node(_head, "BrowL", BROW_PIVOT)
	_part(_brow_l, _sculpt(&"brow_l"), &"hair_grad", -BROW_PIVOT)
	_brow_r = _node(_head, "BrowR", Vector3(-BROW_PIVOT.x, BROW_PIVOT.y, BROW_PIVOT.z))
	_part(_brow_r, _sculpt(&"brow_r"), &"hair_grad", -Vector3(-BROW_PIVOT.x, BROW_PIVOT.y, BROW_PIVOT.z))
	# Jaw: lives at head origin and hinges near the ears; carries the beard block, its tips and the braids.
	_jaw = _node(_head, "Jaw", Vector3.ZERO)
	_part(_head, _sculpt(&"hair_mass"), &"hair_grad", Vector3.ZERO)
	_build_hair_locks()
	_part(_jaw, _sculpt(&"beard"), &"hair_grad", Vector3.ZERO)
	_part(_jaw, _sculpt(&"tongue"), &"tongue", Vector3.ZERO)
	_stache_l = _node(_head, "MustacheL", STACHE_PIVOT)
	_part(_stache_l, _sculpt(&"mustache_l"), &"hair_grad", -STACHE_PIVOT)
	_stache_r = _node(_head, "MustacheR", STACHE_PIVOT)
	_part(_stache_r, _sculpt(&"mustache_r"), &"hair_grad", -STACHE_PIVOT)
	for x: float in [0.068, -0.068]:
		var braid := _node(_jaw, "Braid", Vector3(x, -0.1, 0.165))
		_part(braid, _sculpt(&"braid_knot"), &"hair_grad", Vector3(0.0, -0.005, 0.0))
		_part(braid, _sculpt(&"braid_knot"), &"hair_grad", Vector3(0.0, -0.045, 0.0), Vector3(0.88, 0.95, 0.88))
		_part(braid, _sculpt(&"braid_bead"), &"gold", Vector3(0.0, -0.085, 0.0))
		_part(braid, _sculpt(&"braid_tip"), &"hair_grad", Vector3(0.0, -0.118, 0.0))
		_braids.append(braid)

	_mouth = _node(_head, "Mouth", Vector3(0.0, 0.07, 0.196))
	_part(_mouth, _sculpt(&"mouth_open"), &"mouth", Vector3.ZERO)
	_part(_mouth, _sculpt(&"tooth"), &"eye_glint", Vector3(0.0, 0.028, 0.022))
	_mouth.visible = false
	_stars = _node(_head, "Stars", Vector3(0.0, 0.5, 0.0))
	_stars.visible = false
	for i: int in T.STARS_COUNT:
		var a: float = TAU * float(i) / float(T.STARS_COUNT)
		var star := _part(_stars, _sculpt(&"star"), &"star", Vector3(cos(a) * T.STARS_RADIUS, 0.0, sin(a) * T.STARS_RADIUS))
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sweat = CPUParticles3D.new()
	_sweat.name = "Sweat"
	_sweat.emitting = false
	_sweat.amount = Q.particles(T.SWEAT_AMOUNT)
	_sweat.lifetime = 0.6
	_sweat.local_coords = false
	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.6
	drop.radial_segments = 10
	drop.rings = 6
	drop.material = Mats.get_mat(&"sweat")
	_sweat.mesh = drop
	_sweat.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sweat.emission_sphere_radius = 0.2
	_sweat.direction = Vector3.UP
	_sweat.spread = 60.0
	_sweat.initial_velocity_min = 0.6
	_sweat.initial_velocity_max = 1.1
	_sweat.gravity = Vector3(0.0, -6.0, 0.0)
	_sweat.scale_amount_min = 0.025
	_sweat.scale_amount_max = 0.04
	_sweat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sweat.position = Vector3(0.0, 0.25, 0.05)
	_head.add_child(_sweat)
	_drip = _sweat.duplicate() as CPUParticles3D
	_drip.name = "Drip"
	_drip.amount = 14
	_drip.direction = Vector3.DOWN
	_drip.spread = 15.0
	_drip.initial_velocity_min = 0.0
	_drip.initial_velocity_max = 0.3
	_drip.emission_sphere_radius = 0.28
	_drip.position = Vector3(0.0, 0.25, 0.0)
	_hips.add_child(_drip)

	var helmet := _node(_head, "Helmet", Vector3(0.0, 0.265, -0.005))
	_part(helmet, _hemisphere(0.218), &"metal", Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
	_part(helmet, _torus(0.198, 0.238), &"gold", Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
	_part(helmet, _capsule(0.024, 0.36), &"metal_dark", Vector3(0.0, 0.12, 0.0), Vector3(1.0, 1.0, 0.7), Vector3(90.0, 0.0, 0.0))
	for side: float in [1.0, -1.0]:
		var horn := _node(helmet, "Horn", Vector3(0.19 * side, 0.07, 0.0))
		horn.rotation_degrees.z = -58.0 * side
		_part(horn, _torus(0.03, 0.055), &"gold", Vector3.ZERO)
		_part(horn, _cylinder(0.016, 0.05, 0.16), &"horn", Vector3(0.0, 0.08, 0.0))
		var tip := _node(horn, "Tip", Vector3(0.0, 0.16, 0.0))
		tip.rotation_degrees.z = 38.0 * side
		_part(tip, _cylinder(0.003, 0.017, 0.08), &"horn", Vector3(0.0, 0.038, 0.0))


## Layered wide locks that read as one hair volume with divisions: a short crown under the helmet, a longer
## nape layer and a long back layer, each rotated so tips interleave; plus sideburns, fringe and
## lock tips on the beard edge. Fixed seed so the look is stable.
func _group_locks() -> void:
	var groups: Dictionary = {}
	for lk: Dictionary in _locks:
		var mi: MeshInstance3D = lk["node"]
		var key: Array = [mi.get_parent(), lk["layer"]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(lk)
	for key: Array in groups.keys():
		var parent: Node3D = key[0]
		var origin := Vector3.ZERO
		for lk: Dictionary in groups[key]:
			origin += lk["root"]
		origin /= float(groups[key].size())
		var pivot := _node(parent, "HairLayer%d" % key[1], origin)
		for lk: Dictionary in groups[key]:
			var mi: MeshInstance3D = lk["node"]
			parent.remove_child(mi)
			pivot.add_child(mi)
			mi.transform = Transform3D(lk["basis"], (lk["root"] as Vector3) - origin)
		_hair_pivots.append({"node": pivot, "layer": key[1], "origin": origin})


## Bakes rigid parts into one mesh per animated node (see rig_baker.gd); only what moves on its own stays.
func _bake() -> void:
	var animated: Dictionary = {}
	for n: Node3D in [_squash_node, _hips, _torso, _chest, _shield, _head, _jaw, _mouth, _stars, _leg_l, _leg_r, _arm_l, _arm_r, _fore_l, _fore_r, _axe, _brow_l, _brow_r, _stache_l, _stache_r]:
		animated[n] = true
	for arr: Array in [_braids, _eyes, _pupils]:
		for n: Node3D in arr:
			animated[n] = true
	for hp: Dictionary in _hair_pivots:
		animated[hp["node"]] = true
	var keep: Dictionary = {_blob: true}
	for n: Node3D in _scleras:
		keep[n] = true
	for st: Node in _stars.get_children():
		keep[st] = true
	Baker.bake(self, animated, keep)


func _build_hair_locks() -> void:
	_lock_rng.seed = 4711
	var layers: Array = [
		# [layer, from deg, to deg, step, root y, root r, len min, len max, width, thick, splay deg, curve, curl]
		[0, 66.0, 294.0, 38.0, 0.262, 0.205, 0.1, 0.12, 0.12, 0.04, 20.0, 0.08, 0.15],
		[1, 106.0, 254.0, 37.0, 0.22, 0.2, 0.22, 0.25, 0.13, 0.042, 14.0, 0.08, 0.14],
		[2, 152.0, 208.0, 28.0, 0.16, 0.205, 0.32, 0.36, 0.115, 0.036, 12.0, 0.06, 0.12],
	]
	for cfg: Array in layers:
		var deg: float = cfg[1]
		while deg <= float(cfg[2]) + 0.01:
			var a: float = deg_to_rad(deg + _lock_rng.randf_range(-1.5, 1.5))
			var radial := Vector3(sin(a), 0.0, cos(a))
			var root := Vector3(radial.x * float(cfg[5]), float(cfg[4]) + _lock_rng.randf_range(-0.008, 0.008), radial.z * float(cfg[5]) - 0.01)
			var length: float = _lock_rng.randf_range(cfg[6], cfg[7])
			var splay: float = deg_to_rad(float(cfg[10]) + _lock_rng.randf_range(-2.0, 2.0))
			_add_lock(_head, cfg[0], root, radial, length, float(cfg[8]) * _lock_rng.randf_range(0.95, 1.05), cfg[9], splay, float(cfg[11]) * _lock_rng.randf_range(0.85, 1.15), float(cfg[12]) * _lock_rng.randf_range(0.85, 1.15), HAIR_LIGHT, HAIR_BOTTOM, 14)
			deg += float(cfg[3])
	for side: float in [1.0, -1.0]:
		for d: float in [70.0, 84.0]:
			var a: float = deg_to_rad(d) * side
			var radial := Vector3(sin(a), 0.0, cos(a))
			_add_lock(_head, 0, Vector3(radial.x * 0.205, 0.255, radial.z * 0.205), radial, 0.15 if d < 80.0 else 0.13, 0.06, 0.03, deg_to_rad(6.0), 0.06, 0.1, HAIR_LIGHT, HAIR_BOTTOM, 12)
		var fa: float = deg_to_rad(50.0) * side
		var fr := Vector3(sin(fa), 0.0, cos(fa))
		_add_lock(_head, 0, Vector3(fr.x * 0.2, 0.272, fr.z * 0.2), fr, 0.06, 0.05, 0.024, deg_to_rad(22.0), 0.08, 0.2, HAIR_LIGHT, HAIR_TOP, 12)
	# Beard edge tips in the same lock language.
	for i: int in 5:
		var u: float = (float(i) - 2.0) / 2.0
		var x: float = u * 0.15
		var y: float = -0.075 - 0.07 * (1.0 - u * u)
		var radial := Vector3(u * 0.5, 0.0, 1.0).normalized()
		_add_lock(_jaw, 0, Vector3(x, y, 0.15 + 0.03 * (1.0 - absf(u))), radial, _lock_rng.randf_range(0.06, 0.08), 0.06, 0.03, deg_to_rad(-4.0), 0.06, 0.15, HAIR_TOP, HAIR_BOTTOM, 12)


func _add_lock(parent: Node3D, layer: int, root: Vector3, radial: Vector3, length: float, width: float, thick: float, splay: float, curve: float, curl: float, root_col: Color, tip_col: Color, facets: int, color_power: float = 1.0) -> void:
	var key := "lock_%.2f_%.3f_%.3f_%.2f_%.2f_%d_%s_%s_%.1f" % [length, width, thick, curve, curl, facets, root_col.to_html(), tip_col.to_html(), color_power]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = Sculpt.lock(length, width, thick, curve, curl, facets, root_col, tip_col, color_power)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_cache[key]
	mi.material_override = Mats.get_mat(&"hair_grad" if layer < 3 else &"vcolor")
	var z: Vector3 = radial.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	var b := Basis(x, Vector3.UP, z) * Basis(Vector3.RIGHT, -splay)
	mi.transform = Transform3D(b, root)
	parent.add_child(mi)
	_locks.append({"node": mi, "layer": layer, "root": root, "basis": b})


func _build_leg(x: float) -> Node3D:
	var leg := _node(_hips, "Leg", Vector3(x, 0.0, 0.0))
	_part(leg, _capsule(0.066, 0.22), &"leather_dark", Vector3(0.0, -0.11, 0.0))
	_part(leg, _cylinder(0.074, 0.08, 0.08), &"leather", Vector3(0.0, -0.225, 0.0))
	_part(leg, _sphere(0.092), &"fur_light", Vector3(0.0, -0.18, 0.0), Vector3(1.0, 0.55, 1.0))
	var boot := _part(leg, _sphere(0.082), &"leather", Vector3(0.0, -0.272, 0.03), Vector3(1.05, 0.72, 1.42))
	boot.name = "Boot"
	_node(leg, "Foot", boot.position)
	_part(boot, _torus(0.062, 0.084), &"leather_dark", Vector3(0.0, -0.055, 0.0), Vector3(1.0, 0.5, 1.0))
	return leg


func _build_arm(x: float) -> Node3D:
	var arm := _node(_chest, "Arm", Vector3(x, 0.14, 0.0))
	_part(arm, _sphere(0.092), &"skin", Vector3.ZERO)
	_part(arm, _capsule(0.072, 0.17), &"skin", Vector3(0.0, -0.06, 0.0))
	_part(arm, _torus(0.066, 0.08), &"tattoo", Vector3(0.0, -0.06, 0.0), Vector3(1.0, 0.6, 1.0))
	var fore := _node(arm, "Forearm", Vector3(0.0, -0.13, 0.0))
	_part(fore, _capsule(0.064, 0.12), &"skin", Vector3(0.0, -0.01, 0.0))
	_part(fore, _cylinder(0.068, 0.076, 0.09), &"leather", Vector3(0.0, -0.035, 0.0))
	_part(fore, _torus(0.066, 0.08), &"gold", Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.5, 1.0))
	_part(fore, _sculpt(&"fist"), &"skin", Vector3(0.0, 0.13, 0.0))
	_part(fore, _sculpt(&"thumb_l" if x > 0.0 else &"thumb_r"), &"skin", Vector3(0.0, 0.13, 0.0))
	return arm


func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, mat_key: StringName, pos: Vector3, scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.get_mat(mat_key)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if mat_key == &"eye_glint" or mat_key == &"eye":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Sculpted hair and beard volumes in head space (head center at y 0.17, radius 0.22, face toward +Z).
static func _sculpt(key: StringName) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var hair := {"top_color": HAIR_TOP, "bottom_color": HAIR_BOTTOM}
	var m: Mesh
	match key:
		&"beard":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.125, 0.112), Vector3(0.0, 0.05, 0.132), Vector3(0.0, -0.03, 0.14), Vector3(0.0, -0.1, 0.135), Vector3(0.0, -0.16, 0.13)]),
				PackedFloat32Array([0.158, 0.176, 0.18, 0.145, 0.07]),
				PackedFloat32Array([0.09, 0.1, 0.097, 0.08, 0.05]),
				_merge(hair, {"n": 3.4, "segments": 72, "grooves": 9, "groove_depth": 0.13, "groove_width": 0.55, "bevel_start": 0.3, "bevel_end": 0.9, "top_color": HAIR_LIGHT}))
		&"mustache_l", &"mustache_r":
			# Two halves that meet under the nose so the scream can lift and split them.
			var side: float = 1.0 if key == &"mustache_l" else -1.0
			var pts := PackedVector3Array()
			var ha := PackedFloat32Array()
			var hb := PackedFloat32Array()
			for i: int in 6:
				var u: float = (float(i) / 5.0) * side
				var au: float = absf(u)
				pts.append(Vector3(u * 0.15 - side * 0.008, 0.112 - 0.012 * au - 0.05 * au * au * au, 0.236 - 0.07 * au * au))
				var thick: float = 1.0 - au * au * 0.8
				ha.append(0.03 * thick + 0.004)
				hb.append(0.036 * thick + 0.005)
			m = Sculpt.sweep(pts, ha, hb, Vector3.UP, _merge(hair, {"n": 3.0, "segments": 20, "grooves": 6, "groove_depth": 0.06, "bevel_start": 0.5, "bevel_end": 0.7, "top_color": HAIR_TOP, "bottom_color": HAIR_BOTTOM.lerp(HAIR_TOP, 0.3)}))
		&"tongue":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.122, 0.17), Vector3(0.0, 0.112, 0.19), Vector3(0.0, 0.105, 0.2)]),
				PackedFloat32Array([0.03, 0.038, 0.028]),
				PackedFloat32Array([0.016, 0.02, 0.014]),
				{"n": 2.4, "segments": 20, "bevel": 0.6})
		&"tooth":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.022, 0.0)]),
				PackedFloat32Array([0.026, 0.024]),
				PackedFloat32Array([0.008, 0.007]),
				{"n": 4.0, "segments": 16, "bevel": 0.5})
		&"brow_l", &"brow_r":
			var sx: float = 1.0 if key == &"brow_l" else -1.0
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(0.035 * sx, 0.238, 0.212), Vector3(0.08 * sx, 0.252, 0.204), Vector3(0.125 * sx, 0.258, 0.178)]),
				PackedFloat32Array([0.016, 0.019, 0.013]),
				PackedFloat32Array([0.017, 0.02, 0.014]),
				Vector3.UP, _merge(hair, {"n": 4.0, "segments": 16, "bevel": 0.5, "top_color": HAIR_BOTTOM, "bottom_color": HAIR_BOTTOM}))
		&"hair_mass":
			# Inner cap that only fills gaps between the locks.
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.25, -0.015), Vector3(0.0, 0.17, -0.04), Vector3(0.0, 0.08, -0.07)]),
				PackedFloat32Array([0.205, 0.215, 0.19]),
				PackedFloat32Array([0.2, 0.195, 0.15]),
				{"n": 2.6, "segments": 40, "bevel_start": 0.05, "bevel_end": 0.5, "top_color": HAIR_TOP, "bottom_color": HAIR_BOTTOM})
		&"braid_knot":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.02, 0.0), Vector3(0.0, -0.04, 0.0)]),
				PackedFloat32Array([0.026, 0.033, 0.024]),
				PackedFloat32Array([0.024, 0.03, 0.022]),
				_merge(hair, {"n": 2.6, "segments": 10, "bevel": 0.4, "top_color": HAIR_TOP, "bottom_color": HAIR_TOP.lerp(HAIR_BOTTOM, 0.5)}))
		&"nose":
			# Bulb that grows out of the face surface instead of a sphere stuck on it.
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(0.0, 0.185, 0.185), Vector3(0.0, 0.17, 0.222), Vector3(0.0, 0.16, 0.238)]),
				PackedFloat32Array([0.028, 0.043, 0.04]),
				PackedFloat32Array([0.026, 0.04, 0.036]),
				Vector3.UP, {"n": 2.4, "segments": 24, "bevel_start": 0.0, "bevel_end": 0.9})
		&"sclera":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.03, 0.0), Vector3(0.0, 0.0, 0.006), Vector3(0.0, -0.03, 0.0)]),
				PackedFloat32Array([0.026, 0.044, 0.026]),
				PackedFloat32Array([0.012, 0.02, 0.012]),
				{"n": 2.2, "segments": 24, "bevel": 0.5})
		&"mouth_open":
			# Big dark scream opening between the lifted mustache and the dropped beard.
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.035, -0.01), Vector3(0.0, 0.0, 0.014), Vector3(0.0, -0.045, 0.0)]),
				PackedFloat32Array([0.05, 0.072, 0.05]),
				PackedFloat32Array([0.02, 0.03, 0.02]),
				{"n": 2.4, "segments": 24, "bevel": 0.6})
		&"star":
			m = Sculpt.star(5, 0.07, 0.032, 0.03)
		&"axe_blade":
			# Bearded blade: flares from the socket along -Z and its lower "beard" reaches back toward the grip (+Y).
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(0.0, 0.0, -0.03), Vector3(0.0, 0.012, -0.07), Vector3(0.0, 0.035, -0.115), Vector3(0.0, 0.05, -0.15)]),
				PackedFloat32Array([0.045, 0.07, 0.105, 0.125]),
				PackedFloat32Array([0.026, 0.018, 0.011, 0.007]),
				Vector3.RIGHT, {"n": 4.5, "segments": 24, "bevel_start": 0.0, "bevel_end": 0.3})
		&"axe_edge":
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(0.0, 0.05, -0.148), Vector3(0.0, 0.053, -0.163)]),
				PackedFloat32Array([0.128, 0.122]),
				PackedFloat32Array([0.0075, 0.003]),
				Vector3.RIGHT, {"n": 4.5, "segments": 24, "bevel_start": 0.0, "bevel_end": 0.6})
		&"axe_socket":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.05, 0.0), Vector3(0.0, -0.05, 0.0)]),
				PackedFloat32Array([0.042, 0.042]),
				PackedFloat32Array([0.045, 0.045]),
				{"n": 4.0, "segments": 20, "bevel": 0.4})
		&"axe_pommel":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.02, 0.0), Vector3(0.0, -0.01, 0.0)]),
				PackedFloat32Array([0.038, 0.034]),
				PackedFloat32Array([0.038, 0.034]),
				{"n": 3.0, "segments": 16, "bevel": 0.6})
		&"fist":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, -0.19, 0.0), Vector3(0.0, -0.225, 0.006), Vector3(0.0, -0.265, 0.008), Vector3(0.0, -0.29, 0.004)]),
				PackedFloat32Array([0.06, 0.071, 0.07, 0.058]),
				PackedFloat32Array([0.062, 0.076, 0.074, 0.06]),
				{"n": 3.6, "segments": 32, "grooves": 8, "groove_depth": 0.06, "groove_width": 0.35, "bevel": 0.55})
		&"thumb_l", &"thumb_r":
			var tx: float = -1.0 if key == &"thumb_l" else 1.0
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(0.045 * tx, -0.21, 0.035), Vector3(0.05 * tx, -0.235, 0.07), Vector3(0.035 * tx, -0.255, 0.088)]),
				PackedFloat32Array([0.026, 0.024, 0.02]),
				PackedFloat32Array([0.024, 0.022, 0.018]),
				Vector3.UP, {"n": 3.0, "segments": 16, "bevel_start": 0.0, "bevel_end": 0.7})
		&"pelt":
			# Fur mantle draped over both shoulders and around the back of the neck.
			var pts := PackedVector3Array()
			var pa := PackedFloat32Array()
			var pb := PackedFloat32Array()
			for i: int in 15:
				var ang: float = deg_to_rad(lerpf(48.0, 312.0, float(i) / 14.0))
				var droop: float = 0.025 * pow(absf(sin(ang)), 4.0) + 0.075 * maxf(0.0, -cos(ang))
				pts.append(Vector3(sin(ang) * 0.25, 0.245 - droop, cos(ang) * 0.18 - 0.03))
				pa.append(0.075)
				pb.append(0.045)
			m = Sculpt.sweep(pts, pa, pb, Vector3.UP, {"n": 3.0, "segments": 24, "grooves": 7, "groove_depth": 0.12, "bevel": 0.6, "top_color": FUR_BODY_TOP, "bottom_color": FUR_BODY_BOTTOM})
		&"braid_bead":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.012, 0.0), Vector3(0.0, -0.026, 0.0), Vector3(0.0, -0.038, 0.0)]),
				PackedFloat32Array([0.03, 0.036, 0.036, 0.03]),
				PackedFloat32Array([0.03, 0.036, 0.036, 0.03]),
				{"n": 2.0, "segments": 20, "bevel": 0.3})
		&"braid_tip":
			m = Sculpt.loft_down(
				PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.025, 0.0), Vector3(0.0, -0.05, 0.0)]),
				PackedFloat32Array([0.022, 0.026, 0.012]),
				PackedFloat32Array([0.02, 0.024, 0.01]),
				_merge(hair, {"n": 2.6, "segments": 10, "bevel": 0.5, "top_color": HAIR_BOTTOM.lerp(HAIR_TOP, 0.5), "bottom_color": HAIR_BOTTOM}))
		_:
			var i: int = String(key).trim_prefix("lock_").to_int()
			var x: float = (float(i) - 2.0) * 0.072
			var z0: float = -0.215 + absf(x) * 0.35
			m = Sculpt.sweep(
				PackedVector3Array([Vector3(x, 0.07, z0), Vector3(x * 1.08, -0.005, z0 - 0.04), Vector3(x * 1.14, -0.08, z0 - 0.055)]),
				PackedFloat32Array([0.045, 0.043, 0.028]),
				PackedFloat32Array([0.026, 0.024, 0.016]),
				Vector3.BACK, _merge(hair, {"n": 3.4, "segments": 20, "grooves": 3, "groove_depth": 0.1, "bevel": 0.6}))
	_mesh_cache[key] = m
	return m


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate()
	out.merge(b, true)
	return out


static func _seg(n: int) -> int:
	return maxi(4, int(round(n * Q.mesh_detail())))


static func _sphere(r: float) -> Mesh:
	var key := "s%.3f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = _seg(40 if r > 0.12 else (28 if r > 0.05 else 16))
		m.rings = _seg(20 if r > 0.12 else (14 if r > 0.05 else 8))
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _hemisphere(r: float) -> Mesh:
	var key := "h%.3f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r
		m.is_hemisphere = true
		m.radial_segments = _seg(40)
		m.rings = _seg(12)
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _capsule(r: float, h: float) -> Mesh:
	var key := "c%.3f_%.3f" % [r, h]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = _seg(24)
		m.rings = _seg(8)
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cylinder(top: float, bottom: float, h: float) -> Mesh:
	var key := "y%.3f_%.3f_%.3f" % [top, bottom, h]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = _seg(32)
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _torus(inner: float, outer: float) -> Mesh:
	var key := "t%.3f_%.3f" % [inner, outer]
	if not _mesh_cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = _seg(40)
		m.ring_segments = _seg(14)
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _box(size: Vector3) -> Mesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]
