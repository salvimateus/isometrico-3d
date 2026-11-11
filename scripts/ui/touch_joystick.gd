extends RefCounted

## Dynamic move stick: rests as a ghost at `home`, spawns under the finger, drags its base along when the
## finger passes the rim, and eases back home on release. Pure state + drawing.

const Tuning := preload("res://scripts/tuning.gd")
const Icons := preload("res://scripts/ui/touch_icons.gd")

const RUN_COLOR := Color("FFC93C")
const NAVY := Color(0.05, 0.07, 0.14)
const OUTLINE := Color(0.03, 0.03, 0.08)

var home: Vector2 = Vector2.ZERO
var radius: float = 100.0
var knob_radius: float = 42.0
var active: bool = false
var base: Vector2 = Vector2.ZERO
## Knob offset from the base, length <= radius.
var knob: Vector2 = Vector2.ZERO

var _return_from: Vector2 = Vector2.ZERO
var _return_t: float = 1.0
var _presence: float = 0.0
var _run_glow: float = 0.0
var _run_flash: float = 0.0
var _press_pop: float = 0.0


func place(p_home: Vector2, p_radius: float, p_knob_radius: float) -> void:
	home = p_home
	radius = p_radius
	knob_radius = p_knob_radius
	if not active and _return_t >= 1.0:
		base = home


func press(p: Vector2) -> void:
	active = true
	base = p
	knob = Vector2.ZERO
	_return_t = 1.0
	_press_pop = 1.0


func drag(p: Vector2) -> void:
	if not active:
		return
	var off: Vector2 = p - base
	if off.length() > radius:
		# Past the rim the base follows the finger instead of locking.
		base = p - off.normalized() * radius
		off = off.normalized() * radius
	knob = off


func release() -> void:
	if not active:
		return
	active = false
	_return_from = base
	_return_t = 0.0


## Raw deflection 0..1 (before deadzone).
func deflection() -> float:
	return knob.length() / radius if active else 0.0


## Analog output with a small radial deadzone, remapped to 0..1. Screen space: +x right, +y down.
func output() -> Vector2:
	var d: float = deflection()
	if d <= Tuning.TOUCH_STICK_DEADZONE:
		return Vector2.ZERO
	return knob.normalized() * minf((d - Tuning.TOUCH_STICK_DEADZONE) / (1.0 - Tuning.TOUCH_STICK_DEADZONE), 1.0)


func in_run_band() -> bool:
	return deflection() >= Tuning.TOUCH_STICK_RUN_BAND


func flash_run() -> void:
	_run_flash = 1.0


func update(delta: float) -> void:
	if not active:
		knob = knob.lerp(Vector2.ZERO, 1.0 - exp(-delta * 22.0))
		if _return_t < 1.0:
			_return_t = minf(_return_t + delta / Tuning.TOUCH_STICK_RETURN_TIME, 1.0)
			var e: float = 1.0 - pow(1.0 - _return_t, 3.0)
			base = _return_from.lerp(home, e)
		else:
			base = home
	_presence = move_toward(_presence, 1.0 if active else 0.0, delta / (0.08 if active else Tuning.TOUCH_FADE_TIME))
	_run_glow = move_toward(_run_glow, 1.0 if active and in_run_band() else 0.0, delta / 0.12)
	_run_flash = maxf(_run_flash - delta / 0.45, 0.0)
	_press_pop = maxf(_press_pop - delta / 0.25, 0.0)


func draw(ci: CanvasItem) -> void:
	# Ghost: rim + knob only. In use: light dark fill, brighter rim, knob at its own opacity.
	var a: float = lerpf(Tuning.TOUCH_STICK_GHOST_ALPHA, Tuning.TOUCH_STICK_ACTIVE_ALPHA, _presence)
	var r: float = radius * (1.0 + 0.06 * _press_pop * _press_pop)
	var c: Vector2 = base

	if _run_glow > 0.0 or _run_flash > 0.0:
		Icons.draw_glow(ci, c, r * (1.45 + 0.25 * _run_flash), Color(RUN_COLOR, 0.35 * maxf(_run_glow, _run_flash)))
	ci.draw_circle(c, r, Color(NAVY, Tuning.TOUCH_STICK_FILL_ALPHA * _presence + 0.04), true, -1.0, true)
	ci.draw_circle(c, r * 0.62, Color(1, 1, 1, 0.12 * a), false, 2.0, true)
	ci.draw_circle(c, r + 1.5, Color(OUTLINE, 0.5 * a), false, 1.5, true)
	ci.draw_circle(c, r - 1.5, Color(1, 1, 1, a), false, 3.0, true)

	# Four small chevrons hint the directions.
	for i: int in 4:
		var d := Vector2.from_angle(TAU * float(i) / 4.0)
		var side := Vector2(-d.y, d.x)
		var tip: Vector2 = c + d * r * 0.86
		var back: Vector2 = c + d * r * 0.76
		var chev := PackedVector2Array([back + side * r * 0.08, tip, back - side * r * 0.08])
		ci.draw_polyline(chev, Color(OUTLINE, 0.35 * a), 5.0, true)
		ci.draw_polyline(chev, Color(1, 1, 1, 0.8 * a), 3.0, true)

	# Run band: the outer rim lights up gold.
	if _run_glow > 0.0:
		ci.draw_circle(c, r - 2.0, Color(RUN_COLOR, 0.95 * _run_glow), false, 6.0 + 4.0 * _run_flash, true)
		ci.draw_circle(c, r * Tuning.TOUCH_STICK_RUN_BAND, Color(RUN_COLOR, 0.3 * _run_glow), false, 2.0, true)

	# Direction wedge on the rim, towards the knob.
	if active and knob.length() > radius * Tuning.TOUCH_STICK_DEADZONE:
		var ang: float = knob.angle()
		var col: Color = Color(1, 1, 1).lerp(RUN_COLOR, _run_glow)
		ci.draw_arc(c, r - 2.0, ang - 0.55, ang + 0.55, 24, Color(col, 0.85 * clampf(deflection(), 0.0, 1.0)), 7.0, true)

	var k: Vector2 = c + knob
	var kr: float = knob_radius * (1.0 + 0.08 * _press_pop)
	var ka: float = lerpf(Tuning.TOUCH_STICK_GHOST_ALPHA, Tuning.TOUCH_KNOB_ALPHA, _presence)
	var knob_col: Color = Color(0.96, 0.97, 1.0).lerp(Color("FFE08A"), _run_glow * 0.7)
	ci.draw_circle(k, kr + 1.5, Color(OUTLINE, 0.6 * ka), false, 2.0, true)
	ci.draw_circle(k, kr, Color(knob_col.darkened(0.2), ka), true, -1.0, true)
	ci.draw_circle(k + Vector2(0, -kr * 0.08), kr * 0.88, Color(knob_col, ka), true, -1.0, true)
	ci.draw_circle(k + Vector2(-kr * 0.18, -kr * 0.3), kr * 0.3, Color(1, 1, 1, 0.5 * ka), true, -1.0, true)
