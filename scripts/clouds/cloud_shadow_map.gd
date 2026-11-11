extends SubViewport

## Top-down cloud coverage map: one soft disc per blob, projected to y = 0 along the light.
## Red channel is coverage 0..1 over `world_rect` (x, z, width, depth). Feed it with `update_from()` every frame;
## it only re-renders every `refresh_interval` seconds.

const CT := preload("res://scripts/clouds/cloud_tuning.gd")

var world_rect := Rect2(-110.0, -110.0, 220.0, 220.0)
## Seconds between redraws; 0 redraws every frame. Cloud shadows drift slowly, so a few Hz is enough.
var refresh_interval: float = 0.0

var _since_refresh: float = INF

var _canvas := Node2D.new()
var _disc: GradientTexture2D
var _items: Array[Dictionary] = []
var _light := Vector3.UP


func _init() -> void:
	size = Vector2i(CT.SHADOW_MAP_SIZE, CT.SHADOW_MAP_SIZE)
	disable_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.75))
	_disc = GradientTexture2D.new()
	_disc.gradient = gradient
	_disc.fill = GradientTexture2D.FILL_RADIAL
	_disc.fill_from = Vector2(0.5, 0.5)
	_disc.fill_to = Vector2(1.0, 0.5)
	_disc.width = 64
	_disc.height = 64
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = additive
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


## `items`: [{position: Vector3, blobs: PackedVector4Array, fade: float}], `light`: unit vector toward the light.
func update_from(items: Array[Dictionary], light: Vector3, delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < refresh_interval:
		return
	_since_refresh = 0.0
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_items = items
	_light = light if light.y > 0.15 else Vector3(light.x, 0.15, light.z).normalized()
	_canvas.queue_redraw()


func get_rect_vector() -> Vector4:
	return Vector4(world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y)


func _on_draw() -> void:
	var px := Vector2(size) / world_rect.size
	var slide := Vector2(_light.x, _light.z) / _light.y
	for item: Dictionary in _items:
		var fade: float = item["fade"]
		if fade <= 0.01:
			continue
		var origin: Vector3 = item["position"]
		for b: Vector4 in item["blobs"] as PackedVector4Array:
			var p := Vector3(origin.x + b.x, origin.y + b.y, origin.z + b.z)
			var ground := Vector2(p.x, p.z) - slide * p.y
			var center := (ground - world_rect.position) * px
			var radius: Vector2 = px * b.w * CT.SHADOW_SOFTNESS
			_canvas.draw_texture_rect(_disc, Rect2(center - radius, radius * 2.0), false, Color(1.0, 1.0, 1.0, fade * 0.55))
