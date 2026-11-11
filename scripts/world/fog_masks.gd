extends RefCounted

## Builds the obstacle and base-density masks for the FOG field from the island layout.
## Image column -> world X, row -> world Z, row 0 at area.position.y.

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const GroundData := preload("res://scripts/world/ground_data.gd")


static func _to_world(area: Rect2, res: Vector2i, x: int, y: int) -> Vector2:
	return area.position + Vector2((x + 0.5) / res.x * area.size.x, (y + 0.5) / res.y * area.size.y)


static func obstacles(area: Rect2, buildings: Array[Dictionary], trees: Array[Dictionary]) -> Image:
	var res := Vector2i(int(area.size.x * Tuning.FOG_MASK_PX_PER_UNIT), int(area.size.y * Tuning.FOG_MASK_PX_PER_UNIT))
	var img := Image.create(res.x, res.y, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	var px: float = Tuning.FOG_MASK_PX_PER_UNIT
	var rects: Array[Rect2] = []
	for b: Dictionary in buildings:
		if Layout.NON_SOLID_KINDS.has(b["kind"]):
			continue
		var fp: Vector2i = b["footprint"]
		var c: Vector3 = (b["slot"] as Node3D).position
		rects.append(Rect2(Vector2(c.x, c.z) - Vector2(fp) * 0.5 + Vector2(0.15, 0.15), Vector2(fp) - Vector2(0.3, 0.3)))
	for w: Vector2i in Layout.wall_cells():
		var c: Vector3 = Layout.footprint_center(w, Vector2i.ONE)
		rects.append(Rect2(Vector2(c.x, c.z) - Vector2(0.45, 0.45), Vector2(0.9, 0.9)))
	for r: Rect2 in rects:
		var p0: Vector2 = (r.position - area.position) * px
		var p1: Vector2 = (r.end - area.position) * px
		img.fill_rect(Rect2i(Vector2i(p0.floor()), Vector2i((p1 - p0).ceil())), Color.WHITE)
	# Ocean beyond the cliff is solid for the simulation, so fog never drifts off the island.
	for y: int in res.y:
		for x: int in res.x:
			if Shape.inside_margin(_to_world(area, res, x, y)) < 0.4:
				img.set_pixel(x, y, Color.WHITE)
	for t: Dictionary in trees:
		if t["kind"] != &"tree":
			continue
		var p: Vector2 = t["pos"]
		var radius: float = 0.22 * float(t["scale"])
		var center: Vector2 = (p - area.position) * px
		var rp: int = maxi(1, ceili(radius * px))
		for dy: int in range(-rp, rp + 1):
			for dx: int in range(-rp, rp + 1):
				var q := Vector2i(int(center.x) + dx, int(center.y) + dy)
				if q.x < 0 or q.y < 0 or q.x >= res.x or q.y >= res.y:
					continue
				if Vector2(dx, dy).length() <= rp:
					img.set_pixelv(q, Color.WHITE)
	return img


static func base_density(area: Rect2, ground: GroundData) -> Image:
	var res := Vector2i(int(area.size.x * Tuning.FOG_MASK_PX_PER_UNIT), int(area.size.y * Tuning.FOG_MASK_PX_PER_UNIT))
	var img := Image.create(res.x, res.y, false, Image.FORMAT_L8)
	for y: int in res.y:
		for x: int in res.x:
			var p: Vector2 = _to_world(area, res, x, y)
			var inside: float = clampf((Shape.inside_margin(p) - 0.6) / 1.4, 0.0, 1.0)
			var forest: float = clampf((Shape.playable_distance(p) + 0.5) / 2.5, 0.0, 1.0)
			var pond: float = 1.0 - clampf((Layout.pond_sdf(p) - 0.3) / 2.2, 0.0, 1.0)
			var d: float = lerpf(Tuning.FOG_DENSITY_VILLAGE, Tuning.FOG_DENSITY_WILD, maxf(forest, pond))
			if ground.dirt_at(p):
				d = minf(d, Tuning.FOG_DENSITY_PATH)
			var v: float = d * inside
			img.set_pixel(x, y, Color(v, v, v))
	return img
