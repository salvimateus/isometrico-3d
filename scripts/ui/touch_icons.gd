extends RefCounted

## Vector glyphs for the touch controls, drawn around the origin of the current canvas transform.
## `s` is the glyph half-size in pixels.

static var _glow: GradientTexture2D = null
## Line-width multiplier for the outline pass (lines need extra width beyond the uniform scale).
static var _stroke: float = 1.0


## Soft radial blob (white center, transparent edge) used for glows and shadows.
static func glow_texture() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.42))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## White glyph over a slightly larger dark copy: a thin outline that reads on sky, grass and night.
static func draw_outlined(ci: CanvasItem, kind: StringName, s: float, alpha: float, variant: int = 0) -> void:
	draw(ci, kind, s * 1.12, Color(0.03, 0.03, 0.08, 0.5 * alpha), variant, 1.6)
	draw(ci, kind, s, Color(1, 1, 1, alpha), variant)


static func draw(ci: CanvasItem, kind: StringName, s: float, color: Color, variant: int = 0, stroke: float = 1.0) -> void:
	_stroke = stroke
	match kind:
		&"jump":
			_jump(ci, Vector2.ZERO, s, color)
		&"interact":
			if variant == 1:
				_launch(ci, Vector2.ZERO, s, color)
			else:
				_hand(ci, Vector2.ZERO, s, color)
		&"camera":
			if variant == 1:
				_iso_cube(ci, s, color)
			else:
				_eye(ci, s, color)
		&"day_night":
			if variant == 1:
				_moon(ci, s, color)
			else:
				_sun(ci, s, color)
		&"swap":
			_swap(ci, s, color)
	_stroke = 1.0


static func _poly(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	ci.draw_colored_polygon(pts, color)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, color, 1.2 * _stroke, true)


static func _jump(ci: CanvasItem, o: Vector2, s: float, color: Color) -> void:
	# Chunky up arrow with a short stem: reads as "hop" at a glance.
	_poly(ci, PackedVector2Array([
		o + Vector2(0.0, -0.95) * s, o + Vector2(0.82, -0.08) * s, o + Vector2(0.34, -0.08) * s,
		o + Vector2(0.34, 0.5) * s, o + Vector2(-0.34, 0.5) * s, o + Vector2(-0.34, -0.08) * s,
		o + Vector2(-0.82, -0.08) * s,
	]), color)
	ci.draw_rect(Rect2(o + Vector2(-0.34, 0.66) * s, Vector2(0.68, 0.22) * s), color)


static func _hand(ci: CanvasItem, o: Vector2, s: float, color: Color) -> void:
	# Open palm: four rounded fingers, a thumb and the palm block.
	var w: float = 0.2 * s
	var tops: Array[float] = [-0.62, -0.86, -0.8, -0.56]
	for i: int in 4:
		var x: float = (-0.45 + 0.3 * float(i)) * s
		var top: Vector2 = o + Vector2(x, tops[i] * s)
		var bottom: Vector2 = o + Vector2(x, 0.1 * s)
		ci.draw_line(top, bottom, color, w * 1.25 * _stroke, true)
		ci.draw_circle(top, w * 0.62, color, true, -1.0, true)
	ci.draw_line(o + Vector2(0.48, 0.25) * s, o + Vector2(0.86, -0.12) * s, color, w * 1.25 * _stroke, true)
	ci.draw_circle(o + Vector2(0.86, -0.12) * s, w * 0.62, color, true, -1.0, true)
	_poly(ci, PackedVector2Array([
		o + Vector2(-0.58, -0.05) * s, o + Vector2(0.58, -0.05) * s, o + Vector2(0.5, 0.62) * s,
		o + Vector2(0.2, 0.9) * s, o + Vector2(-0.3, 0.9) * s, o + Vector2(-0.58, 0.55) * s,
	]), color)


static func _launch(ci: CanvasItem, o: Vector2, s: float, color: Color) -> void:
	# Ballistic arc with an arrow head and a little launch pad: "fire the catapult".
	var pts := PackedVector2Array()
	for i: int in 17:
		var t: float = float(i) / 16.0
		var x: float = lerpf(-0.78, 0.62, t)
		var y: float = 0.55 - 1.55 * t * (1.0 - t) * 2.0 + 0.35 * t
		pts.append(o + Vector2(x, y) * s)
	ci.draw_polyline(pts, color, 0.2 * s * _stroke, true)
	var tip: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (tip - pts[pts.size() - 3]).normalized()
	var side := Vector2(-dir.y, dir.x)
	_poly(ci, PackedVector2Array([tip + dir * 0.34 * s, tip + side * 0.26 * s, tip - side * 0.26 * s]), color)
	ci.draw_circle(o + Vector2(-0.78, 0.55) * s, 0.2 * s, color, true, -1.0, true)
	ci.draw_line(o + Vector2(-0.98, 0.86) * s, o + Vector2(-0.4, 0.86) * s, color, 0.16 * s * _stroke, true)


static func _eye(ci: CanvasItem, s: float, color: Color) -> void:
	# Shoulder view glyph: a camera body with a lens.
	var body := Rect2(Vector2(-0.82, -0.42) * s, Vector2(1.64, 1.08) * s)
	ci.draw_rect(body, color, false, 0.16 * s * _stroke, true)
	_poly(ci, PackedVector2Array([Vector2(-0.34, -0.42) * s, Vector2(-0.2, -0.66) * s, Vector2(0.2, -0.66) * s, Vector2(0.34, -0.42) * s]), color)
	ci.draw_circle(Vector2(0, 0.12) * s, 0.3 * s, color, false, 0.15 * s * _stroke, true)
	ci.draw_circle(Vector2(0, 0.12) * s, 0.1 * s, color, true, -1.0, true)


static func _iso_cube(ci: CanvasItem, s: float, color: Color) -> void:
	# Iso view glyph: an isometric block seen from above.
	var top := PackedVector2Array([Vector2(0, -0.86) * s, Vector2(0.78, -0.42) * s, Vector2(0, 0.02) * s, Vector2(-0.78, -0.42) * s])
	_poly(ci, top, color)
	var dim := Color(color, color.a * 0.62)
	_poly(ci, PackedVector2Array([Vector2(-0.78, -0.26) * s, Vector2(-0.08, 0.14) * s, Vector2(-0.08, 0.92) * s, Vector2(-0.78, 0.5) * s]), dim)
	_poly(ci, PackedVector2Array([Vector2(0.08, 0.14) * s, Vector2(0.78, -0.26) * s, Vector2(0.78, 0.5) * s, Vector2(0.08, 0.92) * s]), color)


static func _sun(ci: CanvasItem, s: float, color: Color) -> void:
	ci.draw_circle(Vector2.ZERO, 0.42 * s, color, true, -1.0, true)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var d := Vector2.from_angle(a)
		ci.draw_line(d * 0.62 * s, d * 0.9 * s, color, 0.15 * s * _stroke, true)


static func _moon(ci: CanvasItem, s: float, color: Color) -> void:
	var r: float = 0.78 * s
	var c2 := Vector2(0.46, -0.3) * s
	var d: float = c2.length()
	var mid: Vector2 = c2 * 0.5
	var perp: Vector2 = Vector2(-c2.y, c2.x).normalized() * sqrt(maxf(r * r - d * d * 0.25, 0.0))
	var p1: Vector2 = mid + perp
	var p2: Vector2 = mid - perp
	var pts := PackedVector2Array()
	var a1: float = p1.angle()
	var a2: float = p2.angle()
	# Outer arc: the long way round, away from the biting circle.
	var away: float = (-c2).angle()
	var span: float = wrapf(a2 - a1, 0.0, TAU)
	var mid_angle: float = a1 + span * 0.5
	if absf(angle_difference(mid_angle, away)) > PI * 0.5:
		span -= TAU
	for i: int in 25:
		pts.append(Vector2.from_angle(a1 + span * float(i) / 24.0) * r)
	# Inner arc back from p2 to p1 along the biting circle, inside the outer one.
	var b1: float = (p2 - c2).angle()
	var b2: float = (p1 - c2).angle()
	var bspan: float = wrapf(b2 - b1, 0.0, TAU)
	if (c2 + Vector2.from_angle(b1 + bspan * 0.5) * r).length() > r:
		bspan -= TAU
	for i: int in range(1, 24):
		pts.append(c2 + Vector2.from_angle(b1 + bspan * float(i) / 24.0) * r)
	_poly(ci, pts, color)
	ci.draw_circle(Vector2(0.62, 0.42) * s, 0.09 * s, color, true, -1.0, true)


static func _swap(ci: CanvasItem, s: float, color: Color) -> void:
	var w: float = 0.15 * s
	ci.draw_line(Vector2(-0.7, -0.3) * s, Vector2(0.5, -0.3) * s, color, w * _stroke, true)
	_poly(ci, PackedVector2Array([Vector2(0.86, -0.3) * s, Vector2(0.42, -0.62) * s, Vector2(0.42, 0.02) * s]), color)
	ci.draw_line(Vector2(0.7, 0.34) * s, Vector2(-0.5, 0.34) * s, color, w * _stroke, true)
	_poly(ci, PackedVector2Array([Vector2(-0.86, 0.34) * s, Vector2(-0.42, 0.02) * s, Vector2(-0.42, 0.66) * s]), color)
