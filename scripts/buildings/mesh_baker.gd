extends RefCounted
## Merges the static MeshInstance3D nodes under a root: every opaque palette material collapses into one
## mesh with the shared building_paint material (palette index in UV2.x); the rest, one mesh per material.
## Works on any tree, any number of times (an already baked tree can be baked again by a parent).

const Mat = preload("res://scripts/buildings/materials.gd")

const BAKED_NAME: String = "Baked"

## Subtrees with these names are part of external contracts (animated or queried by other systems).
const PRESERVED_NAMES: Array[StringName] = [
	&"TankPivot", &"PourPoint", &"FillSurface", &"ButtonCap", &"ArmPivot", &"Bucket", &"Seat",
	&"Winch", &"CountdownAnchor", &"Halo",
]

## Shader code that reads the instance position cannot be merged without changing its look.
const INSTANCE_DEPENDENT_TOKENS: Array[String] = ["NODE_POSITION_WORLD", "MODEL_MATRIX[3]"]

static var _shader_mergeable: Dictionary = {}


static func bake_static(root: Node3D) -> void:
	var groups: Dictionary = {}
	var order: Array = []
	var consumed: Array[MeshInstance3D] = []
	var nested: Array[Node3D] = []
	_collect(root, root, Transform3D.IDENTITY, groups, order, consumed, nested)
	# Preserved subtrees (animated or contract nodes) get their own local bake, so they still move as one.
	for sub: Node3D in nested:
		bake_static(sub)
	if consumed.is_empty():
		return
	var baked := Node3D.new()
	baked.name = BAKED_NAME
	root.add_child(baked)
	for key: String in order:
		var g: Dictionary = groups[key]
		var mesh: ArrayMesh
		if g.has("tool"):
			mesh = (g["tool"] as SurfaceTool).commit()
		else:
			mesh = _commit_paint(g)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = g["material"]
		mi.cast_shadow = g["shadow"]
		baked.add_child(mi)
	for mi: MeshInstance3D in consumed:
		if mi.get_child_count() > 0:
			mi.mesh = null
		else:
			mi.get_parent().remove_child(mi)
			mi.free()
	_prune_empty(root, root)


static func _collect(node: Node, root: Node3D, xform: Transform3D, groups: Dictionary, order: Array, consumed: Array[MeshInstance3D], nested: Array[Node3D]) -> void:
	for child: Node in node.get_children():
		if not _descend(child):
			if _bakes_inside(child):
				nested.append(child as Node3D)
			continue
		var t: Transform3D = xform
		if child is Node3D:
			t = xform * (child as Node3D).transform
		if child is MeshInstance3D and _mergeable(child as MeshInstance3D):
			_append(child as MeshInstance3D, t, groups, order)
			consumed.append(child as MeshInstance3D)
		_collect(child, root, t, groups, order, consumed, nested)


## A preserved Node3D subtree whose own children can still be merged locally.
static func _bakes_inside(node: Node) -> bool:
	if not (node is Node3D) or node is MeshInstance3D:
		return false
	if node is GPUParticles3D or node is CPUParticles3D or node is Light3D or node is Label3D:
		return false
	return node.get_child_count() > 0 and (node as Node3D).visible


static func _descend(node: Node) -> bool:
	if node.get_script() != null:
		return false
	if PRESERVED_NAMES.has(StringName(node.name)):
		return false
	if node is GPUParticles3D or node is CPUParticles3D or node is Light3D or node is Label3D:
		return false
	if node is Node3D and not (node as Node3D).visible:
		return false
	return node is Node3D


static func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.material_overlay != null:
		return false
	for s in mi.mesh.get_surface_count():
		var mat: Material = mi.get_active_material(s)
		if mat == null or not _material_mergeable(mat):
			return false
	return true


static func _material_mergeable(mat: Material) -> bool:
	var sm := mat as ShaderMaterial
	if sm == null or sm.shader == null:
		return true
	var id: int = sm.shader.get_instance_id()
	if not _shader_mergeable.has(id):
		var code: String = sm.shader.code
		var ok: bool = true
		for token: String in INSTANCE_DEPENDENT_TOKENS:
			if code.contains(token):
				ok = false
		_shader_mergeable[id] = ok
	return _shader_mergeable[id]


static func _append(mi: MeshInstance3D, xform: Transform3D, groups: Dictionary, order: Array) -> void:
	for s in mi.mesh.get_surface_count():
		var mat: Material = mi.get_active_material(s)
		var paint: Material = Mat.paint()
		var index: int = Mat.paint_index(mat)
		if index >= 0 or mat == paint:
			var pkey := "paint|%d" % mi.cast_shadow
			if not groups.has(pkey):
				groups[pkey] = {
					"material": paint, "shadow": mi.cast_shadow,
					"verts": PackedVector3Array(), "normals": PackedVector3Array(),
					"uvs": PackedVector2Array(), "uv2s": PackedVector2Array(), "indices": PackedInt32Array(),
				}
				order.append(pkey)
			_append_paint(groups[pkey], mi.mesh, s, xform, index)
			continue
		var key := "%d|%d" % [mat.get_instance_id(), mi.cast_shadow]
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = {"tool": st, "material": mat, "shadow": mi.cast_shadow}
			order.append(key)
		(groups[key]["tool"] as SurfaceTool).append_from(mi.mesh, s, xform)


## Appends one surface, transformed into the bake root, tagging every vertex with its palette index
## (index < 0 means the surface is already painted and keeps its own UV2).
static func _append_paint(g: Dictionary, mesh: Mesh, surface: int, xform: Transform3D, index: int) -> void:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count: int = verts.size()
	if count == 0:
		return
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if uvs.size() != count:
		uvs.resize(count)
	var uv2s: PackedVector2Array
	if index < 0 and arrays[Mesh.ARRAY_TEX_UV2] != null:
		uv2s = arrays[Mesh.ARRAY_TEX_UV2]
	else:
		uv2s = PackedVector2Array()
		uv2s.resize(count)
		uv2s.fill(Vector2(float(index), 0.0))
	var basis: Basis = xform.basis
	var nbasis: Basis = basis.inverse().transposed()
	var tn: PackedVector3Array = Transform3D(nbasis, Vector3.ZERO) * normals
	var sc: Vector3 = basis.get_scale()
	if absf(sc.x - sc.y) > 1e-4 or absf(sc.y - sc.z) > 1e-4:
		for k in tn.size():
			tn[k] = tn[k].normalized()
	# Packed arrays are copy-on-write values: read, extend, write back.
	var acc_v: PackedVector3Array = g["verts"]
	var base: int = acc_v.size()
	acc_v.append_array(xform * verts)
	g["verts"] = acc_v
	var acc_n: PackedVector3Array = g["normals"]
	acc_n.append_array(tn)
	g["normals"] = acc_n
	var acc_uv: PackedVector2Array = g["uvs"]
	acc_uv.append_array(uvs)
	g["uvs"] = acc_uv
	var acc_uv2: PackedVector2Array = g["uv2s"]
	acc_uv2.append_array(uv2s)
	g["uv2s"] = acc_uv2
	var idx: PackedInt32Array
	if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		idx = arrays[Mesh.ARRAY_INDEX]
	else:
		idx = PackedInt32Array()
		idx.resize(count)
		for k in count:
			idx[k] = k
	if base > 0:
		for k in idx.size():
			idx[k] += base
	var acc_i: PackedInt32Array = g["indices"]
	acc_i.append_array(idx)
	g["indices"] = acc_i


static func _commit_paint(g: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g["verts"]
	arrays[Mesh.ARRAY_NORMAL] = g["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
	arrays[Mesh.ARRAY_TEX_UV2] = g["uv2s"]
	arrays[Mesh.ARRAY_INDEX] = g["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Drops plain Node3D pivots left without children (keeps contract names, scripts and the root).
static func _prune_empty(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		_prune_empty(child, root)
	if node == root or node.get_class() != "Node3D" or node.get_script() != null:
		return
	if PRESERVED_NAMES.has(StringName(node.name)) or node.name == BAKED_NAME:
		return
	if node.get_child_count() == 0:
		node.get_parent().remove_child(node)
		node.free()
