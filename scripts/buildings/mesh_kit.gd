extends RefCounted
## Procedural mesh generators. Every generator caches by its parameters, so equal calls share one mesh.
## Boxes, cylinders and spheres are centered on the origin; cones, domes and roofs sit on y = 0.

const Tuning = preload("res://scripts/buildings/building_tuning.gd")

static var _cache: Dictionary = {}


class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, uv: Vector2 = Vector2.ZERO) -> int:
		verts.append(p)
		normals.append(n)
		uvs.append(uv)
		return verts.size() - 1

	## Winding is derived from the vertex normals (Godot front faces are clockwise).
	func tri(a: int, b: int, c: int) -> void:
		var cr: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if cr.length_squared() < 1e-14:
			return
		var outward: Vector3 = normals[a] + normals[b] + normals[c]
		if cr.dot(outward) > 0.0:
			indices.append_array(PackedInt32Array([a, c, b]))
		else:
			indices.append_array(PackedInt32Array([a, b, c]))

	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(a, c, d)

	## Flat polygon (convex, ordered) with one shared normal.
	func flat_face(points: PackedVector3Array, n: Vector3, face_uvs: PackedVector2Array = PackedVector2Array()) -> void:
		var base: int = verts.size()
		for i in points.size():
			add(points[i], n, face_uvs[i] if i < face_uvs.size() else Vector2(points[i].x, points[i].y))
		for i in range(1, points.size() - 1):
			tri(base, base + i, base + i + 1)

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Surface 0 = first builder, surface 1 = second, ... (lets roofs give their underside its own material).
static func _commit_surfaces(builders: Array[Builder]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for b: Builder in builders:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.normals
		arrays[Mesh.ARRAY_TEX_UV] = b.uvs
		arrays[Mesh.ARRAY_INDEX] = b.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Caps an explicit side count to the quality tier (mobile keeps small counts, trims dense ones).
static func _tier_sides(n: int) -> int:
	return mini(n, Tuning.CYLINDER_SIDES) if Tuning.MOBILE else n


static func _tier_rings(n: int) -> int:
	return mini(n, Tuning.SPHERE_RINGS) if Tuning.MOBILE else n


static func _remember(key: String, mesh: Mesh) -> Mesh:
	_cache[key] = mesh
	return mesh


static func _bevel_stops(half: float, inner: float, r: float, seg: int) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for k in range(seg, 0, -1):
		raw.append(-(inner + r * tan(PI * 0.25 * float(k) / seg)))
	raw.append(-inner)
	raw.append(inner)
	for k in range(1, seg + 1):
		raw.append(inner + r * tan(PI * 0.25 * float(k) / seg))
	var out := PackedFloat32Array()
	for v: float in raw:
		if out.is_empty() or absf(v - out[out.size() - 1]) > 1e-5:
			out.append(v)
	out[0] = -half
	out[out.size() - 1] = half
	return out


## Box with rounded edges (smooth normals across the bevel). `taper` shrinks the top in X/Z (0.1 = 10%).
static func rounded_box(size: Vector3, radius: float, taper: float = 0.0, segments: int = 0) -> ArrayMesh:
	var seg: int = segments if segments > 0 else Tuning.BEVEL_SEGMENTS
	var half: Vector3 = size * 0.5
	var r: float = clampf(radius, 0.0, minf(half.x, minf(half.y, half.z)))
	var key := "rbox|%.3f|%.3f|%.3f|%.3f|%.3f|%d" % [size.x, size.y, size.z, r, taper, seg]
	if _cache.has(key):
		return _cache[key]
	var inner: Vector3 = half - Vector3(r, r, r)
	var b := Builder.new()
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in 3:
		var ui: int = (ai + 1) % 3
		var vi: int = (ai + 2) % 3
		var us: PackedFloat32Array = _bevel_stops(half[ui], inner[ui], r, seg)
		var vs: PackedFloat32Array = _bevel_stops(half[vi], inner[vi], r, seg)
		for sgn: float in [1.0, -1.0]:
			var n: Vector3 = axes[ai] * sgn
			var base: int = b.verts.size()
			for j in vs.size():
				for i in us.size():
					var p: Vector3 = n * half[ai] + axes[ui] * us[i] + axes[vi] * vs[j]
					var c: Vector3 = p.clamp(-inner, inner)
					var d: Vector3 = p - c
					var nn: Vector3 = n if d.length_squared() < 1e-12 else d.normalized()
					var fp: Vector3 = c + nn * r
					if taper != 0.0:
						var t: float = (fp.y + half.y) / size.y
						var s: float = 1.0 - taper * t
						fp.x *= s
						fp.z *= s
						nn.y += (absf(nn.x) * half.x + absf(nn.z) * half.z) * taper / size.y
						nn = nn.normalized()
					b.add(fp, nn, Vector2(fp.dot(axes[ui]), fp.dot(axes[vi])))
			var row: int = us.size()
			for j in vs.size() - 1:
				for i in row - 1:
					var i0: int = base + j * row + i
					b.quad(i0, i0 + 1, i0 + 1 + row, i0 + row)
	return _remember(key, b.commit())


## Surface of revolution around Y. `points` go bottom to top as (radius, y); normals are derived and
## split at corners sharper than `crease_deg`.
static func lathe(points: PackedVector2Array, sides: int = 0, crease_deg: float = 50.0) -> ArrayMesh:
	var n_sides: int = _tier_sides(sides) if sides > 0 else Tuning.CYLINDER_SIDES
	var key := "lathe|%d|%.1f|%s" % [n_sides, crease_deg, str(points)]
	if _cache.has(key):
		return _cache[key]
	var seg_normals: Array[Vector2] = []
	for k in points.size() - 1:
		var d: Vector2 = points[k + 1] - points[k]
		seg_normals.append(Vector2(d.y, -d.x).normalized() if d.length_squared() > 1e-12 else Vector2.ZERO)
	# Expanded profile: each entry is (radius, y, normal_r, normal_y, length_along_profile).
	var prof: Array[PackedFloat32Array] = []
	var cos_crease: float = cos(deg_to_rad(crease_deg))
	var acc: float = 0.0
	for k in points.size():
		if k > 0:
			acc += points[k].distance_to(points[k - 1])
		var n_prev: Vector2 = seg_normals[k - 1] if k > 0 else Vector2.ZERO
		var n_next: Vector2 = seg_normals[k] if k < seg_normals.size() else Vector2.ZERO
		if n_prev == Vector2.ZERO:
			n_prev = n_next
		if n_next == Vector2.ZERO:
			n_next = n_prev
		if n_prev.dot(n_next) < cos_crease:
			prof.append(PackedFloat32Array([points[k].x, points[k].y, n_prev.x, n_prev.y, acc]))
			prof.append(PackedFloat32Array([points[k].x, points[k].y, n_next.x, n_next.y, acc]))
		else:
			var nn: Vector2 = (n_prev + n_next).normalized()
			prof.append(PackedFloat32Array([points[k].x, points[k].y, nn.x, nn.y, acc]))
	var max_r: float = 0.0
	for p: Vector2 in points:
		max_r = maxf(max_r, p.x)
	var b := Builder.new()
	var rows: int = prof.size()
	for s in n_sides + 1:
		var a: float = TAU * float(s) / n_sides
		var ca: float = cos(a)
		var sa: float = sin(a)
		for e: PackedFloat32Array in prof:
			b.add(Vector3(e[0] * ca, e[1], e[0] * sa), Vector3(e[2] * ca, e[3], e[2] * sa).normalized(), Vector2(a * max_r, e[4]))
	for s in n_sides:
		for k in rows - 1:
			var i0: int = s * rows + k
			var i1: int = (s + 1) * rows + k
			b.quad(i0, i1, i1 + 1, i0 + 1)
	return _remember(key, b.commit())


static func _arc(points: PackedVector2Array, center: Vector2, r: float, a0: float, a1: float, steps: int) -> void:
	for k in range(1, steps + 1):
		var a: float = lerpf(a0, a1, float(k) / steps)
		points.append(center + Vector2(cos(a), sin(a)) * r)


## Cylinder with rounded top/bottom rims. `radius_top` < 0 means same as `radius`.
static func cylinder(radius: float, height: float, bevel: float = 0.04, radius_top: float = -1.0, sides: int = 0) -> ArrayMesh:
	var rt: float = radius if radius_top < 0.0 else radius_top
	var h: float = height * 0.5
	var bv: float = clampf(bevel, 0.0, minf(minf(radius, rt), h) * 0.95)
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, -h))
	if bv > 0.001:
		var side_angle: float = atan2(radius - rt, height)
		pts.append(Vector2(radius - bv, -h))
		_arc(pts, Vector2(radius - bv, -h + bv), bv, -PI * 0.5, side_angle, Tuning.BEVEL_SEGMENTS + 1)
		pts.append(Vector2(rt - bv + bv * cos(side_angle), h - bv + bv * sin(side_angle)))
		_arc(pts, Vector2(rt - bv, h - bv), bv, side_angle, PI * 0.5, Tuning.BEVEL_SEGMENTS + 1)
	else:
		pts.append(Vector2(radius, -h))
		pts.append(Vector2(rt, h))
	pts.append(Vector2(0.0, h))
	return lathe(pts, sides, 50.0)


## Cone sitting on y = 0 with an optional rounded bottom rim.
static func cone(radius: float, height: float, sides: int = 0, bevel: float = 0.0) -> ArrayMesh:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, 0.0))
	if bevel > 0.001:
		pts.append(Vector2(radius - bevel, 0.0))
		_arc(pts, Vector2(radius - bevel, bevel), bevel, -PI * 0.5, atan2(radius, height), Tuning.BEVEL_SEGMENTS + 1)
	else:
		pts.append(Vector2(radius, 0.0))
	pts.append(Vector2(0.0, height))
	return lathe(pts, sides, 50.0)


## Half ellipsoid sitting on y = 0.
static func dome(radius: float, height: float, sides: int = 0, rings: int = 0) -> ArrayMesh:
	var n_rings: int = _tier_rings(rings) if rings > 0 else Tuning.SPHERE_RINGS >> 1
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, 0.0))
	for k in n_rings + 1:
		var a: float = PI * 0.5 * float(k) / n_rings
		pts.append(Vector2(cos(a) * radius, sin(a) * height))
	pts[pts.size() - 1] = Vector2(0.0, height)
	return lathe(pts, sides if sides > 0 else Tuning.SPHERE_SIDES, 50.0)


static func sphere(radius: float, sides: int = 0, rings: int = 0) -> ArrayMesh:
	var n_rings: int = _tier_rings(rings) if rings > 0 else Tuning.SPHERE_RINGS
	var pts := PackedVector2Array()
	for k in n_rings + 1:
		var a: float = lerpf(-PI * 0.5, PI * 0.5, float(k) / n_rings)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	pts[0] = Vector2(0.0, -radius)
	pts[pts.size() - 1] = Vector2(0.0, radius)
	return lathe(pts, sides if sides > 0 else Tuning.SPHERE_SIDES, 89.0)


## Ring lying in the XZ plane (tube around Y).
static func torus(ring_radius: float, tube_radius: float, sides: int = 0, tube_sides: int = 8) -> Mesh:
	var n: int = _tier_sides(sides) if sides > 0 else Tuning.CYLINDER_SIDES
	var key := "torus|%.3f|%.3f|%d|%d" % [ring_radius, tube_radius, n, tube_sides]
	if _cache.has(key):
		return _cache[key]
	var mesh := TorusMesh.new()
	mesh.inner_radius = ring_radius - tube_radius
	mesh.outer_radius = ring_radius + tube_radius
	mesh.rings = n
	mesh.ring_segments = tube_sides
	return _remember(key, mesh)


static func _slope_uv(p: Vector3, eave_point: Vector3, along: Vector3) -> Vector2:
	var rel: Vector3 = p - eave_point
	var u: float = rel.dot(along)
	var v: float = (rel - along * u).length()
	return Vector2(u, v)


## Solid hip roof on y = 0: footprint `width` (X) by `depth` (Z), ridge along Z of length `ridge`
## (0 = pyramid), vertical fascia of `fascia` height. UV is (along eave, up the slope) in units.
## Surface 0 = tiled slopes, surface 1 = fascia and underside.
static func hip_roof(width: float, depth: float, height: float, ridge: float, fascia: float = 0.12) -> ArrayMesh:
	var key := "hip|%.3f|%.3f|%.3f|%.3f|%.3f" % [width, depth, height, ridge, fascia]
	if _cache.has(key):
		return _cache[key]
	var w: float = width * 0.5
	var d: float = depth * 0.5
	var rz: float = clampf(ridge, 0.0, depth - 0.01) * 0.5
	var t: float = fascia
	var a := Vector3(-w, t, -d)
	var bb := Vector3(w, t, -d)
	var c := Vector3(w, t, d)
	var dd := Vector3(-w, t, d)
	var r1 := Vector3(0.0, t + height, -rz)
	var r2 := Vector3(0.0, t + height, rz)
	var b := Builder.new()
	var under := Builder.new()
	var slopes: Array = [
		[PackedVector3Array([bb, c, r2, r1]), bb, Vector3.BACK],
		[PackedVector3Array([dd, a, r1, r2]), a, Vector3.BACK],
		[PackedVector3Array([c, dd, r2]), dd, Vector3.RIGHT],
		[PackedVector3Array([a, bb, r1]), a, Vector3.RIGHT],
	]
	for s: Array in slopes:
		var pts: PackedVector3Array = s[0]
		var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
		if n.y < 0.0:
			n = -n
		var face_uvs := PackedVector2Array()
		for p: Vector3 in pts:
			face_uvs.append(_slope_uv(p, s[1], s[2]))
		b.flat_face(pts, n, face_uvs)
	_fascia_ring(under, w, d, t)
	return _remember(key, _commit_surfaces([b, under]))


static func _fascia_ring(b: Builder, w: float, d: float, t: float) -> void:
	var y0: float = 0.0
	var corners: Array[Vector2] = [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d)]
	for i in 4:
		var p0: Vector2 = corners[i]
		var p1: Vector2 = corners[(i + 1) % 4]
		var mid: Vector2 = (p0 + p1) * 0.5
		var n := Vector3(mid.x, 0.0, mid.y).normalized()
		n = Vector3(signf(n.x) if absf(mid.x) > absf(mid.y) else 0.0, 0.0, signf(n.z) if absf(mid.y) >= absf(mid.x) else 0.0)
		b.flat_face(PackedVector3Array([
			Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, t, p1.y), Vector3(p0.x, t, p0.y)
		]), n)
	b.flat_face(PackedVector3Array([
		Vector3(-w, y0, -d), Vector3(w, y0, -d), Vector3(w, y0, d), Vector3(-w, y0, d)
	]), Vector3.DOWN)


## Gable roof made of two thick slabs, ridge along Z, sitting on y = 0. Gable ends stay open so a
## `prism` wall can fill them. UV on the top faces is (along ridge, up the slope).
## Surface 0 = tiled slopes, surface 1 = underside, eave and end edges.
static func gable_roof(width: float, depth: float, height: float, thickness: float = 0.12) -> ArrayMesh:
	var key := "gable|%.3f|%.3f|%.3f|%.3f" % [width, depth, height, thickness]
	if _cache.has(key):
		return _cache[key]
	var w: float = width * 0.5
	var d: float = depth * 0.5
	var t: float = thickness
	var b := Builder.new()
	var under := Builder.new()
	for sx: float in [1.0, -1.0]:
		var eave_top := Vector3(w * sx, t, 0.0)
		var ridge_top := Vector3(0.0, t + height, 0.0)
		var eave_bot := Vector3(w * sx, 0.0, 0.0)
		var ridge_bot := Vector3(0.0, height, 0.0)
		var zf := Vector3(0.0, 0.0, d)
		var top_n: Vector3 = Vector3(height * sx, w, 0.0).normalized()
		var slope_len: float = eave_top.distance_to(ridge_top)
		b.flat_face(PackedVector3Array([eave_top - zf, eave_top + zf, ridge_top + zf, ridge_top - zf]), top_n,
			PackedVector2Array([Vector2(-d, 0.0), Vector2(d, 0.0), Vector2(d, slope_len), Vector2(-d, slope_len)]))
		under.flat_face(PackedVector3Array([eave_bot - zf, eave_bot + zf, ridge_bot + zf, ridge_bot - zf]), -top_n)
		under.flat_face(PackedVector3Array([eave_bot - zf, eave_bot + zf, eave_top + zf, eave_top - zf]), Vector3(sx, 0.0, 0.0))
		for sz: float in [1.0, -1.0]:
			var z := Vector3(0.0, 0.0, d * sz)
			under.flat_face(PackedVector3Array([eave_bot + z, eave_top + z, ridge_top + z, ridge_bot + z]), Vector3(0.0, 0.0, sz))
	return _remember(key, _commit_surfaces([b, under]))


## Triangular prism (gable wall): base `width` on y = 0, apex at `height`, extruded along Z.
static func prism(width: float, height: float, depth: float) -> ArrayMesh:
	var key := "prism|%.3f|%.3f|%.3f" % [width, height, depth]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector2Array([Vector2(-width * 0.5, 0.0), Vector2(width * 0.5, 0.0), Vector2(0.0, height)])
	return _remember(key, _extrude_build(pts, depth))


## Extrudes a 2D outline (XY plane) along Z, centered. Flat normals.
static func extrude(outline: PackedVector2Array, depth: float, key_hint: String = "") -> ArrayMesh:
	var key := "extrude|%s|%.3f|%s" % [key_hint, depth, str(outline) if key_hint.is_empty() else ""]
	if _cache.has(key):
		return _cache[key]
	return _remember(key, _extrude_build(outline, depth))


static func _extrude_build(outline: PackedVector2Array, depth: float) -> ArrayMesh:
	var b := Builder.new()
	var hz: float = depth * 0.5
	var area: float = 0.0
	for i in outline.size():
		var p0: Vector2 = outline[i]
		var p1: Vector2 = outline[(i + 1) % outline.size()]
		area += p0.x * p1.y - p1.x * p0.y
	var ccw: bool = area > 0.0
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for sz: float in [1.0, -1.0]:
		var base: int = b.verts.size()
		for p: Vector2 in outline:
			b.add(Vector3(p.x, p.y, hz * sz), Vector3(0.0, 0.0, sz), p)
		for k in range(0, tris.size(), 3):
			b.tri(base + tris[k], base + tris[k + 1], base + tris[k + 2])
	for i in outline.size():
		var p0: Vector2 = outline[i]
		var p1: Vector2 = outline[(i + 1) % outline.size()]
		var e: Vector2 = p1 - p0
		var n2: Vector2 = Vector2(e.y, -e.x).normalized()
		if not ccw:
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0.0)
		b.flat_face(PackedVector3Array([
			Vector3(p0.x, p0.y, -hz), Vector3(p1.x, p1.y, -hz), Vector3(p1.x, p1.y, hz), Vector3(p0.x, p0.y, hz)
		]), n, PackedVector2Array([Vector2(0, -hz), Vector2(e.length(), -hz), Vector2(e.length(), hz), Vector2(0, hz)]))
	return b.commit()


static func gear(teeth: int, radius: float, tooth_depth: float, depth: float) -> ArrayMesh:
	var key := "gear|%d|%.3f|%.3f|%.3f" % [teeth, radius, tooth_depth, depth]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector2Array()
	var steps: int = teeth * 4
	for i in steps:
		var a: float = TAU * float(i) / steps
		var r: float = radius if (i % 4) < 2 else radius - tooth_depth
		pts.append(Vector2(cos(a), sin(a)) * r)
	return _remember(key, _extrude_build(pts, depth))


## Heater shield outline, top edge at y = h/2, point at y = -h/2.
static func shield(width: float, height: float, depth: float) -> ArrayMesh:
	var key := "shield|%.3f|%.3f|%.3f" % [width, height, depth]
	if _cache.has(key):
		return _cache[key]
	var w: float = width * 0.5
	var h: float = height * 0.5
	var pts := PackedVector2Array([Vector2(-w, h), Vector2(w, h)])
	var steps: int = 8
	for k in range(1, steps + 1):
		var t: float = float(k) / steps
		pts.append(Vector2(w * cos(t * PI * 0.5), h * 0.3 - (h * 1.3) * sin(t * PI * 0.5)))
	for k in range(steps - 1, 0, -1):
		var t2: float = float(k) / steps
		pts.append(Vector2(-w * cos(t2 * PI * 0.5), h * 0.3 - (h * 1.3) * sin(t2 * PI * 0.5)))
	return _remember(key, _extrude_build(pts, depth))


## Rectangle with a semicircular top; bottom edge at y = 0.
static func arch(width: float, height: float, depth: float) -> ArrayMesh:
	var key := "arch|%.3f|%.3f|%.3f" % [width, height, depth]
	if _cache.has(key):
		return _cache[key]
	var w: float = width * 0.5
	var spring: float = maxf(height - w, 0.0)
	var pts := PackedVector2Array([Vector2(-w, 0.0), Vector2(w, 0.0)])
	var steps: int = 10
	for k in steps + 1:
		var a: float = PI * float(k) / steps
		pts.append(Vector2(cos(a) * w, spring + 0.001 + sin(a) * w))
	return _remember(key, _extrude_build(pts, depth))


## Subdivided quad in the XY plane facing +Z, x in [0, width], y in [-height/2, height/2]. UV.x = 0 at the pole.
static func grid_plane(width: float, height: float, sx: int, sy: int) -> ArrayMesh:
	var key := "grid|%.3f|%.3f|%d|%d" % [width, height, sx, sy]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	for j in sy + 1:
		for i in sx + 1:
			var u: float = float(i) / sx
			var v: float = float(j) / sy
			b.add(Vector3(u * width, (v - 0.5) * height, 0.0), Vector3.BACK, Vector2(u, 1.0 - v))
	for j in sy:
		for i in sx:
			var i0: int = j * (sx + 1) + i
			b.quad(i0, i0 + 1, i0 + sx + 2, i0 + sx + 1)
	return _remember(key, b.commit())


## Faceted crystal (double pyramid) sitting on y = 0.
static func crystal(radius: float, height: float, sides: int = 6) -> ArrayMesh:
	var pts := PackedVector2Array([Vector2(0.0, 0.0), Vector2(radius, height * 0.25), Vector2(radius * 0.85, height * 0.7), Vector2(0.0, height)])
	return lathe(pts, sides, 10.0)


## Low-poly boulder (~unit size, flattened base) with softened facets; `seed` varies the shape.
static func rock(seed_value: int, rings: int = 4, sides: int = 7) -> ArrayMesh:
	var key := "rock|%d|%d|%d" % [seed_value, rings, sides]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid: Array[PackedVector3Array] = []
	for r in rings + 1:
		var lat: float = lerpf(-PI * 0.5, PI * 0.5, float(r) / rings)
		var ring := PackedVector3Array()
		var twist: float = rng.randf() * 0.5
		for sd in sides:
			var lon: float = TAU * (float(sd) + twist) / sides
			var rad: float = 0.5 * rng.randf_range(0.8, 1.08)
			var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * rad
			p.y = maxf(p.y, -0.3)
			ring.append(p)
		grid.append(ring)
	var b := Builder.new()
	for r in rings:
		for sd in sides:
			var p00: Vector3 = grid[r][sd]
			var p01: Vector3 = grid[r][(sd + 1) % sides]
			var p10: Vector3 = grid[r + 1][sd]
			var p11: Vector3 = grid[r + 1][(sd + 1) % sides]
			for t: PackedVector3Array in [PackedVector3Array([p00, p10, p11]), PackedVector3Array([p00, p11, p01])]:
				var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
				if n.length_squared() < 1e-10:
					continue
				var centroid: Vector3 = (t[0] + t[1] + t[2]) / 3.0
				n = n.normalized()
				if n.dot(centroid) < 0.0:
					n = -n
				var base: int = b.verts.size()
				for v: Vector3 in t:
					b.add(v, (n * 0.72 + v.normalized() * 0.28).normalized(), Vector2(v.x + v.z, v.y))
				b.tri(base, base + 1, base + 2)
	return _remember(key, b.commit())

