extends Node

## Water-tower sequence: button press, anticipation wobble, heavy tip, pour jet, impact, return and refill.
## Drives the BUILDINGS nodes TankPivot / PourPoint / FillSurface / ButtonCap by name.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const Jet := preload("res://scripts/liquid/liquid_jet.gd")
const Feedback := preload("res://scripts/liquid/liquid_feedback.gd")

enum State { READY, ANTICIPATION, TIPPING, POURING, HOLD, RETURNING, REFILLING }

const PLAYER_LAYER: int = 4

var state: int = State.READY

var _field: Node3D
var _tower: Node3D
var _button: Node3D
var _pivot: Node3D
var _pour: Node3D
var _fill: Node3D
var _cap: Node3D
var _area: Area3D
var _jet: Jet
var _fill_base := Vector3.ZERO
var _fill_basis := Basis.IDENTITY
var _fill_meta: bool = false
var _fill_y_offset: float = 0.0 # FillSurface local Y minus its metadata Y
var _fill_y_range := Vector2.ZERO # y_empty, y_full
var _fill_r_range := Vector2.ZERO # radius_empty, radius_full
var _cap_base := Vector3.ZERO
var _cap_scale := Vector3.ONE

var _t: float = 0.0
var _clock: float = 0.0
var _angle: float = 0.0
var _angle_prev: float = 0.0
var _angle_vel_prev: float = 0.0
var _volume: float = LT.BUCKET_VOLUME
var _rate: float = 0.0
var _rate_history: Array[Vector2] = [] # (clock, rate)
var _impact_started: bool = false
var _pour_age: float = 0.0
var _tail_age: float = -1.0
var _slosh: float = 0.0
var _slosh_vel: float = 0.0
var _cap_press: float = 0.0
var _cap_squash: float = 0.0
var _cap_squash_vel: float = 0.0
var _button_down: float = 0.0
var _drip_timer: float = 0.0
var _spill_timer: float = 0.0
var _last_origin := Vector3.ZERO
var _last_v0 := Vector3.ZERO
var _last_hit: float = 0.5
var _rng := RandomNumberGenerator.new()
var _gush: Node
var _bodies: int = 0


func setup(field: Node3D, tower: Node3D, button: Node3D) -> void:
	_rng.randomize()
	_field = field
	_tower = tower
	_button = button
	_pivot = tower.find_child("TankPivot", true, false) as Node3D
	_pour = tower.find_child("PourPoint", true, false) as Node3D
	_fill = tower.find_child("FillSurface", true, false) as Node3D
	_cap = button.find_child("ButtonCap", true, false) as Node3D if button != null else null
	if _pivot == null or _pour == null:
		push_error("[Liquid] water tower is missing TankPivot or PourPoint")
	if _fill != null:
		_fill_base = _fill.position
		_fill_basis = _fill.basis
		_read_fill_meta()
	if _cap != null:
		_cap_base = _cap.position
		_cap_scale = _cap.scale
	Feedback.warm([&"button_click", &"bell_ding", &"wood_creak", &"water_gush", &"splash_big", &"splash_small", &"water_drip", &"chime_ready", &"water_flow", &"waterfall"])
	_jet = Jet.new()
	add_child(_jet)
	_jet.set_foam_texture(field.call(&"get_foam_texture"))
	if button != null:
		_build_trigger()


func can_trigger() -> bool:
	return state == State.READY


func trigger() -> void:
	if not can_trigger():
		return
	state = State.ANTICIPATION
	_t = 0.0
	_cap_squash_vel = -9.0
	_button_down = 1.0
	var tree: SceneTree = get_tree()
	Feedback.play(tree, &"button_click", -2.0, 1.0)
	Feedback.trauma(tree, LT.TRAUMA_BUTTON)
	Feedback.rumble(LT.RUMBLE_BUTTON)
	Feedback.play(tree, &"bell_ding", -4.0, 1.0)
	Feedback.play(tree, &"wood_creak", -6.0, 1.1)


func set_night(amount: float) -> void:
	_jet.material.set_shader_parameter(&"day", 1.0 - amount)
	_jet.material.set_shader_parameter(&"scatter_color", LT.SCATTER_COLOR.lerp(LT.NIGHT_SCATTER_COLOR, amount))
	_jet.material.set_shader_parameter(&"foam_color", LT.FOAM_COLOR.lerp(LT.NIGHT_FOAM_COLOR, amount))


func _build_trigger() -> void:
	_area = Area3D.new()
	_area.name = "LiquidButtonTrigger"
	_area.collision_layer = 0
	_area.collision_mask = PLAYER_LAYER
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = LT.BUTTON_TRIGGER_RADIUS
	cyl.height = 0.45
	shape.shape = cyl
	shape.position = Vector3(0.0, 0.2, 0.0)
	_area.add_child(shape)
	_button.add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _on_body_entered(_body: Node3D) -> void:
	_bodies += 1
	trigger()


func _on_body_exited(_body: Node3D) -> void:
	_bodies = maxi(0, _bodies - 1)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_clock += delta
	_t += delta
	var tree: SceneTree = get_tree()
	match state:
		State.ANTICIPATION:
			var k: float = clampf(_t / LT.ANTICIPATION_TIME, 0.0, 1.0)
			var amp: float = LT.ANTICIPATION_ANGLE_DEG * (0.35 + 0.65 * k)
			_angle = amp * sin(k * TAU * LT.ANTICIPATION_SWINGS) * (1.0 - smoothstep(0.85, 1.0, k) * 0.6)
			_spill_timer -= delta
			if _angle > amp * 0.7 and _spill_timer <= 0.0:
				_spill_timer = 0.18
				_spill(6, 0.06)
			if _t >= LT.ANTICIPATION_TIME:
				state = State.TIPPING
				_t = 0.0
				Feedback.play(tree, &"wood_creak", -2.0, 0.85)
		State.TIPPING:
			var k: float = clampf(_t / LT.TIP_TIME, 0.0, 1.0)
			_angle = LT.TIP_ANGLE_DEG * pow(k, 2.3)
			if k >= 1.0:
				state = State.POURING
				_t = 0.0
				Feedback.trauma(tree, LT.TRAUMA_TIP)
				Feedback.play(tree, &"wood_creak", -3.0, 0.7)
		State.POURING:
			var s: float = _t
			_angle = LT.TIP_ANGLE_DEG + 7.0 * exp(-5.0 * s) * sin(s * 16.0)
			if _volume <= LT.BUCKET_VOLUME * 0.01 and _rate < 0.05:
				state = State.HOLD
				_t = 0.0
		State.HOLD:
			_angle = LT.TIP_ANGLE_DEG + 1.5 * exp(-3.0 * _t) * sin(_t * 12.0)
			_spill_timer -= delta
			if _spill_timer <= 0.0:
				_spill_timer = _rng.randf_range(0.1, 0.35)
				_spill(2, 0.02)
			if _t >= LT.EMPTY_HOLD_TIME:
				state = State.RETURNING
				_t = 0.0
				Feedback.play(tree, &"wood_creak", -4.0, 1.25)
		State.RETURNING:
			var k: float = clampf(_t / LT.RETURN_TIME, 0.0, 1.0)
			_angle = LT.TIP_ANGLE_DEG * (1.0 - _ease_out_bounce(k))
			if k >= 1.0:
				state = State.REFILLING
				_t = 0.0
				_volume = 0.0
				Feedback.trauma(tree, LT.TRAUMA_RETURN)
				Feedback.rumble(LT.RUMBLE_RETURN)
				Feedback.play(tree, &"wood_creak", -5.0, 1.4)
		State.REFILLING:
			_angle = 0.0
			_volume = LT.BUCKET_VOLUME * clampf(_t / LT.REFILL_TIME, 0.0, 1.0)
			_drip_timer -= delta
			if _drip_timer <= 0.0:
				_drip_timer = _rng.randf_range(0.45, 0.9)
				Feedback.play(tree, &"water_drip", -10.0, _rng.randf_range(0.9, 1.15))
				_drip()
			if _t >= LT.REFILL_TIME:
				state = State.READY
				_volume = LT.BUCKET_VOLUME
				_button_down = 0.0
				_cap_squash_vel = 6.0
				Feedback.play(tree, &"chime_ready", -3.0, 1.0)
		_:
			_angle = 0.0
	_pivot.rotation.x = deg_to_rad(_angle)
	_update_pour(delta)
	_update_fill(delta)
	_update_cap(delta)


func _update_pour(delta: float) -> void:
	var tree: SceneTree = get_tree()
	var tilt: float = clampf((_angle - LT.POUR_START_DEG) / (LT.TIP_ANGLE_DEG - LT.POUR_START_DEG), 0.0, 1.0)
	var fill: float = _volume / LT.BUCKET_VOLUME
	var pouring_state: bool = state == State.TIPPING or state == State.POURING or state == State.HOLD
	_rate = 0.0
	if pouring_state and _volume > 0.0:
		_rate = LT.POUR_RATE_MAX * minf(tilt * 3.0, 1.0) * pow(fill, 0.7) * (1.0 if fill > 0.015 else 3.0)
		_rate = minf(_rate, _volume / maxf(delta, 1e-4))
		_volume -= _rate * delta
	var flow: float = clampf(_rate / LT.POUR_RATE_MAX, 0.0, 1.0)

	var origin: Vector3 = _pour.global_position
	var fwd: Vector3 = _tower.global_basis.z.normalized()
	var opening: Vector3 = _pivot.global_basis.y.normalized()
	var v0: Vector3 = (fwd * 0.75 + opening * 0.45) * LT.JET_SPEED * (0.55 + 0.45 * sqrt(flow))
	v0.y = minf(v0.y, 0.6)
	if flow > 0.001:
		_last_origin = origin
		_last_v0 = v0
		_last_hit = _flight_time(origin, v0)
		if _tail_age >= 0.0 or _pour_age <= 0.0:
			_tail_age = -1.0
			_pour_age = 0.0
			_impact_started = false
			Feedback.play(tree, &"water_gush", -1.0, 1.0)
		_pour_age += delta
	elif _pour_age > 0.0:
		if _tail_age < 0.0:
			_tail_age = 0.0
		_tail_age += delta
	_rate_history.append(Vector2(_clock, _rate))
	while _rate_history.size() > 2 and _clock - _rate_history[1].x > 3.0:
		_rate_history.pop_front()

	if _pour_age <= 0.0:
		_jet.hide_jet()
		return
	var t_hit: float = _last_hit
	var head: float = minf(_pour_age, t_hit)
	var tail: float = 0.0 if _tail_age < 0.0 else minf(_tail_age, t_hit)
	var radius: float = LT.JET_RADIUS * pow(maxf(flow, 0.06), 0.65)
	if _tail_age >= 0.0:
		radius = LT.JET_RADIUS * 0.15 * maxf(0.0, 1.0 - _tail_age * 1.5)
	_jet.build(_last_origin if _tail_age >= 0.0 else origin, _last_v0 if _tail_age >= 0.0 else v0, radius, tail, head, flow, _clock)

	var g := Vector3(0.0, -LT.GRAVITY, 0.0)
	var hit: Vector3 = _last_origin + _last_v0 * t_hit + 0.5 * g * t_hit * t_hit
	var hit_vel: Vector3 = _last_v0 + g * t_hit
	var landing_rate: float = _rate_at(_clock - t_hit)
	var fx: Node3D = _field.get(&"fx")
	if _pour_age >= t_hit and landing_rate > 0.0:
		var horiz := Vector3(hit_vel.x, 0.0, hit_vel.z)
		_field.call(&"add_water", hit, landing_rate * delta, horiz, LT.IMPACT_RADIUS, LT.IMPACT_PUSH)
		var lf: float = clampf(landing_rate / LT.POUR_RATE_MAX, 0.0, 1.0)
		if not _impact_started:
			_impact_started = true
			Feedback.play(tree, &"splash_big", 0.0, 1.0)
			Feedback.trauma(tree, LT.TRAUMA_IMPACT)
			Feedback.rumble(LT.RUMBLE_IMPACT)
			fx.call(&"splash", hit, 150, 4.5, 4.2, 0.5, horiz * 0.3)
			fx.call(&"mist", hit, 18, 1.2, 1.2, 1.6)
			fx.call(&"crown", hit, 0.55, 0.5)
		fx.call(&"splash", hit, int(ceil(lf * 160.0 * delta + _rng.randf())), 2.6 * (0.5 + lf), 2.6 * (0.5 + lf), 0.45, horiz * 0.25)
		if _rng.randf() < lf * 10.0 * delta:
			fx.call(&"mist", hit, 1, 0.7, 0.8, 1.2)
	if flow > 0.05:
		fx.call(&"spray", origin + v0 * 0.05, v0 * 1.05, int(ceil(flow * 50.0 * delta)), 0.5)
		# The heavy stream sheds drops and sheets from its skin all along the fall.
		var gv := Vector3(0.0, -LT.GRAVITY, 0.0)
		for i: int in int(ceil(flow * 140.0 * delta)):
			var tt: float = _rng.randf_range(0.05, minf(_pour_age, t_hit) * 0.95)
			var pv: Vector3 = v0 + gv * tt
			var side: Vector3 = pv.cross(Vector3.UP).normalized()
			if side.length() < 0.1:
				side = Vector3.RIGHT
			var out: Vector3 = (side * _rng.randf_range(-1.0, 1.0) + pv.cross(side).normalized() * _rng.randf_range(-0.4, 0.4)).normalized()
			var pp: Vector3 = origin + v0 * tt + 0.5 * gv * tt * tt + out * radius * 0.9
			fx.call(&"spray", pp, pv * 0.9 + out * _rng.randf_range(0.8, 2.2), 1, 0.35)
	if _tail_age >= 0.0 and _tail_age > t_hit + 0.1:
		_pour_age = 0.0
		_tail_age = -1.0
		_jet.hide_jet()


func _flight_time(origin: Vector3, v0: Vector3) -> float:
	var t: float = 0.0
	var dt: float = 0.02
	var g: float = LT.GRAVITY
	for i: int in 150:
		t += dt
		var p: Vector3 = origin + v0 * t + Vector3(0.0, -0.5 * g * t * t, 0.0)
		var ground: float = float(_field.call(&"ground_height", p.x, p.z)) + float(_field.call(&"depth_at", p))
		if p.y <= ground:
			# Refine between the last two samples.
			var lo: float = t - dt
			var hi: float = t
			for k: int in 6:
				var mid: float = 0.5 * (lo + hi)
				var pm: Vector3 = origin + v0 * mid + Vector3(0.0, -0.5 * g * mid * mid, 0.0)
				if pm.y <= float(_field.call(&"ground_height", pm.x, pm.z)):
					hi = mid
				else:
					lo = mid
			return hi
	return t


func _rate_at(time: float) -> float:
	var r: float = 0.0
	for s: Vector2 in _rate_history:
		if s.x <= time:
			r = s.y
		else:
			break
	return r


func _spill(count: int, volume: float) -> void:
	var fx: Node3D = _field.get(&"fx")
	var fwd: Vector3 = _tower.global_basis.z.normalized()
	var p: Vector3 = _pour.global_position
	fx.call(&"spray", p, fwd * 1.3 + Vector3.UP * 0.8, count, 0.7)
	var land := Vector3(p.x + fwd.x * 0.9, 0.0, p.z + fwd.z * 0.9)
	land.y = float(_field.call(&"ground_height", land.x, land.z))
	_field.call(&"add_water", land, volume * 0.5, Vector3.ZERO, 0.4, 0.0)
	Feedback.play(get_tree(), &"splash_small", -14.0, _rng.randf_range(1.0, 1.3))


func _drip() -> void:
	var fx: Node3D = _field.get(&"fx")
	var p: Vector3 = _pour.global_position + Vector3(_rng.randf_range(-0.3, 0.3), -0.05, _rng.randf_range(-0.1, 0.1))
	fx.call(&"spray", p, Vector3(0.0, -0.3, 0.0), 1, 0.1)


## BUILDINGS publishes the inner wall span on FillSurface (unit disc scaled to the radius): y_empty/y_full
## in the tank frame and the matching radii. The tank frame offset is recovered from the authored pose.
func _read_fill_meta() -> void:
	for k: StringName in [&"y_empty", &"y_full", &"radius_empty", &"radius_full"]:
		if not _fill.has_meta(k):
			return
	_fill_y_range = Vector2(float(_fill.get_meta(&"y_empty")), float(_fill.get_meta(&"y_full")))
	_fill_r_range = Vector2(float(_fill.get_meta(&"radius_empty")), float(_fill.get_meta(&"radius_full")))
	var r0: float = _fill_basis.get_scale().x
	var dr: float = _fill_r_range.y - _fill_r_range.x
	var k0: float = clampf((r0 - _fill_r_range.x) / dr, 0.0, 1.0) if absf(dr) > 1e-5 else 1.0
	_fill_y_offset = _fill_base.y - lerpf(_fill_y_range.x, _fill_y_range.y, k0)
	_fill_basis = _fill_basis.orthonormalized()
	_fill_meta = true


func _update_fill(delta: float) -> void:
	if _fill == null:
		return
	var fill: float = _volume / LT.BUCKET_VOLUME
	_fill.visible = fill > 0.02 and _angle < 70.0
	var ang_vel: float = (_angle - _angle_prev) / maxf(delta, 1e-4)
	var ang_acc: float = (ang_vel - _angle_vel_prev) / maxf(delta, 1e-4)
	_angle_prev = _angle
	_angle_vel_prev = ang_vel
	_slosh_vel += (-60.0 * _slosh - 3.2 * _slosh_vel - ang_acc * 0.002) * delta
	_slosh += _slosh_vel * delta
	_slosh = clampf(_slosh, -0.5, 0.5)
	if state == State.REFILLING:
		_slosh += sin(_clock * 9.0) * 0.004
	# Level surface: counter-rotate the tank tilt (clamped so it stays inside the tank) plus the slosh.
	var level: float = -deg_to_rad(minf(_angle, 40.0)) + _slosh
	if _fill_meta:
		var r: float = lerpf(_fill_r_range.x, _fill_r_range.y, fill)
		_fill.basis = Basis(Vector3.RIGHT, level) * _fill_basis * Basis.from_scale(Vector3(r, 1.0, r))
		_fill.position = Vector3(_fill_base.x, _fill_y_offset + lerpf(_fill_y_range.x, _fill_y_range.y, fill), _fill_base.z)
	else:
		_fill.basis = Basis(Vector3.RIGHT, level) * _fill_basis
		_fill.position = _fill_base - Vector3(0.0, (1.0 - fill) * LT.FILL_DEPTH, 0.0)


func _update_cap(delta: float) -> void:
	if _cap == null:
		return
	_cap_squash_vel += (-180.0 * _cap_squash - 11.0 * _cap_squash_vel) * delta
	_cap_squash += _cap_squash_vel * delta
	_cap_press = move_toward(_cap_press, _button_down, delta * (14.0 if _button_down > 0.5 else 3.5))
	var sq: float = clampf(_cap_squash, -0.45, 0.35)
	_cap.scale = _cap_scale * Vector3(1.0 - sq * 0.6, 1.0 + sq, 1.0 - sq * 0.6)
	_cap.position = _cap_base - Vector3(0.0, LT.BUTTON_DROP * _cap_press, 0.0)


static func _ease_out_bounce(x: float) -> float:
	var n1: float = 7.5625
	var d1: float = 2.75
	if x < 1.0 / d1:
		return n1 * x * x
	elif x < 2.0 / d1:
		x -= 1.5 / d1
		return n1 * x * x + 0.75
	elif x < 2.5 / d1:
		x -= 2.25 / d1
		return n1 * x * x + 0.9375
	x -= 2.625 / d1
	return n1 * x * x + 0.984375
