extends RefCounted

## Builds island meshes (ground top, cliff skirt, seabed) from IslandShape.

const Tuning := preload("res://scripts/tuning.gd")
const Shape := preload("res://scripts/world/island_shape.gd")

const C_GRASS := Color("7CC243")
const C_GRASS_DARK := Color("5FA834")
const C_DIRT := Color("B98A52")
const C_DIRT_LIGHT := Color("D3A266")
const C_DIRT_DARK := Color("8A5A33")
const C_ROCK := Color("A39684")
const C_ROCK_DARK := Color("7A6F62")
const C_ROCK_DEEP := Color("4A5560")
const C_SEABED := Color("2B8FA6")
const C_SAND := Color("E3D3A0")

# offset outward from the outline, height, color
const PROFILE: Array = [
	[-0.15, 0.0, C_GRASS],
	[0.16, -0.035, C_GRASS],
	[0.33, -0.14, C_GRASS],
	[0.43, -0.28, C_GRASS_DARK],
	[0.47, -0.36, C_DIRT_LIGHT],
	[0.55, -0.6, C_DIRT],
	[0.56, -0.88, C_DIRT],
	[0.52, -1.12, C_DIRT_DARK],
	[0.47, -1.22, C_DIRT_DARK],
	[0.64, -1.3, C_ROCK],
	[0.7, -1.42, C_ROCK],
	[0.66, -1.72, C_ROCK_DARK],
	[0.88, -1.82, C_ROCK],
	[0.95, -2.18, C_ROCK],
	[0.97, -2.5, C_ROCK_DARK],
	[1.15, -2.75, C_ROCK_DEEP],
	[1.9, -3.45, C_SAND],
	[4.5, -3.75, C_SAND],
	[8.0, -4.3, C_SEABED],
	[12.0, -5.3, C_SEABED],
]


static func build_ground_mesh() -> ArrayMesh:
	var step: float = Tuning.GROUND_GRID_STEP
	var extent: float = Tuning.ISLAND_HALF_SIZE * 1.12
	var count: int = int(ceil(extent * 2.0 / step)) + 1
	var verts := PackedVector3Array()
	var inside := PackedByteArray()
	verts.resize(count * count)
	inside.resize(count * count)
	for iz: int in count:
		for ix: int in count:
			var p := Vector2(-extent + ix * step, -extent + iz * step)
			var r: float = Shape.outline_radius(atan2(p.y, p.x))
			var flag: int = 1
			if p.length() > r:
				p = p.normalized() * r
				flag = 0
			verts[iz * count + ix] = Vector3(p.x, Shape.ground_height(p), p.y)
			inside[iz * count + ix] = flag
	var indices := PackedInt32Array()
	for iz: int in count - 1:
		for ix: int in count - 1:
			var a: int = iz * count + ix
			var b: int = a + 1
			var c: int = a + count
			var d: int = c + 1
			if inside[a] + inside[b] + inside[c] + inside[d] == 0:
				continue
			indices.append_array([a, b, c, b, d, c])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i: int in range(0, indices.size(), 3):
		var n: Vector3 = (verts[indices[i + 2]] - verts[indices[i]]).cross(verts[indices[i + 1]] - verts[indices[i]])
		for k: int in 3:
			normals[indices[i + k]] += n
	for i: int in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-10 else Vector3.UP
		if normals[i].y < 0.0:
			normals[i] = -normals[i]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_cliff_mesh() -> ArrayMesh:
	var segs: int = Tuning.ISLAND_OUTLINE_SEGMENTS
	var rows: int = PROFILE.size()
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.35
	noise.fractal_octaves = 2
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var arc: float = 0.0
	var prev := Vector2.ZERO
	for i: int in segs + 1:
		var theta: float = TAU * float(i % segs) / float(segs)
		var base: Vector2 = Shape.outline_point(theta)
		if i > 0:
			arc += base.distance_to(prev)
		prev = base
		var outward := Vector2(cos(theta), sin(theta))
		var chunk: float = noise.get_noise_1d(arc * 0.6) * 0.5 + 0.5
		for j: int in rows:
			var row: Array = PROFILE[j]
			var offset: float = row[0]
			var y: float = row[1]
			if j >= 9 and j <= 14:
				offset += 0.22 * noise.get_noise_2d(arc, y * 2.2) + 0.12 * chunk
				y += 0.06 * noise.get_noise_2d(arc * 1.7 + 40.0, y)
			elif j >= 4:
				offset += 0.05 * noise.get_noise_2d(arc * 2.0, 3.0)
			var p: Vector2 = base + outward * offset
			verts.append(Vector3(p.x, y, p.y))
			var col: Color = row[2]
			var shade: float = 0.93 + 0.14 * (noise.get_noise_2d(arc * 0.8, y * 4.0) * 0.5 + 0.5)
			colors.append(Color(col.r * shade, col.g * shade, col.b * shade).srgb_to_linear())
	for i: int in segs:
		for j: int in rows - 1:
			var a: int = i * rows + j
			var b: int = a + rows
			indices.append_array([a, a + 1, b, b, a + 1, b + 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in verts.size():
		st.set_color(colors[i])
		st.add_vertex(verts[i])
	for idx: int in indices:
		st.add_index(idx)
	st.generate_normals()
	return st.commit()


## Hanging roots under the grass lip and stones jutting out of the rock face.
static func build_cliff_details(parent: Node3D, rock_mesh: Mesh, rock_mat: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var Kit: GDScript = load("res://scripts/world/mesh_kit.gd")
	var kit = Kit.new()
	var root_dark := Color("5A3A20")
	var root_light := Color("7A5030")
	for i: int in 4:
		var a: float = TAU * i / 4.0
		var p0 := Vector3(cos(a) * 0.03, 0.0, sin(a) * 0.03)
		var p1 := Vector3(cos(a) * 0.12, -0.25, sin(a) * 0.08 + 0.06)
		var p2 := Vector3(cos(a) * 0.16, -0.5 - 0.1 * (i % 2), sin(a) * 0.1 + 0.1)
		for seg: Array in [[p0, p1, 0.035, 0.025], [p1, p2, 0.025, 0.01]]:
			var from: Vector3 = seg[0]
			var to: Vector3 = seg[1]
			var cyl: CylinderMesh = Kit.cylinder(seg[3], seg[2], from.distance_to(to), 5)
			var up: Vector3 = (from - to).normalized()
			var side: Vector3 = up.cross(Vector3.FORWARD).normalized()
			if side.length_squared() < 0.01:
				side = Vector3.RIGHT
			var basis := Basis(side, up, side.cross(up))
			kit.add(cyl, Transform3D(basis, (from + to) * 0.5), root_dark, root_light)
	var root_mesh: Mesh = kit.commit()
	var roots: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var segs: int = 140
	for i: int in segs:
		var theta: float = TAU * (i + rng.randf()) / segs
		var base: Vector2 = Shape.outline_point(theta)
		var out := Vector2(cos(theta), sin(theta))
		var yaw: float = -theta + PI * 0.5
		if rng.randf() < 0.45:
			var p: Vector2 = base + out * 0.5
			roots.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(p.x, -0.4, p.y)))
		if rng.randf() < 0.35:
			var depth: float = rng.randf_range(-2.3, -1.15)
			var p: Vector2 = base + out * (0.72 + rng.randf_range(-0.05, 0.12))
			var sc: float = rng.randf_range(0.35, 0.75)
			stones.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 1.3, sc * 0.8, sc)), Vector3(p.x, depth, p.y)))
	for pair: Array in [[root_mesh, load("res://scripts/world/world_materials.gd").vertex_color(&"roots", 0.9), roots], [rock_mesh, rock_mat, stones]]:
		var list: Array = pair[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = list.size()
		for k: int in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.multimesh = mm
		mmi.material_override = pair[1]
		parent.add_child(mmi)
