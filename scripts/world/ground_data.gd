extends RefCounted

## Rasterizes the layout into a 1 px per tile data texture (R = worn ground, G = dirt path)
## and an occupancy grid used to keep scatter away from buildings and paths.

const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")

const ORIGIN: Vector2i = Vector2i(-20, -20)
const SIZE: int = 40

var image: Image
var texture: ImageTexture
var _blocked: Dictionary = {}


func build(footprint_of: Callable) -> void:
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	var offset := Vector2i(int(-Layout.HALF), int(-Layout.HALF)) - ORIGIN
	for e: Dictionary in Layout.entries():
		var cell: Vector2i = e["cell"]
		var fp: Vector2i = footprint_of.call(e["kind"])
		for x: int in fp.x:
			for z: int in fp.y:
				_write(cell + Vector2i(x, z) + offset, 0, 1.0)
				_blocked[cell + Vector2i(x, z)] = 2
	for w: Vector2i in Layout.wall_cells():
		_write(w + offset, 0, 0.75)
		_blocked[w] = 2
	for p: Vector2i in Layout.path_cells():
		_write(p + offset, 1, 1.0)
		if not _blocked.has(p):
			_blocked[p] = 1
	# B = pond mask, A = depression depth (0..1 over 0..0.3).
	for y: int in SIZE:
		for x: int in SIZE:
			var p := Vector2(ORIGIN.x + x + 0.5, ORIGIN.y + y + 0.5)
			var c: Color = image.get_pixel(x, y)
			c.b = 1.0 if Layout.pond_sdf(p) < 0.6 else 0.0
			image.set_pixel(x, y, c)
	texture = ImageTexture.create_from_image(image)


func _write(px: Vector2i, channel: int, value: float) -> void:
	if px.x < 0 or px.y < 0 or px.x >= SIZE or px.y >= SIZE:
		return
	var c: Color = image.get_pixelv(px)
	if channel == 0:
		c.r = maxf(c.r, value)
	else:
		c.g = maxf(c.g, value)
	image.set_pixelv(px, c)


## 0 free, 1 path, 2 building or wall. Takes a world-space point.
func blocked_at(p: Vector2, margin: float = 0.0) -> int:
	var worst: int = 0
	for dx: float in [-margin, 0.0, margin]:
		for dz: float in [-margin, 0.0, margin]:
			var cell := Vector2i(floori(p.x + dx + Layout.HALF), floori(p.y + dz + Layout.HALF))
			worst = maxi(worst, int(_blocked.get(cell, 0)))
	return worst


func data_rect() -> Vector4:
	return Vector4(ORIGIN.x, ORIGIN.y, SIZE, SIZE)


## True on dirt paths and worn ground, sampled bilinearly from the data image.
func dirt_at(p: Vector2) -> bool:
	var u: float = p.x - ORIGIN.x - 0.5
	var v: float = p.y - ORIGIN.y - 0.5
	var x0: int = clampi(floori(u), 0, SIZE - 2)
	var y0: int = clampi(floori(v), 0, SIZE - 2)
	var fx: float = clampf(u - x0, 0.0, 1.0)
	var fy: float = clampf(v - y0, 0.0, 1.0)
	var c: Color = image.get_pixel(x0, y0).lerp(image.get_pixel(x0 + 1, y0), fx).lerp(
		image.get_pixel(x0, y0 + 1).lerp(image.get_pixel(x0 + 1, y0 + 1), fx), fy)
	return c.r > 0.28 or c.g > 0.36
