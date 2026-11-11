extends RefCounted

## Collapses a procedural rig's rigid parts into one mesh per animated node: every MeshInstance3D is baked
## into its nearest animated ancestor, and all StandardMaterial3D looks fold into one shared shader by
## encoding albedo, emission, roughness, metallic and rim per vertex (shaders/character/toy_paint).

const SHADER := preload("res://shaders/character/toy_paint.gdshader")

static var _material: ShaderMaterial


## animated: Node3D -> true for nodes whose transform/visibility changes at runtime (bake targets).
## keep: MeshInstance3D -> true for meshes left untouched (own shader, toggled or animated alone).
static func bake(root: Node3D, animated: Dictionary, keep: Dictionary) -> void:
	var groups: Dictionary = {}
	_collect(root, root, Transform3D.IDENTITY, animated, keep, groups)
	for key: Array in groups.keys():
		var target: Node3D = key[0]
		var shadow: int = key[1]
		var mesh: ArrayMesh = _merge(groups[key])
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Baked"
		mi.mesh = mesh
		mi.material_override = _shared_material()
		mi.cast_shadow = shadow as GeometryInstance3D.ShadowCastingSetting
		target.add_child(mi)
	for key: Array in groups.keys():
		for entry: Dictionary in groups[key]:
			# A baked mesh may already be gone with a baked parent mesh (e.g. a sole under a boot).
			var src: Variant = entry["node"]
			if is_instance_valid(src):
				var n := src as Node
				n.get_parent().remove_child(n)
				n.free()


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## Walks the tree; `xf` is the transform of `node` relative to `target` (its nearest animated ancestor).
static func _collect(node: Node, target: Node3D, xf: Transform3D, animated: Dictionary, keep: Dictionary, groups: Dictionary) -> void:
	for child: Node in node.get_children():
		if not child is Node3D:
			continue
		var c := child as Node3D
		if keep.has(c):
			continue
		if animated.has(c):
			_collect(c, c, Transform3D.IDENTITY, animated, keep, groups)
			continue
		var cxf: Transform3D = xf * c.transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).material_override is StandardMaterial3D:
			var mi := c as MeshInstance3D
			var key: Array = [target, int(mi.cast_shadow)]
			if not groups.has(key):
				groups[key] = []
			groups[key].append({"node": mi, "xf": cxf})
		_collect(c, target, cxf, animated, keep, groups)


static func _merge(entries: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for e: Dictionary in entries:
		var mi: MeshInstance3D = e["node"]
		var xf: Transform3D = e["xf"]
		var nbasis: Basis = xf.basis.inverse().transposed()
		var mat := mi.material_override as StandardMaterial3D
		var p: Dictionary = _params(mat)
		for s: int in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var sc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base: int = verts.size()
			var use_vc: bool = mat.vertex_color_use_as_albedo and sc.size() == sv.size()
			for i: int in sv.size():
				verts.append(xf * sv[i])
				normals.append((nbasis * (sn[i] if i < sn.size() else Vector3.UP)).normalized())
				var albedo: Color = p["albedo"]
				if use_vc:
					var vc: Color = sc[i]
					if mat.vertex_color_is_srgb:
						vc = vc.srgb_to_linear()
					albedo = Color(albedo.r * vc.r, albedo.g * vc.g, albedo.b * vc.b)
				colors.append(Color(albedo.r, albedo.g, albedo.b, p["glow"]))
				uv.append(p["uv"])
				uv2.append(p["uv2"])
			if si.is_empty():
				for i: int in sv.size():
					indices.append(base + i)
			else:
				for idx: int in si:
					indices.append(base + idx)
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _params(mat: StandardMaterial3D) -> Dictionary:
	var albedo: Color = mat.albedo_color.srgb_to_linear()
	var glow: float = 0.0
	var rough: float = mat.roughness
	var metal: float = mat.metallic
	var rim: float = mat.rim if mat.rim_enabled else 0.0
	if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		glow = 1.0
		rough = 1.0
		metal = 0.0
		rim = 0.0
	elif mat.emission_enabled:
		glow = mat.emission_energy_multiplier
		if mat.vertex_color_use_as_albedo:
			# Emission was a flat palette color; approximate with the vertex albedo.
			glow *= 1.0
	return {"albedo": albedo, "glow": glow, "uv": Vector2(rough, metal), "uv2": Vector2(rim, mat.rim_tint)}
