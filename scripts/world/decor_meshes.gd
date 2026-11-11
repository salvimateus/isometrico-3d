extends RefCounted

## Procedural meshes for nature props. Each function returns a fresh ArrayMesh with vertex colors.

const Kit := preload("res://scripts/world/mesh_kit.gd")
const Quality := preload("res://scripts/quality.gd")

const C_FOLIAGE := Color("3FA34D")
const C_FOLIAGE_DARK := Color("2F8C3E")
const C_FOLIAGE_LIGHT := Color("7AD058")
const C_TRUNK := Color("8A5A33")
const C_TRUNK_DARK := Color("6A4224")
const C_ROCK := Color("ACA394")
const C_ROCK_DARK := Color("6F685E")


static func _t(pos: Vector3, scale: Vector3 = Vector3.ONE, rot_y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y).scaled(scale), pos)


## Pine silhouettes: 0 tall slender, 1 tall slender with an extra tier, 2 full and short, 3 young.
const PINE_VARIANTS: int = 4
const _PINE_SPECS: Array = [
	# tiers, foliage_bottom, foliage_top, base_radius, top_radius, trunk_top, seed
	[5, 0.72, 2.8, 0.92, 0.36, 1.05, 11],
	[6, 0.7, 3.05, 0.9, 0.32, 1.05, 23],
	[4, 0.46, 2.2, 1.12, 0.46, 0.8, 37],
	[3, 0.3, 1.4, 0.74, 0.34, 0.5, 51],
]


static func pine_height(variant: int) -> float:
	return _PINE_SPECS[variant][2] + 0.25


static func pine_variant(variant: int) -> ArrayMesh:
	var spec: Array = _PINE_SPECS[variant]
	var tiers: int = spec[0]
	var y_bottom: float = spec[1]
	var y_top: float = spec[2]
	var r_base: float = spec[3]
	var r_top: float = spec[4]
	var rng := RandomNumberGenerator.new()
	rng.seed = spec[6]
	var lathe := _Lathe.new()
	var trunk_top: float = spec[5]
	var trunk_r: float = 0.09 + r_base * 0.04
	lathe.add_trunk(trunk_r, trunk_top, C_TRUNK_DARK, C_TRUNK)
	var span: float = (y_top - y_bottom) / (tiers + 0.35)
	var angle: float = rng.randf() * TAU
	for i: int in tiers:
		var f: float = float(i) / maxf(tiers - 1, 1)
		var rim_y: float = y_bottom + span * i
		var radius: float = lerpf(r_base, r_top, pow(f, 0.85)) * rng.randf_range(0.94, 1.06)
		var height: float = span * (1.55 if i == tiers - 1 else lerpf(1.75, 1.9, f))
		var lobes: int = int(round(lerpf(9.0, 6.0, f))) + rng.randi_range(-1, 0)
		var offset := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.05
		angle += 2.39996 + rng.randf_range(-0.3, 0.3)
		var bend := Vector2.ZERO
		if i == tiers - 1:
			bend = Vector2(cos(angle), sin(angle)) * height * 0.12
		lathe.add_skirt(Vector3(offset.x, rim_y, offset.y), radius, height, lobes, angle, f, bend)
	return lathe.commit()


## Builds lathed, smooth-shaded pine geometry straight into mesh arrays (colors stored linear).
class _Lathe extends RefCounted:
	const C_TOP_INNER_LOW := Color("185429")
	const C_TOP_INNER_HIGH := Color("2F8C3E")
	const C_RIM_LOW := Color("3FA34D")
	const C_RIM_HIGH := Color("7AD058")
	const C_UNDER := Color("17502A")

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Adds a ring grid: `rows` profile rows of `segs` columns each (wrapping around), with smooth normals.
	## `outward` picks the facing: normals end up agreeing with radial*outward.x + up*outward.y.
	func _grid(pts: PackedVector3Array, cols: PackedColorArray, rows: int, segs: int, center: Vector3, outward: Vector2) -> void:
		var base: int = verts.size()
		var acc := PackedVector3Array()
		acc.resize(pts.size())
		var tris := PackedInt32Array()
		var agree: float = 0.0
		for r: int in rows - 1:
			for s: int in segs:
				var a: int = r * segs + s
				var b: int = r * segs + (s + 1) % segs
				var c: int = (r + 1) * segs + s
				var d: int = (r + 1) * segs + (s + 1) % segs
				tris.append_array([a, b, c, b, d, c])
		for t: int in range(0, tris.size(), 3):
			var p0: Vector3 = pts[tris[t]]
			var p1: Vector3 = pts[tris[t + 1]]
			var p2: Vector3 = pts[tris[t + 2]]
			var n: Vector3 = (p1 - p0).cross(p2 - p0)
			var mid: Vector3 = (p0 + p1 + p2) / 3.0 - center
			var radial := Vector3(mid.x, 0, mid.z).normalized()
			agree += n.dot(radial * outward.x + Vector3.UP * outward.y)
		var flip: bool = agree < 0.0
		for t: int in range(0, tris.size(), 3):
			var p0: Vector3 = pts[tris[t]]
			var p1: Vector3 = pts[tris[t + 1]]
			var p2: Vector3 = pts[tris[t + 2]]
			var n: Vector3 = (p1 - p0).cross(p2 - p0) * (-1.0 if flip else 1.0)
			for k: int in 3:
				acc[tris[t + k]] += n
			# Godot front faces wind clockwise, i.e. opposite to the right-hand normal.
			if flip:
				indices.append_array([base + tris[t], base + tris[t + 1], base + tris[t + 2]])
			else:
				indices.append_array([base + tris[t], base + tris[t + 2], base + tris[t + 1]])
		for i: int in pts.size():
			verts.append(pts[i])
			var n: Vector3 = acc[i]
			if n.length_squared() < 1e-10:
				n = Vector3.UP
			normals.append(n.normalized())
			colors.append(cols[i].srgb_to_linear())

	func add_trunk(radius: float, top: float, bottom_c: Color, top_c: Color) -> void:
		var segs: int = 9
		var profile: Array = [[radius * 1.7, -0.05], [radius * 1.25, 0.12], [radius, 0.32], [radius * 0.6, top]]
		var pts := PackedVector3Array()
		var cols := PackedColorArray()
		for row: Array in profile:
			var r: float = row[0]
			var y: float = row[1]
			for s: int in segs:
				var a: float = TAU * s / segs
				pts.append(Vector3(cos(a) * r, y, sin(a) * r))
				cols.append(bottom_c.lerp(top_c, clampf(y / 0.5, 0.0, 1.0)))
		_grid(pts, cols, profile.size(), segs, Vector3(0, 0.5, 0), Vector2(1, 0))

	## One curved skirt tier: concave top flaring into a drooping, pointed rim, plus a dark underside.
	## `f` is the tier's height fraction (0 bottom, 1 top), driving the color ramp.
	func add_skirt(rim_center: Vector3, radius: float, height: float, lobes: int, rot: float, f: float, bend: Vector2) -> void:
		var lite: bool = Quality.is_mobile()
		var segs: int = lobes * (2 if lite else 4)
		var rows: int = 5 if lite else 8
		var apex_y: float = rim_center.y + height
		var droop: float = height * 0.16
		var inner_c: Color = C_TOP_INNER_LOW.lerp(C_TOP_INNER_HIGH, f)
		var rim_c: Color = C_RIM_LOW.lerp(C_RIM_HIGH, 0.25 + 0.75 * f)
		var pts := PackedVector3Array()
		var cols := PackedColorArray()
		var rim := PackedVector3Array()
		for r: int in rows:
			var t: float = float(r) / (rows - 1)
			for s: int in segs:
				var a: float = TAU * s / segs + rot
				var tri: float = 1.0 - absf(fmod(float(s) / 4.0, 1.0) * 2.0 - 1.0)
				var lobe: float = 1.0 - tri
				var edge: float = radius * (0.8 + 0.2 * lobe)
				var rr: float = lerpf(radius * 0.04, edge, t)
				var y: float = apex_y - height * (1.0 - pow(1.0 - t, 1.9))
				y -= droop * pow(smoothstep(0.55, 1.0, t), 2.0) * (0.55 + 0.45 * lobe)
				var off: Vector2 = bend * pow(1.0 - t, 2.0)
				var p := Vector3(rim_center.x + off.x + cos(a) * rr, y, rim_center.z + off.y + sin(a) * rr)
				pts.append(p)
				var c: Color = inner_c.lerp(rim_c, pow(t, 0.8))
				cols.append(c.lerp(C_RIM_HIGH, lobe * t * t * 0.35 * (0.4 + 0.6 * f)))
				if r == rows - 1:
					rim.append(p)
		_grid(pts, cols, rows, segs, rim_center, Vector2(0.35, 1))
		var under := PackedVector3Array()
		var ucols := PackedColorArray()
		var inner_r: float = radius * 0.18
		var inner_y: float = rim_center.y + height * 0.32
		for r: int in 3:
			var t: float = float(r) / 2.0
			for s: int in segs:
				var a: float = TAU * s / segs + rot
				var p: Vector3 = rim[s]
				var q := Vector3(rim_center.x + cos(a) * inner_r, inner_y, rim_center.z + sin(a) * inner_r)
				var m: Vector3 = p.lerp(q, t)
				m.y -= sin(t * PI) * height * 0.05
				under.append(m)
				ucols.append(rim_c.lerp(C_UNDER, minf(t * 2.0, 1.0) * 0.85).darkened(0.12))
		_grid(under, ucols, 3, segs, rim_center, Vector2(0.3, -1))

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func bush() -> ArrayMesh:
	var kit := Kit.new()
	var blobs: Array = [
		[Vector3(0, 0.3, 0), 0.42],
		[Vector3(0.36, 0.22, 0.1), 0.3],
		[Vector3(-0.32, 0.22, -0.08), 0.32],
		[Vector3(0.05, 0.24, 0.32), 0.28],
	]
	for i: int in blobs.size():
		var b: Array = blobs[i]
		kit.add(Kit.sphere(b[1], 12, 7), _t(b[0], Vector3(1, 0.85, 1)), C_FOLIAGE_DARK, C_FOLIAGE_LIGHT, 0.02, i + 3)
	return kit.commit()


static func rock(variant: int) -> ArrayMesh:
	var kit := Kit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var count: int = 1 + variant % 3
	for i: int in count:
		var r: float = rng.randf_range(0.28, 0.5) * (1.0 if i == 0 else 0.6)
		var off := Vector3(rng.randf_range(-0.35, 0.35), r * 0.45, rng.randf_range(-0.35, 0.35)) if i > 0 else Vector3(0, r * 0.5, 0)
		kit.add(Kit.sphere(r, 7, 4), _t(off, Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.6, 0.85), 1.0), rng.randf() * TAU), C_ROCK_DARK, C_ROCK, r * 0.12, variant * 7 + i)
	return kit.commit()


static func flower() -> ArrayMesh:
	var kit := Kit.new()
	kit.add(Kit.cylinder(0.008, 0.012, 0.16, 4), _t(Vector3(0, 0.08, 0)), Color("4E9A34"), Color("5FA834"))
	for i: int in 5:
		var a: float = TAU * i / 5.0
		kit.add(Kit.sphere(0.045, 6, 3), _t(Vector3(cos(a) * 0.05, 0.17, sin(a) * 0.05), Vector3(1.2, 0.45, 1.2)), Color(0.92, 0.92, 0.92), Color.WHITE)
	kit.add(Kit.sphere(0.035, 6, 3), _t(Vector3(0, 0.185, 0)), Color("FFC93C"), Color("FFD86A"))
	return kit.commit()


static func mushroom() -> ArrayMesh:
	var kit := Kit.new()
	kit.add(Kit.cylinder(0.045, 0.06, 0.16, 8), _t(Vector3(0, 0.08, 0)), Color("E9DCC0"), Color("F7EEDB"))
	kit.add(Kit.sphere(0.13, 12, 5, true), _t(Vector3(0, 0.15, 0), Vector3(1, 0.85, 1)), Color("A8321F"), Color("E2533A"))
	for i: int in 4:
		var a: float = TAU * i / 4.0 + 0.4
		kit.add(Kit.sphere(0.022, 6, 3), _t(Vector3(cos(a) * 0.075, 0.235, sin(a) * 0.075)), Color.WHITE, Color.WHITE)
	kit.add(Kit.sphere(0.024, 6, 3), _t(Vector3(0, 0.262, 0)), Color.WHITE, Color.WHITE)
	return kit.commit()


static func grass_tuft() -> ArrayMesh:
	var kit := Kit.new()
	var base_c := Color("4C9A2C")
	var tip_c := Color("A7E063")
	var blades: int = 6
	for i: int in blades:
		var a: float = TAU * i / blades + 0.3 * sin(i * 2.7)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h: float = 0.26 + 0.12 * fmod(i * 0.618, 1.0)
		var root: Vector3 = dir * 0.03
		var tip: Vector3 = dir * (0.1 + 0.04 * (i % 2)) + Vector3(0, h, 0)
		kit.add_triangle(root - side * 0.035, tip, root + side * 0.035, base_c, tip_c, base_c, Vector3(dir.x * 0.3, 1, dir.z * 0.3).normalized())
	return kit.commit()


static func lily_pad() -> ArrayMesh:
	var kit := Kit.new()
	kit.add(Kit.cylinder(0.32, 0.32, 0.02, 12), _t(Vector3(0, 0.01, 0)), Color("3F9A3E"), Color("5DBB4C"))
	return kit.commit()


static func reed() -> ArrayMesh:
	var kit := Kit.new()
	for i: int in 5:
		var a: float = TAU * i / 5.0
		var h: float = 0.55 + 0.2 * fmod(i * 0.37, 1.0)
		kit.add(Kit.cylinder(0.006, 0.018, h, 4), Transform3D(Basis(Vector3(sin(a), 0, -cos(a)), 0.12), Vector3(cos(a) * 0.06, h * 0.5, sin(a) * 0.06)), Color("4C8F2E"), Color("8CC85A"))
		if i % 2 == 0:
			kit.add(Kit.cylinder(0.03, 0.03, 0.14, 6), _t(Vector3(cos(a) * 0.06 + sin(a) * 0.06 * 0.1, h - 0.05, sin(a) * 0.06)), Color("6A4224"), Color("8A5A33"))
	return kit.commit()
