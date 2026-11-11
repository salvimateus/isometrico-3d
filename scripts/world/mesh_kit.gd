extends RefCounted

## Accumulates transformed primitive meshes with vertex colors into one ArrayMesh.
## Colors are given in sRGB and stored linear, so shaders can use COLOR directly.

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


## Appends `mesh` transformed by `xform`, colored by a vertical gradient over its own height.
## `jitter` displaces vertices along their normal by smooth noise for organic lumps.
func add(mesh: PrimitiveMesh, xform: Transform3D, bottom: Color, top: Color, jitter: float = 0.0, seed: int = 0) -> void:
	var arrays: Array = mesh.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ymin: float = INF
	var ymax: float = -INF
	for p: Vector3 in v:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var span: float = maxf(ymax - ymin, 0.0001)
	var base: int = _verts.size()
	var basis_n: Basis = xform.basis.inverse().transposed()
	for i: int in v.size():
		var p: Vector3 = v[i]
		if jitter > 0.0:
			var k: float = sin(p.x * 7.1 + seed) * cos(p.z * 6.3 - seed * 0.7) + sin(p.y * 5.3 + seed * 1.9) * 0.6
			p += n[i] * k * jitter
		_verts.append(xform * p)
		_normals.append((basis_n * n[i]).normalized())
		_colors.append(bottom.lerp(top, clampf((v[i].y - ymin) / span, 0.0, 1.0)).srgb_to_linear())
	for i: int in idx:
		_indices.append(base + i)


## Raw triangle with explicit colors per vertex and a shared normal.
func add_triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, normal: Vector3) -> void:
	var base: int = _verts.size()
	_verts.append_array([a, b, c])
	_normals.append_array([normal, normal, normal])
	_colors.append_array([ca.srgb_to_linear(), cb.srgb_to_linear(), cc.srgb_to_linear()])
	_indices.append_array([base, base + 1, base + 2])


func commit(smooth_jittered: bool = false) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if smooth_jittered:
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_normals()
		return st.commit()
	return mesh


static func sphere(radius: float, segments: int = 14, rings: int = 8, hemisphere: bool = false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemisphere else 2.0)
	m.radial_segments = segments
	m.rings = rings
	m.is_hemisphere = hemisphere
	return m


static func cylinder(top_r: float, bottom_r: float, height: float, segments: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
