extends RefCounted

const Q := preload("res://scripts/character/char_quality.gd")

## Sculpted solids for chunky "painted toy" volumes: a rounded-rectangle (superellipse) section swept
## along a path, with beveled end caps, optional strand grooves and a top-to-bottom vertex color gradient.

## path: section centers. half_a/half_b: section half sizes per path point along `side` and `normal`,
## where side = tangent x ref_up and normal = side x tangent.
## opts: n (squareness, 2 = ellipse, ~4 = rounded box), segments, grooves (count), groove_depth (0..1),
## groove_width (0..1), groove_phase (radians), color_power (gradient curve), bevel (0..1 of the smaller half size; bevel_start/bevel_end override per end),
## top_color, bottom_color.
static func sweep(path: PackedVector3Array, half_a: PackedFloat32Array, half_b: PackedFloat32Array, ref_up: Vector3, opts: Dictionary = {}) -> ArrayMesh:
	var n_exp: float = opts.get("n", 3.5)
	var seg: int = maxi(8, int(round(float(opts.get("segments", 32)) * Q.mesh_detail())))
	var grooves: int = opts.get("grooves", 0)
	var groove_depth: float = opts.get("groove_depth", 0.0)
	var groove_width: float = opts.get("groove_width", 0.3)
	var groove_phase: float = opts.get("groove_phase", 0.0)
	var bevel: float = opts.get("bevel", 0.3)
	var bevels: Array[float] = [opts.get("bevel_start", bevel), opts.get("bevel_end", bevel)]
	var top_color: Color = opts.get("top_color", Color.WHITE)
	var bottom_color: Color = opts.get("bottom_color", Color.WHITE)
	var color_power: float = opts.get("color_power", 1.0)

	var profile := PackedVector2Array()
	for j: int in seg:
		var th: float = TAU * float(j) / float(seg)
		var c: float = cos(th)
		var s: float = sin(th)
		var p := Vector2(signf(c) * pow(absf(c), 2.0 / n_exp), signf(s) * pow(absf(s), 2.0 / n_exp))
		if grooves > 0 and groove_depth > 0.0:
			var w: float = absf(sin(th * float(grooves) * 0.5 + groove_phase))
			p *= 1.0 - groove_depth * (1.0 - smoothstep(0.0, groove_width, w))
		profile.append(p)

	# Ring frames, plus inset bevel rings at both ends.
	var count: int = path.size()
	var centers := PackedVector3Array()
	var sides := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedVector3Array()
	var sa := PackedFloat32Array()
	var sb := PackedFloat32Array()
	for i: int in count:
		var t: Vector3 = (path[mini(i + 1, count - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side: Vector3 = t.cross(ref_up)
		if side.length() < 1e-4:
			side = t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD)
		side = side.normalized()
		centers.append(path[i])
		sides.append(side)
		normals.append(side.cross(t).normalized())
		tangents.append(t)
		sa.append(half_a[i])
		sb.append(half_b[i])
	for end: int in 2:
		var bv: float = bevels[end]
		if bv > 0.0:
			var i: int = 0 if end == 0 else centers.size() - 1
			var d: float = minf(sa[i], sb[i]) * bv
			var dir: Vector3 = -tangents[i] if end == 0 else tangents[i]
			var k: float = 1.0 - bv * 0.55
			var idx: int = 0 if end == 0 else centers.size()
			centers.insert(idx, centers[i] + dir * d)
			sides.insert(idx, sides[i])
			normals.insert(idx, normals[i])
			tangents.insert(idx, tangents[i])
			sa.insert(idx, sa[i] * k)
			sb.insert(idx, sb[i] * k)

	var y_min: float = INF
	var y_max: float = -INF
	for cpos: Vector3 in centers:
		y_min = minf(y_min, cpos.y)
		y_max = maxf(y_max, cpos.y)
	var y_span: float = maxf(y_max - y_min, 1e-4)

	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var rings: int = centers.size()
	for i: int in rings:
		for j: int in seg:
			var p: Vector2 = profile[j]
			verts.append(centers[i] + sides[i] * p.x * sa[i] + normals[i] * p.y * sb[i])
	for v: Vector3 in verts:
		cols.append(top_color.lerp(bottom_color, pow(clampf((y_max - v.y) / y_span, 0.0, 1.0), color_power)))

	var indices := PackedInt32Array()
	for i: int in rings - 1:
		var mid: Vector3 = (centers[i] + centers[i + 1]) * 0.5
		for j: int in seg:
			var a: int = i * seg + j
			var b: int = i * seg + (j + 1) % seg
			var c2: int = (i + 1) * seg + j
			var d: int = (i + 1) * seg + (j + 1) % seg
			_tri(indices, verts, a, c2, b, mid)
			_tri(indices, verts, b, c2, d, mid)

	var vnormals := PackedVector3Array()
	vnormals.resize(verts.size())
	for k: int in range(0, indices.size(), 3):
		var fa: Vector3 = verts[indices[k]]
		var fn: Vector3 = -(verts[indices[k + 1]] - fa).cross(verts[indices[k + 2]] - fa)
		for m: int in 3:
			vnormals[indices[k + m]] += fn
	for k: int in vnormals.size():
		vnormals[k] = vnormals[k].normalized()

	# Flat caps with their own vertices.
	for end: int in 2:
		var ri: int = 0 if end == 0 else rings - 1
		var cn: Vector3 = -tangents[ri] if end == 0 else tangents[ri]
		var base: int = verts.size()
		verts.append(centers[ri])
		vnormals.append(cn)
		cols.append(bottom_color.lerp(top_color, (centers[ri].y - y_min) / y_span))
		for j: int in seg:
			verts.append(verts[ri * seg + j])
			vnormals.append(cn)
			cols.append(cols[ri * seg + j])
		for j: int in seg:
			_tri(indices, verts, base, base + 1 + j, base + 1 + (j + 1) % seg, centers[ri] - cn)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = vnormals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Vertical loft helper: rings stacked from top to bottom, sections facing `forward`.
static func loft_down(centers: PackedVector3Array, half_w: PackedFloat32Array, half_d: PackedFloat32Array, opts: Dictionary = {}) -> ArrayMesh:
	return sweep(centers, half_w, half_d, Vector3.BACK, opts)


## Godot treats clockwise triangles as front faces; orient each triangle to face away from `inside`.
static func _tri(indices: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, inside: Vector3) -> void:
	var va: Vector3 = verts[a]
	var n: Vector3 = (verts[b] - va).cross(verts[c] - va)
	var centroid: Vector3 = (va + verts[b] + verts[c]) / 3.0
	if n.dot(centroid - inside) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


## Hair/fur lock: a soft lens-section blade hanging along -Y from its root at the origin, hugging inward
## then turning its rounded tip slightly outward (+Z). Smooth normals with one subtle center crease on the
## outer face; color runs from `root_color` at the top to `tip_color` at the bottom (color_power > 1 keeps
## the tip color near the tip).
## curve/tip_curl: outward offsets as a fraction of length. sides: section segment count.
static func lock(length: float, root_width: float, thickness: float, curve: float, tip_curl: float, sides: int, root_color: Color, tip_color: Color, color_power: float = 1.0) -> ArrayMesh:
	var steps: int = 8
	var spine := PackedVector3Array()
	var ha := PackedFloat32Array()
	var hb := PackedFloat32Array()
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		var z: float = curve * length * (sin(PI * t) * 0.5 - t * 0.3) + tip_curl * length * t * t * t
		spine.append(Vector3(0.0, -length * t, z))
		var round_tip: float = sqrt(maxf(1.0 - pow(t, 2.6), 0.0))
		ha.append(maxf(root_width * round_tip * (1.0 + 0.12 * sin(PI * t)), root_width * 0.12))
		hb.append(maxf(thickness * round_tip, thickness * 0.15))
	return sweep(spine, ha, hb, Vector3.BACK, {
		"n": 2.3, "segments": sides, "grooves": 2, "groove_phase": PI * 0.5, "groove_depth": 0.22, "groove_width": 0.3,
		"bevel_start": 0.0, "bevel_end": 0.8, "top_color": root_color, "bottom_color": tip_color, "color_power": color_power,
	})


## Chunky extruded star in the XY plane (facing +Z), beveled by a smaller front face. Flat normals.
static func star(points: int, r_out: float, r_in: float, thickness: float) -> ArrayMesh:
	var outline := PackedVector2Array()
	for i: int in points * 2:
		var a: float = PI * float(i) / float(points) + PI * 0.5
		var r: float = r_out if i % 2 == 0 else r_in
		outline.append(Vector2(cos(a), sin(a)) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = outline.size()
	var hz: float = thickness * 0.5
	for face: int in 2:
		var z: float = hz if face == 0 else -hz
		var cz: float = z * 1.6
		for i: int in n:
			var a2: Vector2 = outline[i]
			var b2: Vector2 = outline[(i + 1) % n]
			var c := Vector3(0.0, 0.0, cz)
			var a := Vector3(a2.x, a2.y, z)
			var b := Vector3(b2.x, b2.y, z)
			var nrm: Vector3 = (b - a).cross(c - a).normalized()
			if (nrm.z > 0.0) != (face == 0):
				nrm = -nrm
				var tmp: Vector3 = a
				a = b
				b = tmp
			st.set_normal(nrm)
			st.add_vertex(a)
			st.set_normal(nrm)
			st.add_vertex(c)
			st.set_normal(nrm)
			st.add_vertex(b)
	for i: int in n:
		var a2: Vector2 = outline[i]
		var b2: Vector2 = outline[(i + 1) % n]
		var p0 := Vector3(a2.x, a2.y, hz)
		var p1 := Vector3(b2.x, b2.y, hz)
		var p2 := Vector3(b2.x, b2.y, -hz)
		var p3 := Vector3(a2.x, a2.y, -hz)
		var nrm := Vector3((a2 + b2).x, (a2 + b2).y, 0.0).normalized()
		for v: Vector3 in [p0, p2, p1, p0, p3, p2]:
			st.set_normal(nrm)
			st.add_vertex(v)
	st.index()
	return st.commit()
