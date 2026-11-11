extends Control

## Vector icon drawn in code: "gold" coin or "mana" drop.

var kind: StringName = &"gold"
## Sweep progress in [0, 1]; negative hides the shine band.
var shine: float = -1.0:
	set(v):
		shine = v
		queue_redraw()
## Halo intensity in [0, 1].
var flash: float = 0.0:
	set(v):
		flash = v
		queue_redraw()


func _init(p_kind: StringName = &"gold") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(46, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.46
	if flash > 0.001:
		var halo: Color = Color("FFE38A") if kind == &"gold" else Color("F0A8FF")
		for i: int in 4:
			var k: float = 1.0 + 0.16 * float(i + 1)
			draw_circle(c, r * k, Color(halo, flash * 0.22))
	if kind == &"gold":
		draw_circle(c + Vector2(0, 2.5), r, Color(0, 0, 0, 0.28))
		draw_circle(c, r, Color("C98A12"))
		draw_circle(c - Vector2(0, 1.5), r * 0.9, Color("FFC93C"))
		draw_circle(c - Vector2(0, 1.5), r * 0.62, Color("F2A91E"))
		draw_circle(c - Vector2(0, 2.5), r * 0.52, Color("FFD861"))
		draw_circle(c + Vector2(-r * 0.32, -r * 0.42), r * 0.16, Color(1, 1, 1, 0.85))
		_draw_shine(c - Vector2(0, 1.5), r * 0.86)
	else:
		var pts := PackedVector2Array()
		var steps: int = 28
		for i: int in steps + 1:
			var t: float = float(i) / steps
			var a: float = lerpf(-PI * 0.5, PI * 1.5, t)
			var rr: float = r * 0.78
			var p := Vector2(cos(a), sin(a)) * rr + c + Vector2(0, r * 0.2)
			var top_pull: float = pow(maxf(0.0, -sin(a)), 3.0)
			p.y -= top_pull * r * 0.75
			p.x = lerpf(p.x, c.x, top_pull * 0.85)
			pts.append(p)
		var shadow := PackedVector2Array()
		for p: Vector2 in pts:
			shadow.append(p + Vector2(0, 2.5))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
		draw_colored_polygon(pts, Color("8E2BB0"))
		var inner := PackedVector2Array()
		for p: Vector2 in pts:
			inner.append(c + (p - c) * 0.84 - Vector2(0, 1.5))
		draw_colored_polygon(inner, Color("C24BE0"))
		draw_circle(c + Vector2(-r * 0.22, r * 0.05), r * 0.17, Color(1, 0.85, 1, 0.9))
		_draw_shine(c + Vector2(0, r * 0.22), r * 0.5)


func _draw_shine(c: Vector2, radius: float) -> void:
	if shine < 0.0 or shine > 1.0:
		return
	var u := Vector2(1, 1).normalized()
	var v := Vector2(-u.y, u.x)
	var w: float = radius * 0.34
	var s0: float = clampf(lerpf(-radius - w, radius, shine), -radius, radius)
	var s1: float = clampf(s0 + w, -radius, radius)
	if s1 - s0 < 0.5:
		return
	var l0: float = sqrt(maxf(radius * radius - s0 * s0, 0.0))
	var l1: float = sqrt(maxf(radius * radius - s1 * s1, 0.0))
	var band := PackedVector2Array([c + u * s0 + v * l0, c + u * s1 + v * l1, c + u * s1 - v * l1, c + u * s0 - v * l0])
	draw_colored_polygon(band, Color(1, 1, 1, 0.42 * sin(shine * PI)))
