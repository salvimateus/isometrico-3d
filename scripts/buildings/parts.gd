extends RefCounted
## Assembly helpers shared by every building: placing meshes and the recurring details
## (footing, windows, doors, flags, smoke, idle-animated pivots).

const Kit = preload("res://scripts/buildings/mesh_kit.gd")
const Mat = preload("res://scripts/buildings/materials.gd")
const Tuning = preload("res://scripts/buildings/building_tuning.gd")
const SPIN = preload("res://scripts/buildings/anim/spin.gd")
const BOB = preload("res://scripts/buildings/anim/bob.gd")
const SWAY = preload("res://scripts/buildings/anim/sway.gd")
const LIGHT_PULSE = preload("res://scripts/buildings/anim/light_pulse.gd")
const NIGHT_LIGHT = preload("res://scripts/buildings/anim/night_light.gd")

static var _process_cache: Dictionary = {}


static func mesh(parent: Node3D, m: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Roof mesh (hip_roof / gable_roof): tiles on surface 0, `under` (default dark wood) on fascia and underside.
static func roof(parent: Node3D, m: Mesh, tiles: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, under: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.set_surface_override_material(0, tiles)
	mi.set_surface_override_material(1, under if under != null else Mat.wood_dark())
	parent.add_child(mi)
	return mi


## Cone roof with a dark wooden soffit disc so it reads right from below.
static func cone_roof(parent: Node3D, radius: float, height: float, tiles: Material, pos: Vector3) -> void:
	mesh(parent, Kit.cone(radius, height, 0, 0.05), tiles, pos)
	mesh(parent, Kit.cylinder(radius - 0.02, 0.03, 0.01), Mat.wood_dark(), pos + Vector3(0.0, -0.005, 0.0))


static func box(parent: Node3D, size: Vector3, material: Material, pos: Vector3, radius: float = 0.05, rot_deg: Vector3 = Vector3.ZERO, taper: float = 0.0) -> MeshInstance3D:
	return mesh(parent, Kit.rounded_box(size, radius, taper), material, pos, rot_deg)


## Box whose bottom sits at `pos.y`.
static func block(parent: Node3D, size: Vector3, material: Material, pos: Vector3, radius: float = 0.05, taper: float = 0.0, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return mesh(parent, Kit.rounded_box(size, radius, taper), material, pos + Vector3(0.0, size.y * 0.5, 0.0), rot_deg)


## Cylinder whose bottom sits at `pos.y`.
static func cyl(parent: Node3D, radius: float, height: float, material: Material, pos: Vector3, bevel: float = 0.04, radius_top: float = -1.0, sides: int = 0) -> MeshInstance3D:
	return mesh(parent, Kit.cylinder(radius, height, bevel, radius_top, sides), material, pos + Vector3(0.0, height * 0.5, 0.0))


## Rod between two points (beams, braces, spears, pipes).
static func rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material, sides: int = 0, square: bool = false) -> MeshInstance3D:
	var dir: Vector3 = to - from
	var length: float = dir.length()
	var m: Mesh
	if square:
		m = Kit.rounded_box(Vector3(radius * 2.0, length, radius * 2.0), radius * 0.35)
	else:
		m = Kit.cylinder(radius, length, radius * 0.3, -1.0, sides if sides > 0 else Tuning.CYLINDER_SIDES_SMALL)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	var up: Vector3 = dir / length
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd: Vector3 = side.cross(up).normalized()
	mi.transform = Transform3D(Basis(side, up, fwd), (from + to) * 0.5)
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, node_name: String = "") -> Node3D:
	var n := Node3D.new()
	if not node_name.is_empty():
		n.name = node_name
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


static func animated(parent: Node3D, script: Script, props: Dictionary, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, node_name: String = "") -> Node3D:
	var n := Node3D.new()
	n.set_script(script)
	for k: String in props:
		n.set(k, props[k])
	n.position = pos
	n.rotation_degrees = rot_deg
	if not node_name.is_empty():
		n.name = node_name
	parent.add_child(n)
	return n


static func spinner(parent: Node3D, pos: Vector3, axis: Vector3, speed: float, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	return animated(parent, SPIN, {"axis": axis, "speed": speed}, pos, rot_deg, "Spin")


static func bobber(parent: Node3D, pos: Vector3, amplitude: float, speed: float, axis: Vector3 = Vector3.UP) -> Node3D:
	return animated(parent, BOB, {"axis": axis, "amplitude": amplitude, "speed": speed}, pos, Vector3.ZERO, "Bob")


static func swayer(parent: Node3D, pos: Vector3, axis: Vector3, amplitude_deg: float, speed: float, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	return animated(parent, SWAY, {"axis": axis, "amplitude_deg": amplitude_deg, "speed": speed}, pos, rot_deg, "Sway")


## Dark stone slab every building stands on (y = 0 to `height`).
static func footing(parent: Node3D, size_xz: Vector2, height: float = 0.14, material: Material = null) -> void:
	var mat: Material = material if material != null else Mat.stone_dark()
	block(parent, Vector3(size_xz.x, height, size_xz.y), mat, Vector3.ZERO, minf(0.07, height * 0.5))


## Glowing window with frame, cross muntins and sill, built facing +Z then turned by `yaw_deg`
## (0 = +Z, 90 = +X). `pos` is the pane center on the wall surface.
static func window(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector2 = Vector2(0.36, 0.44), arched: bool = false, frame_mat: Material = null) -> Node3D:
	var root := pivot(parent, pos, Vector3(0.0, yaw_deg, 0.0), "Window")
	var fm: Material = frame_mat if frame_mat != null else Mat.wood_dark()
	var w: float = size.x
	var h: float = size.y
	var bar: float = 0.06
	if arched:
		mesh(root, Kit.arch(w + bar * 2.0, h + bar * 1.5, 0.05), fm, Vector3(0.0, -h * 0.5 - bar, 0.0))
		mesh(root, Kit.arch(w, h, 0.05), Mat.window_glow(), Vector3(0.0, -h * 0.5, 0.025))
		box(root, Vector3(0.035, h * 0.95, 0.05), fm, Vector3(0.0, -0.01, 0.045), 0.012)
		box(root, Vector3(w, 0.035, 0.05), fm, Vector3(0.0, -h * 0.12, 0.045), 0.012)
	else:
		box(root, Vector3(w, h, 0.04), Mat.window_glow(), Vector3(0.0, 0.0, 0.0), 0.01)
		box(root, Vector3(w + bar * 2.0, bar, 0.08), fm, Vector3(0.0, h * 0.5 + bar * 0.5 - 0.01, 0.02), 0.02)
		box(root, Vector3(bar, h, 0.08), fm, Vector3(w * 0.5 + bar * 0.5 - 0.01, 0.0, 0.02), 0.02)
		box(root, Vector3(bar, h, 0.08), fm, Vector3(-w * 0.5 - bar * 0.5 + 0.01, 0.0, 0.02), 0.02)
		box(root, Vector3(0.035, h, 0.05), fm, Vector3(0.0, 0.0, 0.025), 0.012)
		box(root, Vector3(w, 0.035, 0.05), fm, Vector3(0.0, 0.0, 0.025), 0.012)
	box(root, Vector3(w + 0.18, 0.06, 0.13), fm, Vector3(0.0, -h * 0.5 - 0.04, 0.05), 0.025)
	return root


## Arched plank door with stone surround and gold knob; `pos` is the bottom center on the wall.
static func door(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector2 = Vector2(0.5, 0.75), surround: Material = null) -> Node3D:
	var root := pivot(parent, pos, Vector3(0.0, yaw_deg, 0.0), "Door")
	var sm: Material = surround if surround != null else Mat.stone()
	mesh(root, Kit.arch(size.x + 0.16, size.y + 0.1, 0.08), sm, Vector3(0.0, 0.0, 0.0))
	mesh(root, Kit.arch(size.x, size.y, 0.06), Mat.planks(false, Mat.WOOD_DARK, Mat.WOOD_DEEP, 0.12), Vector3(0.0, 0.0, 0.03))
	box(root, Vector3(size.x * 0.96, 0.05, 0.04), Mat.metal(), Vector3(0.0, size.y * 0.25, 0.065), 0.015)
	box(root, Vector3(size.x * 0.96, 0.05, 0.04), Mat.metal(), Vector3(0.0, size.y * 0.62, 0.065), 0.015)
	mesh(root, Kit.sphere(0.035, 10, 6), Mat.gold(), Vector3(size.x * 0.28, size.y * 0.42, 0.08))
	return root


## Pole with gold knob and a waving flag; `pos` is the pole base.
static func flag(parent: Node3D, pos: Vector3, pole_height: float, cloth: Color, flag_size: Vector2 = Vector2(0.55, 0.34), pole_mat: Material = null) -> Node3D:
	var root := pivot(parent, pos, Vector3.ZERO, "Flag")
	var pm: Material = pole_mat if pole_mat != null else Mat.wood_dark()
	cyl(root, 0.03, pole_height, pm, Vector3.ZERO, 0.01, 0.025, 8)
	mesh(root, Kit.sphere(0.055, 10, 6), Mat.gold(), Vector3(0.0, pole_height + 0.03, 0.0))
	var cloth_mi := mesh(root, Kit.grid_plane(flag_size.x, flag_size.y, 10, 3), Mat.flag(cloth), Vector3(0.02, pole_height - flag_size.y * 0.5 - 0.04, 0.0), Vector3(0.0, 45.0, 0.0))
	cloth_mi.extra_cull_margin = 0.2
	return root


static func _particle_process(key: String, spread: float, velocity: Vector2, gravity: Vector3, scale_range: Vector2, emission_box: Vector3) -> ParticleProcessMaterial:
	if _process_cache.has(key):
		return _process_cache[key]
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = velocity.x
	pm.initial_velocity_max = velocity.y
	pm.gravity = gravity
	pm.scale_min = scale_range.x
	pm.scale_max = scale_range.y
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	if emission_box != Vector3.ZERO:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = emission_box
	_process_cache[key] = pm
	return pm


static func _smoke_process() -> ParticleProcessMaterial:
	var key := "smoke"
	if _process_cache.has(key):
		return _process_cache[key]
	var pm := _particle_process(key, 12.0, Vector2(0.25, 0.4), Vector3(0.12, 0.06, -0.04), Vector2(0.7, 1.1), Vector3(0.04, 0.0, 0.04))
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.5, 0.85))
	curve.add_point(Vector2(1.0, 1.25))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(0.12, Color(0.96, 0.96, 0.98, 0.75))
	g.add_point(0.6, Color(0.9, 0.9, 0.93, 0.45))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


## Chimney smoke puffs rising from `pos`.
static func smoke(parent: Node3D, pos: Vector3, amount: int, puff_radius: float = 0.12) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = amount
	p.lifetime = Tuning.SMOKE_LIFETIME
	p.preprocess = Tuning.SMOKE_LIFETIME
	p.randomness = 0.3
	p.process_material = _smoke_process()
	var puff := Kit.sphere(puff_radius, 10, 6)
	p.draw_pass_1 = puff
	p.material_override = Mat.smoke()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1.0, -0.2, -1.0), Vector3(2.0, 2.5, 2.0))
	p.position = pos
	parent.add_child(p)
	return p


## Rising bubbles inside a tank: emitted from a box of `extents` at `pos`.
static func bubbles(parent: Node3D, pos: Vector3, extents: Vector3, rise: float) -> GPUParticles3D:
	var key := "bubbles|%s|%.2f" % [extents, rise]
	var pm: ParticleProcessMaterial = _process_cache.get(key)
	if pm == null:
		pm = _particle_process(key, 5.0, Vector2(rise * 0.5, rise * 0.7) / Tuning.BUBBLE_LIFETIME, Vector3(0.0, rise * 0.3, 0.0), Vector2(0.6, 1.2), extents)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.15, Color(1.0, 0.9, 1.0, 0.9))
		g.add_point(0.8, Color(1.0, 0.9, 1.0, 0.7))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.name = "Bubbles"
	p.amount = Tuning.BUBBLE_AMOUNT
	p.lifetime = Tuning.BUBBLE_LIFETIME
	p.preprocess = Tuning.BUBBLE_LIFETIME
	p.process_material = pm
	p.draw_pass_1 = Kit.sphere(0.035, 8, 5)
	p.material_override = Mat.bubble()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-extents - Vector3(0.2, 0.2, 0.2), extents * 2.0 + Vector3(0.4, rise + 0.4, 0.4))
	p.position = pos
	parent.add_child(p)
	return p


## Warm night-only omni light (no shadow, short range) that joins the night-light group.
static func night_light(parent: Node3D, pos: Vector3) -> OmniLight3D:
	if not Tuning.USE_OMNI_LIGHTS:
		_halo(parent, pos)
		return null
	var l := OmniLight3D.new()
	l.set_script(NIGHT_LIGHT)
	l.light_color = Tuning.NIGHT_LIGHT_COLOR
	l.omni_range = Tuning.NIGHT_LIGHT_RANGE
	l.shadow_enabled = false
	l.light_specular = 0.3
	l.position = pos
	parent.add_child(l)
	return l


static var _halo_mesh: QuadMesh


## Additive billboard glow standing in for a lamp's light where OmniLight3D is too costly.
static func _halo(parent: Node3D, pos: Vector3) -> void:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(Tuning.HALO_SIZE, Tuning.HALO_SIZE)
	var mi := mesh(parent, _halo_mesh, Mat.halo(), pos)
	mi.name = "Halo"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Wall lantern facing `yaw_deg` (0 = +Z): bracket, glowing cage, caps and a night light.
static func lantern(parent: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var root := pivot(parent, pos, Vector3(0.0, yaw_deg, 0.0), "Lantern")
	box(root, Vector3(0.05, 0.05, 0.1), Mat.metal(), Vector3(0.0, 0.12, -0.04), 0.015)
	box(root, Vector3(0.12, 0.16, 0.12), Mat.lantern(), Vector3.ZERO, 0.03)
	box(root, Vector3(0.16, 0.04, 0.16), Mat.metal(), Vector3(0.0, 0.1, 0.0), 0.015)
	box(root, Vector3(0.14, 0.03, 0.14), Mat.metal(), Vector3(0.0, -0.09, 0.0), 0.012)
	night_light(root, Vector3(0.0, 0.0, 0.12))
	return root


static func mana_light(parent: Node3D, pos: Vector3) -> void:
	if not Tuning.USE_OMNI_LIGHTS:
		return
	var l := OmniLight3D.new()
	l.set_script(LIGHT_PULSE)
	l.light_color = Mat.MANA_BRIGHT
	l.light_energy = Tuning.MANA_LIGHT_ENERGY
	l.omni_range = Tuning.MANA_LIGHT_RANGE
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)


## Bounds of every mesh under `root`, in `root`'s local space (works before entering the tree).
static func local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != root and cur is Node3D:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b: AABB = t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Coin: thin gold disc lying flat, tilted by `rot_deg`.
static func coin(parent: Node3D, pos: Vector3, rot_deg: Vector3, radius: float = 0.09) -> MeshInstance3D:
	return mesh(parent, Kit.cylinder(radius, radius * 0.32, radius * 0.12, -1.0, 14), Mat.gold(), pos, rot_deg)


## Deterministic heap of gold nuggets and coins around `center` on a surface at `center.y`.
static func gold_heap(parent: Node3D, center: Vector3, radius: float, height: float, seed_value: int, coins: int = 10) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	mesh(parent, Kit.dome(radius * 0.96, height * 0.96, 16, 6), Mat.gold(), center)
	for i in 4:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.2, 0.75) * radius
		var hy: float = height * sqrt(maxf(0.0, 1.0 - (d / radius) * (d / radius)))
		var s: float = rng.randf_range(0.06, 0.1) * (radius / 0.6)
		mesh(parent, Kit.rounded_box(Vector3.ONE, 0.3), Mat.gold(), center + Vector3(cos(a) * d, hy - s * 0.2, sin(a) * d), Vector3(rng.randf() * 60.0, rng.randf() * 360.0, rng.randf() * 60.0), Vector3(s, s * 0.8, s))
	var coin_r: float = clampf(radius * 0.17, 0.06, 0.11)
	for i in coins * 2:
		var a2: float = rng.randf() * TAU
		var k: float = sqrt(rng.randf()) * 0.98
		var d2: float = k * radius
		var hy2: float = height * sqrt(maxf(0.0, 1.0 - k * k))
		# Tilt each coin to the dome slope so it lies on the surface.
		var slope: float = rad_to_deg(atan2(height * k, radius * sqrt(maxf(0.02, 1.0 - k * k))))
		var tilt: float = slope + rng.randf_range(-15.0, 15.0)
		var c := pivot(parent, center + Vector3(cos(a2) * d2, hy2, sin(a2) * d2), Vector3(0.0, -rad_to_deg(a2) - 90.0, 0.0))
		coin(c, Vector3.ZERO, Vector3(tilt, rng.randf() * 360.0, 0.0), coin_r * rng.randf_range(0.85, 1.1))
