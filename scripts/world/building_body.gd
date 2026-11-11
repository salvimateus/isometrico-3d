extends StaticBody3D

## Pick + physics body of a building or wall. `bump()` wobbles the slot toward the impact and puffs dust.

const Tuning := preload("res://scripts/tuning.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")

var slot: Node3D = null
var dust_radius: float = 1.5

var _tween: Tween
var _rest_basis: Basis = Basis()
var _has_rest: bool = false
var _last_bump: float = -100.0


func bump(impulse: Vector3) -> void:
	if slot == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_bump < Tuning.BUMP_COOLDOWN:
		return
	_last_bump = now
	var strength: float = clampf(impulse.length() / Tuning.BUMP_REFERENCE_IMPULSE, 0.35, 1.5)
	var dir := Vector3(impulse.x, 0.0, impulse.z)
	if dir.length_squared() < 1e-6:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	var tilt_axis: Vector3 = Vector3.UP.cross(dir).normalized()
	var baked: bool = slot.has_meta(&"baked")
	var angle: float = deg_to_rad(Tuning.BUMP_TILT_DEG) * strength
	var t: float = Tuning.BUMP_WOBBLE_TIME
	# Remember the slot's resting basis (yaw of rotated props) once, so the wobble always returns to it.
	if not _has_rest:
		_rest_basis = slot.basis
		_has_rest = true
	if _tween and _tween.is_valid():
		_tween.kill()
	slot.basis = _rest_basis
	if baked:
		_puff(dir, strength)
		return
	_tween = slot.create_tween()
	_tween.tween_method(_apply.bind(tilt_axis), 0.0, 1.0, t).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(func() -> void: slot.basis = _rest_basis)
	set_meta(&"bump_angle", angle)
	_puff(dir, strength)


func _apply(u: float, tilt_axis: Vector3) -> void:
	var angle: float = get_meta(&"bump_angle", 0.0)
	var decay: float = exp(-u * 5.0)
	var wave: float = sin(u * TAU * 2.2)
	var squash: float = 1.0 - Tuning.BUMP_SQUASH * decay * absf(wave)
	var b := Basis(tilt_axis, angle * decay * wave)
	slot.basis = b.scaled(Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))) * _rest_basis


func _puff(dir: Vector3, strength: float) -> void:
	var fx: Node = get_tree().get_first_node_in_group(&"world_fx")
	if fx != null:
		fx.call(&"dust", slot.global_position + dir * -0.2, dust_radius, strength)
	Sfx.play(get_tree(), &"building_thud", lerpf(-8.0, 0.0, clampf(strength, 0.0, 1.0)), randf_range(0.92, 1.05))

