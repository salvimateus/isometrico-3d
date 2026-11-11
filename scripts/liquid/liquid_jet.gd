extends MeshInstance3D

## Pouring stream: a tube swept along the ballistic path of the water leaving the bucket.
## Top level at the identity transform; rebuilt every frame while visible.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const P := preload("res://scripts/liquid/liquid_profile.gd")
const JET_SHADER := preload("res://shaders/liquid/liquid_jet.gdshader")

var material: ShaderMaterial

var _mesh := ImmediateMesh.new()


func _init() -> void:
	name = "PourJet"
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = P.shader(JET_SHADER)
	material_override = material
	visible = false


func set_foam_texture(tex: Texture2D) -> void:
	material.set_shader_parameter(&"foam_tex", tex)


## Sweeps the stream between flight times t0 and t1 of the path origin + v0 t + g t^2 / 2.
func build(origin: Vector3, v0: Vector3, radius: float, t0: float, t1: float, flow: float, time: float) -> void:
	_mesh.clear_surfaces()
	if t1 - t0 < 0.01 or radius < 0.005:
		visible = false
		return
	visible = true
	material.set_shader_parameter(&"flow", clampf(flow * 1.3, 0.25, 1.0))
	var g := Vector3(0.0, -LT.GRAVITY, 0.0)
	var segs: int = P.jet_segments()
	var sides: int = P.jet_sides()
	var speed0: float = maxf(v0.length(), 0.5)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var vs: PackedFloat32Array = PackedFloat32Array()
	var prev_side := Vector3.RIGHT
	for i: int in segs + 1:
		var k: float = float(i) / float(segs)
		var t: float = lerpf(t0, t1, k)
		var c: Vector3 = origin + v0 * t + 0.5 * g * t * t
		var vel: Vector3 = v0 + g * t
		var tang: Vector3 = vel.normalized()
		var side: Vector3 = tang.cross(Vector3.UP)
		if side.length() < 0.1:
			side = prev_side
		side = side.normalized()
		prev_side = side
		var up: Vector3 = side.cross(tang).normalized()
		# Continuity thins the jet as it accelerates; the lip end swells a little.
		var r: float = radius * sqrt(speed0 / maxf(vel.length(), 0.5))
		r *= 1.0 + 0.12 * sin(t * 23.0 - time * 17.0) + 0.08 * sin(t * 41.0 + time * 9.0)
		r *= lerpf(1.0, 1.25, smoothstep(0.75, 1.0, k))
		var ring := PackedVector3Array()
		var nring := PackedVector3Array()
		for j: int in sides + 1:
			var a: float = float(j) / float(sides) * TAU
			var dir: Vector3 = side * cos(a) + up * sin(a)
			var flat: float = 1.25 + 0.45 * clampf(t * 2.0, 0.0, 1.0)
			# Lumpy, sheeting skin: lobes that drift along the fall.
			var lump: float = 1.0 + 0.16 * sin(a * 3.0 + t * 13.0 - time * 8.0) + 0.09 * sin(a * 5.0 - t * 21.0 + time * 5.0)
			ring.append(c + side * cos(a) * r * flat * lump + up * sin(a) * r / flat * lump)
			nring.append(dir)
		rings.append(ring)
		normals.append(nring)
		vs.append(t)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segs:
		for j: int in sides:
			for q: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var ii: int = i + q.y
				var jj: int = j + q.x
				_mesh.surface_set_normal(normals[ii][jj])
				_mesh.surface_set_uv(Vector2(float(jj) / float(sides), vs[ii] / 0.7))
				_mesh.surface_add_vertex(rings[ii][jj])
	_mesh.surface_end()
	custom_aabb = AABB(origin - Vector3(8, 12, 8), Vector3(16, 16, 16))


func hide_jet() -> void:
	_mesh.clear_surfaces()
	visible = false
