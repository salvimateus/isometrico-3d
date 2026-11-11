extends RefCounted

## Terrain images for the LIQUID shallow-water field. x -> world X, y -> world Z, row 0 at area.position.y.

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")


static func _world(area: Rect2, res: int, x: int, y: int) -> Vector2:
	return area.position + Vector2((x + 0.5) / res * area.size.x, (y + 0.5) / res * area.size.y)


## Returns [height (FORMAT_RF), solid (L8), drain (L8)].
static func build(area: Rect2, buildings: Array[Dictionary]) -> Array[Image]:
	var res: int = Tuning.LIQUID_TERRAIN_RES
	var height := Image.create(res, res, false, Image.FORMAT_RF)
	var drain := Image.create(res, res, false, Image.FORMAT_L8)
	var solid := Image.create(res, res, false, Image.FORMAT_L8)
	solid.fill(Color.BLACK)
	for y: int in res:
		for x: int in res:
			var p: Vector2 = _world(area, res, x, y)
			var inside: bool = Shape.inside_margin(p) > 0.25
			var h: float = Shape.ground_height(p) if inside else Tuning.WATER_LEVEL
			if inside and Layout.pond_sdf(p) < 0.0:
				h = maxf(h, Shape.POND_WATER_Y)
			height.set_pixel(x, y, Color(h, 0, 0))
			drain.set_pixel(x, y, Color.BLACK if inside else Color.WHITE)
	var px: float = res / area.size.x
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
		solid.fill_rect(Rect2i(Vector2i(p0.floor()), Vector2i((p1 - p0).ceil())), Color.WHITE)
	return [height, solid, drain]
