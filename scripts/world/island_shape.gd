extends RefCounted

## Pure island geometry: outline radius, ground height, region masks. No rendering.

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")

const POND_DEPTH: float = 0.92
## Max upward ground ripple: the fog field assumes ground near y = 0.
const MAX_RISE: float = 0.08

static var _flat_grid: PackedFloat32Array = PackedFloat32Array()
const FLAT_ORIGIN: float = -20.0
const FLAT_STEP: float = 0.25
const FLAT_RES: int = 160
## Footprints stay flat within FLAT_GROW and blend into dips over FLAT_TRANSITION (1-tile corridors still dip).
const FLAT_GROW: float = 0.15
const FLAT_TRANSITION: float = 0.6
const POND_WATER_Y: float = -0.16


static func outline_radius(theta: float) -> float:
	var n: float = Tuning.ISLAND_SUPERELLIPSE_N
	var c: float = absf(cos(theta))
	var s: float = absf(sin(theta))
	var r: float = Tuning.ISLAND_HALF_SIZE / pow(pow(c, n) + pow(s, n), 1.0 / n)
	var wobble: float = 0.022 * sin(3.0 * theta + 1.3) + 0.016 * sin(7.0 * theta + 0.4) + 0.009 * sin(13.0 * theta + 2.1)
	return r * (1.0 + wobble)


static func outline_point(theta: float) -> Vector2:
	return Vector2(cos(theta), sin(theta)) * outline_radius(theta)


## Signed distance-ish: positive inside the island, in tiles, measured radially.
static func inside_margin(p: Vector2) -> float:
	return outline_radius(atan2(p.y, p.x)) - p.length()


static func playable_distance(p: Vector2) -> float:
	var q: Vector2 = Vector2(absf(p.x), absf(p.y)) - Vector2(Layout.HALF, Layout.HALF)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func ground_height(p: Vector2) -> float:
	var y: float = 0.0
	var pond: float = Layout.pond_sdf(p)
	if pond < 0.25:
		var t: float = clampf((0.25 - pond) / 1.6, 0.0, 1.0)
		y -= POND_DEPTH * t * t * (3.0 - 2.0 * t)
	var outside_play: float = clampf((playable_distance(p) - 1.2) / 2.5, 0.0, 1.0)
	var edge_fade: float = clampf((inside_margin(p) - 0.6) / 2.0, 0.0, 1.0)
	var bump: float = sin(p.x * 0.55 + 1.7) * cos(p.y * 0.48 - 0.6) * 0.5 + 0.5
	var dep: float = depression_depth(p)
	# No ripple inside ditches and dips, so they keep draining downhill.
	y += MAX_RISE * bump * outside_play * edge_fade * clampf(pond / 1.0, 0.0, 1.0) * clampf(1.0 - dep / 0.05, 0.0, 1.0)
	y -= dep * clampf((pond - 0.4) / 0.8, 0.0, 1.0)
	return y


## Depth (>= 0) of the shallow depressions and ditches at p, zero under footprints and walls.
static func depression_depth(p: Vector2) -> float:
	var d: float = 0.0
	for dep: Vector4 in Layout.DEPRESSIONS:
		var r: float = p.distance_to(Vector2(dep.x, dep.y))
		if r < dep.z:
			var t: float = 1.0 - r / dep.z
			d = maxf(d, dep.w * t * t * (3.0 - 2.0 * t))
	for ditch: Array in Layout.DITCHES:
		var a: Vector2 = ditch[0]
		var b: Vector2 = ditch[1]
		var ab: Vector2 = b - a
		var u: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var r: float = p.distance_to(a + ab * u)
		var radius: float = ditch[2]
		if r < radius:
			var t: float = 1.0 - r / radius
			d = maxf(d, lerpf(ditch[3], ditch[4], u) * t * t * (3.0 - 2.0 * t))
	if d <= 0.0:
		return 0.0
	return d * _flatness(p)


## 0 on building footprints, walls and the spawn tile, rising smoothly to 1 within ~1 unit.
static func _flatness(p: Vector2) -> float:
	if _flat_grid.is_empty():
		_build_flat_grid()
	var u: float = (p.x - FLAT_ORIGIN) / FLAT_STEP
	var v: float = (p.y - FLAT_ORIGIN) / FLAT_STEP
	var x0: int = clampi(floori(u), 0, FLAT_RES - 2)
	var y0: int = clampi(floori(v), 0, FLAT_RES - 2)
	var fx: float = clampf(u - x0, 0.0, 1.0)
	var fy: float = clampf(v - y0, 0.0, 1.0)
	var a: float = lerpf(_flat_grid[y0 * FLAT_RES + x0], _flat_grid[y0 * FLAT_RES + x0 + 1], fx)
	var b: float = lerpf(_flat_grid[(y0 + 1) * FLAT_RES + x0], _flat_grid[(y0 + 1) * FLAT_RES + x0 + 1], fx)
	return lerpf(a, b, fy)


static func _build_flat_grid() -> void:
	var rects: Array[Rect2] = []
	for e: Dictionary in Layout.entries():
		var fp: Vector2i = Layout.FALLBACK_FOOTPRINTS[e["kind"]]
		var c: Vector3 = Layout.footprint_center(e["cell"], fp)
		rects.append(Rect2(Vector2(c.x, c.z) - Vector2(fp) * 0.5, Vector2(fp)).grow(FLAT_GROW))
	var lo: float = Layout.WALL_MIN - Layout.HALF
	var hi: float = Layout.WALL_MAX + 1 - Layout.HALF
	rects.append(Rect2(lo, lo, hi - lo, 1.0).grow(FLAT_GROW))
	rects.append(Rect2(lo, hi - 1.0, hi - lo, 1.0).grow(FLAT_GROW))
	rects.append(Rect2(lo, lo, 1.0, hi - lo).grow(FLAT_GROW))
	rects.append(Rect2(hi - 1.0, lo, 1.0, hi - lo).grow(FLAT_GROW))
	rects.append(Rect2(-0.8, 2.0, 1.6, 1.0))
	_flat_grid.resize(FLAT_RES * FLAT_RES)
	for iy: int in FLAT_RES:
		for ix: int in FLAT_RES:
			var q := Vector2(FLAT_ORIGIN + ix * FLAT_STEP, FLAT_ORIGIN + iy * FLAT_STEP)
			var best: float = 99.0
			for r: Rect2 in rects:
				var dx: float = maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0)
				var dz: float = maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0)
				best = minf(best, Vector2(dx, dz).length())
			var t: float = clampf(best / FLAT_TRANSITION, 0.0, 1.0)
			_flat_grid[iy * FLAT_RES + ix] = t * t * (3.0 - 2.0 * t)
