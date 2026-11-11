extends RefCounted

## One round touch button: squash on press, springy pop on release, ripple, optional glow and progress ring.
## Mobile-game transparency: dark translucent face, light rim, white icon with a thin dark outline.
## Pure state + drawing; the touch controls own input routing and call `draw` on their canvas.

const Tuning := preload("res://scripts/tuning.gd")
const Icons := preload("res://scripts/ui/touch_icons.gd")

const FACE := Color(0.05, 0.07, 0.14)
const OUTLINE := Color(0.03, 0.03, 0.08)
const SPRING_K: float = 620.0
const SPRING_DAMP: float = 17.0

var kind: StringName
var center: Vector2 = Vector2.ZERO
var radius: float = 40.0
## Rim tint (white for gadgets, gold for the main button).
var accent: Color = Color.WHITE
var shown: bool = true
## Interact style: dim until `lit_target`, then a colored face with a pulsing glow.
var dim_when_unlit: bool = false
var lit_target: bool = false
var lit: float = 0.0
var glow_color: Color = Color("D77CF0")
## Progress ring 0..1; negative hides it.
var ring: float = -1.0
var icon_variant: int = 0
## Upper bound on opacity (gadgets fade to it after a while without touches).
var cap_target: float = 1.0

var pressed: bool = false
var appear: float = 1.0
var _cap: float = 1.0
var _press: float = 0.0
var _s: float = 1.0
var _v: float = 0.0
var _ripples: Array[Vector3] = []
var _clock: float = 0.0
var _lit_pop: float = 0.0


func _init(p_kind: StringName) -> void:
	kind = p_kind


func hit(p: Vector2) -> bool:
	return shown and appear > 0.5 and p.distance_to(center) <= radius * Tuning.TOUCH_HIT_SLOP


func press(p: Vector2) -> void:
	pressed = true
	_v -= 6.0
	_ripples.append(Vector3(p.x - center.x, p.y - center.y, 0.0))


func release() -> void:
	if not pressed:
		return
	pressed = false
	_v += 9.0


## Extra pop without a press (e.g. when the button lights up).
func kick(amount: float = 7.0) -> void:
	_v += amount


func update(delta: float) -> void:
	_clock += delta
	var target: float = 0.88 if pressed else 1.0
	# Semi-implicit damped spring: overshoots a little on release (the "pop").
	_v += ((target - _s) * SPRING_K - _v * SPRING_DAMP) * delta
	_s += _v * delta
	_press = move_toward(_press, 1.0 if pressed else 0.0, delta / (0.05 if pressed else 0.2))
	var was_lit: bool = lit > 0.5
	lit = move_toward(lit, 1.0 if lit_target else 0.0, delta / 0.18)
	if lit > 0.5 and not was_lit:
		_lit_pop = 1.0
		kick(10.0)
	_lit_pop = maxf(_lit_pop - delta / 0.5, 0.0)
	appear = move_toward(appear, 1.0 if shown else 0.0, delta / 0.16)
	_cap = move_toward(_cap, cap_target, delta / Tuning.TOUCH_GADGET_IDLE_FADE)
	for i: int in range(_ripples.size() - 1, -1, -1):
		var r: Vector3 = _ripples[i]
		r.z += delta / Tuning.TOUCH_RIPPLE_TIME
		if r.z >= 1.0:
			_ripples.remove_at(i)
		else:
			_ripples[i] = r


## Overall opacity: idle / pressed / dim / lit levels from the tuning, times appear and the idle cap.
func opacity() -> float:
	var rest: float = Tuning.TOUCH_BUTTON_IDLE_ALPHA
	if dim_when_unlit:
		rest = lerpf(Tuning.TOUCH_INTERACT_DIM_ALPHA, Tuning.TOUCH_INTERACT_LIT_ALPHA, lit)
	var k: float = lerpf(rest, maxf(rest, Tuning.TOUCH_BUTTON_PRESSED_ALPHA), _press)
	if not pressed:
		k = minf(k, _cap)
	return k * appear * appear * (3.0 - 2.0 * appear)


func draw(ci: CanvasItem) -> void:
	if appear <= 0.01:
		return
	var a: float = appear * appear * (3.0 - 2.0 * appear)
	var k: float = opacity()
	var sy: float = _s * lerpf(0.6, 1.0, a)
	var sx: float = (1.0 - (1.0 - _s) * 0.3) * lerpf(0.6, 1.0, a)
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * Tuning.TOUCH_INTERACT_PULSE_HZ)
	var r: float = radius

	if lit > 0.0:
		var g: float = lit * (0.45 + 0.35 * pulse) * a
		var glow_r: float = r * (1.75 + 0.25 * pulse + 0.6 * _lit_pop)
		Icons.draw_glow(ci, center, glow_r, Color(glow_color.lightened(0.3), g))
		var phase: float = fmod(_clock * Tuning.TOUCH_INTERACT_PULSE_HZ, 1.0)
		ci.draw_circle(center, r * (1.06 + 0.45 * phase), Color(glow_color.lightened(0.55), 0.85 * (1.0 - phase) * lit * a), false, maxf(2.5, r * 0.08 * (1.0 - phase)), true)

	ci.draw_set_transform(center, 0.0, Vector2(sx, sy))
	var face: Color = FACE.lerp(glow_color.darkened(0.15), lit)
	var face_alpha: float = k * lerpf(Tuning.TOUCH_BUTTON_FILL_ALPHA, 0.9, lit)
	ci.draw_circle(Vector2.ZERO, r, Color(face, face_alpha), true, -1.0, true)
	if _press > 0.0:
		ci.draw_circle(Vector2.ZERO, r * 0.94, Color(1, 1, 1, 0.12 * _press * a), true, -1.0, true)
	# Thin dark hairline outside the light rim keeps the edge readable on bright ground or sky.
	var rim_w: float = maxf(2.5, r * 0.05)
	ci.draw_circle(Vector2.ZERO, r + 1.0, Color(OUTLINE, 0.5 * k), false, 1.5, true)
	var rim_col: Color = accent.lerp(Color.WHITE, lit * (0.4 + 0.6 * pulse))
	ci.draw_circle(Vector2.ZERO, r - rim_w * 0.5, Color(rim_col, minf(k * 1.35, 1.0)), false, rim_w, true)

	for rp: Vector3 in _ripples:
		var t: float = rp.z
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		var o := Vector2(rp.x, rp.y).lerp(Vector2.ZERO, e)
		ci.draw_circle(o, lerpf(r * 0.35, r * 1.05, e), Color(1, 1, 1, 0.5 * (1.0 - t) * a), false, lerpf(r * 0.16, 1.5, t), true)

	var icon_alpha: float = minf(Tuning.TOUCH_ICON_ALPHA * k / Tuning.TOUCH_BUTTON_IDLE_ALPHA, 1.0)
	var icon_scale: float = 1.0 + 0.18 * _lit_pop
	ci.draw_set_transform(center, 0.0, Vector2(sx, sy) * icon_scale)
	Icons.draw_outlined(ci, kind, r * 0.5, icon_alpha, icon_variant)
	ci.draw_set_transform(center, 0.0, Vector2(sx, sy))

	if ring >= 0.0:
		var rr: float = r + maxf(7.0, r * 0.11)
		var w: float = maxf(5.0, r * 0.08)
		ci.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, Color(OUTLINE, 0.4 * a), w + 3.0, true)
		ci.draw_arc(Vector2.ZERO, rr, -PI * 0.5, -PI * 0.5 + TAU * clampf(ring, 0.0, 1.0), 64, Color(1, 1, 1, 0.9 * a), w, true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
