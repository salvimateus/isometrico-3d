extends RefCounted

## Procedural cumulus layout: a flat-bottomed cluster of spheres, tallest in the middle.
## `generate()` returns {blobs: PackedVector4Array (xyz relative to box center, w radius),
## half_extents: Vector3, base_y: float, top_y: float, lift: float}, where `lift` is the
## box center height above the cloud base.

const CT := preload("res://scripts/clouds/cloud_tuning.gd")


static func generate(rng: RandomNumberGenerator, width: float, height_ratio: float) -> Dictionary:
	var height: float = width * height_ratio
	var depth: float = width * rng.randf_range(0.6, 0.85)
	var half_w: float = width * 0.5
	var raw: Array[Vector4] = []
	# Two staggered rows of base lobes give a broad, flat underside.
	var base_count: int = rng.randi_range(3, 4)
	for row: int in 2:
		var row_z: float = (0.2 if row == 0 else -0.2) * depth
		var count: int = base_count - row
		for i: int in count:
			var u: float = lerpf(-1.0, 1.0, (i + 0.5) / count) + rng.randf_range(-0.1, 0.1)
			var falloff: float = 1.0 - 0.45 * absf(u)
			var r: float = height * 0.62 * falloff * rng.randf_range(0.9, 1.1)
			var x: float = u * (half_w - r * 0.75)
			raw.append(Vector4(x, r * rng.randf_range(0.12, 0.25), row_z + rng.randf_range(-0.06, 0.06) * depth, r))
	var top_count: int = mini(rng.randi_range(2, 3), CT.MAX_BLOBS - raw.size())
	for i: int in top_count:
		var r: float = height * rng.randf_range(0.42, 0.55)
		var x: float = rng.randf_range(-0.25, 0.25) * width
		var lift: float = height * (1.0 - 0.55 * absf(x) / half_w) - r
		raw.append(Vector4(x, maxf(lift, r * 0.45), rng.randf_range(-0.12, 0.12) * depth, r))

	var yaw: float = rng.randf_range(0.0, TAU)
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var margin: float = CT.SOFTNESS * 1.4
	for i: int in raw.size():
		var b: Vector4 = raw[i]
		var p := Vector3(b.x, b.y, b.z).rotated(Vector3.UP, yaw)
		raw[i] = Vector4(p.x, p.y, p.z, b.w)
		lo = Vector3(minf(lo.x, p.x - b.w - margin), 0.0, minf(lo.z, p.z - b.w - margin))
		hi = Vector3(maxf(hi.x, p.x + b.w + margin), maxf(hi.y, p.y + b.w + margin), maxf(hi.z, p.z + b.w + margin))
	lo.y = -margin * 0.5
	var center: Vector3 = (lo + hi) * 0.5
	var blobs := PackedVector4Array()
	for b: Vector4 in raw:
		blobs.append(Vector4(b.x - center.x, b.y - center.y, b.z - center.z, b.w))
	return {
		"blobs": blobs,
		"half_extents": (hi - lo) * 0.5,
		"base_y": -center.y,
		"top_y": hi.y - margin - center.y,
		"lift": center.y,
	}
