extends RefCounted

## Small arched wooden footbridge spanning along Z, origin at its center on the ground.

const Kit := preload("res://scripts/world/mesh_kit.gd")
const Mats := preload("res://scripts/world/world_materials.gd")

const C_PLANK := Color("A8693A")
const C_PLANK_LIGHT := Color("C07E48")
const C_BEAM := Color("7A4A28")
const C_ROPE := Color("D9C08F")


const LENGTH: float = 4.2
const WIDTH: float = 1.3
const RISE: float = 0.42


static func build(length: float = LENGTH, width: float = WIDTH) -> MeshInstance3D:
	var kit := Kit.new()
	var planks: int = 11
	var rise: float = RISE
	for i: int in planks:
		var t: float = (i + 0.5) / planks
		var z: float = (t - 0.5) * length
		var y: float = 0.1 + rise * sin(PI * t)
		var slope: float = rise * PI * cos(PI * t) / length
		var w: float = width + (0.06 if i % 2 == 0 else -0.04)
		var basis := Basis(Vector3.RIGHT, -atan(slope)) * Basis(Vector3.UP, sin(i * 3.1) * 0.03)
		kit.add(Kit.box(Vector3(w, 0.09, length / planks * 0.9)), Transform3D(basis, Vector3(sin(i * 1.7) * 0.03, y, z)), C_PLANK, C_PLANK_LIGHT)
	for side: float in [-1.0, 1.0]:
		var segments: int = 8
		for i: int in segments:
			var t0: float = float(i) / segments
			var t1: float = float(i + 1) / segments
			var p0 := Vector3(side * (width * 0.5 - 0.02), 0.02 + rise * sin(PI * t0), (t0 - 0.5) * length)
			var p1 := Vector3(side * (width * 0.5 - 0.02), 0.02 + rise * sin(PI * t1), (t1 - 0.5) * length)
			kit.add(Kit.box(Vector3(0.12, 0.14, p0.distance_to(p1) + 0.02)), Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) * 0.5), C_BEAM, C_BEAM)
			var r0: Vector3 = p0 + Vector3(0, 0.62, 0)
			var r1: Vector3 = p1 + Vector3(0, 0.62, 0)
			kit.add(Kit.box(Vector3(0.08, 0.08, r0.distance_to(r1) + 0.02)), Transform3D(Basis.looking_at(r1 - r0, Vector3.UP), (r0 + r1) * 0.5), C_PLANK, C_PLANK_LIGHT)
		for t: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var y: float = rise * sin(PI * t)
			var base := Vector3(side * (width * 0.5 - 0.02), y - 0.25, (t - 0.5) * length)
			var h: float = 1.0 if t == 0.0 or t == 1.0 else 0.92
			kit.add(Kit.cylinder(0.075, 0.09, h, 8), Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)), C_BEAM, C_PLANK)
			kit.add(Kit.sphere(0.095, 8, 4), Transform3D(Basis(), base + Vector3(0, h, 0)), C_PLANK, C_PLANK_LIGHT)
	var mi := MeshInstance3D.new()
	mi.name = "Bridge"
	mi.mesh = kit.commit()
	mi.material_override = Mats.vertex_color(&"wood", 0.82)
	return mi
