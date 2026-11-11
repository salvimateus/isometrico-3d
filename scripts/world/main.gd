extends Node3D

## Scene assembly: environment, island, water, decor, buildings, camera, selection, HUD.

const Tuning := preload("res://scripts/tuning.gd")
const Layout := preload("res://scripts/world/base_layout.gd")
const Shape := preload("res://scripts/world/island_shape.gd")
const IslandBuilder := preload("res://scripts/world/island_builder.gd")
const GroundData := preload("res://scripts/world/ground_data.gd")
const DecorScatter := preload("res://scripts/world/decor_scatter.gd")
const Spawner := preload("res://scripts/world/building_spawner.gd")
const Bridge := preload("res://scripts/world/bridge_builder.gd")
const Ambient := preload("res://scripts/world/ambient_life.gd")
const EnvBuilder := preload("res://scripts/world/environment_builder.gd")
const CameraRig := preload("res://scripts/camera/camera_rig.gd")
const Selection := preload("res://scripts/world/selection_controller.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const WorldCollision := preload("res://scripts/world/world_collision.gd")
const PostFx := preload("res://scripts/world/post_fx.gd")
const WorldFx := preload("res://scripts/world/world_fx.gd")
const VillageProps := preload("res://scripts/world/village_props.gd")
const DayNight := preload("res://scripts/world/day_night.gd")
const FogMasks := preload("res://scripts/world/fog_masks.gd")
const Quality := preload("res://scripts/quality.gd")

const CATAPULT_FACTORY_PATH: String = "res://scripts/catapult/catapult_factory.gd"
const LIQUID_FACTORY_PATH: String = "res://scripts/liquid/liquid_factory.gd"
const LiquidTerrain := preload("res://scripts/world/liquid_terrain.gd")
const PondBody := preload("res://scripts/world/pond_body.gd")
const CLOUD_FACTORY_PATH: String = "res://scripts/clouds/cloud_factory.gd"
const FOG_FACTORY_PATH: String = "res://scripts/fog/fog_factory.gd"
const FOG_AGITATOR_PATH: String = "res://scripts/fog/fog_agitator.gd"

const COLLECTORS_PATH: String = "res://scripts/world/resource_collectors.gd"

const PLAYER_FACTORY_PATH: String = "res://scripts/character/player_factory.gd"

var rig: Node3D
var spawner: Spawner
var selection: Node3D
var player: Node3D = null
var day_night: Node = null
## Perf toggle read by day_night for the lantern OmniLights.
var night_lights_enabled: bool = true
var perf: Node = null
var liquid: Node3D = null
var _catapult_controller: Object = null
var _decor_shakers: Array[Dictionary] = []
var _ground: GroundData = null
var _water_mats: Array[ShaderMaterial] = []


func _ready() -> void:
	var args: Dictionary = _user_args()
	_apply_quality_tier()
	EnvBuilder.build(self, String(args.get("tonemap", "aces")))
	if not args.has("no-clouds"):
		_setup_clouds()

	spawner = Spawner.new(not args.has("placeholders"))
	var problems: PackedStringArray = Layout.validate(spawner.footprint_of)
	for p: String in problems:
		push_warning("[Layout] " + p)

	var ground := GroundData.new()
	ground.build(spawner.footprint_of)
	_ground = ground
	var ground_mesh: Mesh = _build_island(ground)
	_build_water()

	var decor := DecorScatter.new()
	decor.build(self, ground)
	_decor_shakers = decor.shakers
	var bridge: MeshInstance3D = Bridge.build()
	bridge.position = Layout.BRIDGE_CENTER
	add_child(bridge)
	VillageProps.build(self, ground)
	Ambient.build(self)
	WorldCollision.build(self, ground, ground_mesh, Bridge.LENGTH, Bridge.WIDTH, Bridge.RISE, decor.shakers, decor.rock_points)

	spawner.spawn_all(self)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	selection = Selection.new()
	selection.name = "Selection"
	add_child(selection)
	selection.setup(spawner, rig)
	var world_fx: Node3D = WorldFx.new()
	world_fx.name = "WorldFx"
	add_child(world_fx)
	var post_fx: CanvasLayer = PostFx.new()
	post_fx.name = "PostFx"
	add_child(post_fx)
	if args.get("postfx", "1") == "0":
		post_fx.visible = false
	var hud: CanvasLayer = Hud.new()
	add_child(hud)
	var touch: CanvasLayer = load("res://scripts/ui/touch_controls.gd").new()
	touch.name = "TouchControls"
	touch.call(&"setup", rig, selection, hud)
	add_child(touch)

	player = null if args.has("no-player") else _spawn_player()
	if player == null and args.has("fake-player"):
		player = load("res://scripts/dev/fake_player.gd").new()
		player.position = _spawn_point() + Vector3(0, 0.05, 0)
		add_child(player)
	rig.set_follow_target(player)
	touch.call(&"set_player", player)
	world_fx.set(&"player", player)
	_setup_collectors(hud)
	_setup_catapults()
	if args.has("catapult-auto"):
		_after_frames(int(args["catapult-auto"]), _catapult_auto)
	_setup_liquid(args)
	_setup_fog(args.has("no-fog"))
	_setup_day_night(args.get("night", "0") == "1")
	_warm_up()
	perf = load("res://scripts/world/perf_settings.gd").new()
	perf.name = "PerfSettings"
	add_child(perf)
	perf.call(&"setup", self)
	hud.call(&"attach_perf_panel", perf)
	if args.has("perf-panel"):
		_after_frames(30, func() -> void: (hud.get(&"fps_pill") as Node).emit_signal(&"tapped"))
	rig.follow_locked = args.has("view")
	if args.has("pitch"):
		rig.pitch_deg = float(args["pitch"])
	if args.has("catapult-auto") and not args.has("view") and player != null:
		# Start in the normal follow framing on the player, not in overview.
		rig.focus_on(player.global_position, Tuning.CAMERA_FOLLOW_DISTANCE, true)
	else:
		_apply_view(String(args.get("view", "overview")), args)
		if Quality.is_mobile() and not args.has("view") and player != null:
			_mobile_intro()
	if args.has("where-player") and player != null:
		get_tree().create_timer(1.0).timeout.connect(func() -> void: print("[where-player] ", player.global_position, " visible=", player.is_visible_in_tree()))
	if args.has("splash-test"):
		_after_frames(int(args["splash-test"]), func() -> void: get_tree().get_first_node_in_group(&"water_body").call(&"splash", Vector3(Layout.CATAPULT_TARGET.x, 0.0, Layout.CATAPULT_TARGET.y), 1.0))
	if args.has("check-landing"):
		get_tree().create_timer(0.5).timeout.connect(_check_landing)
	if args.has("player-at") and player != null:
		# `--player-at=x,z` teleports the player there at frame 60 (dev).
		var xz: PackedStringArray = String(args["player-at"]).split(",")
		_after_frames(60, func() -> void: player.global_position = Vector3(float(xz[0]), Shape.ground_height(Vector2(float(xz[0]), float(xz[1]))) + 0.1, float(xz[1])))
	if args.has("toggle-night-at"):
		_after_frames(int(args["toggle-night-at"]), func() -> void: if day_night != null: day_night.call(&"toggle"))
	if args.has("perf-probe"):
		add_child(load("res://scripts/dev/perf_probe.gd").new())
	if args.has("flood-probe"):
		add_child(load("res://scripts/dev/flood_probe.gd").new())
	if args.has("frame-spikes"):
		add_child(load("res://scripts/dev/frame_spike.gd").new())
	if args.has("bump-probe"):
		add_child(load("res://scripts/dev/bump_probe.gd").new())
	if args.has("probe-collision"):
		var probe: Node3D = load("res://scripts/dev/collision_probe.gd").new()
		add_child(probe)


func _spawn_player() -> Node3D:
	if not ResourceLoader.exists(PLAYER_FACTORY_PATH):
		return null
	var factory: Resource = load(PLAYER_FACTORY_PATH)
	if not (factory is GDScript) or not (factory as GDScript).can_instantiate():
		return null
	var made: Variant = (factory as GDScript).call("create")
	if not (made is Node3D):
		return null
	var body: Node3D = made
	body.name = "Player"
	body.position = _spawn_point() + Vector3(0.0, 0.05, 0.0)
	add_child(body)
	return body


func _user_args() -> Dictionary:
	var out: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _setup_liquid(args: Dictionary) -> void:
	if args.has("no-liquid") or not ResourceLoader.exists(LIQUID_FACTORY_PATH):
		return
	var factory: Resource = load(LIQUID_FACTORY_PATH)
	if not (factory is GDScript) or not (factory as GDScript).can_instantiate():
		return
	var field: Variant = (factory as GDScript).call(&"create", Tuning.LIQUID_AREA)
	if not (field is Node3D):
		return
	liquid = field
	add_child(liquid)
	var images: Array[Image] = LiquidTerrain.build(Tuning.LIQUID_AREA, spawner.buildings)
	liquid.call(&"set_terrain", images[0], images[1], images[2])
	var tower: Node3D = null
	var button_index: int = -1
	for i: int in spawner.buildings.size():
		var b: Dictionary = spawner.buildings[i]
		if b["kind"] == &"water_tower":
			tower = b["model"]
		elif b["kind"] == &"water_button":
			button_index = i
	if tower == null or button_index < 0:
		return
	liquid.call(&"attach_tower", tower, spawner.buildings[button_index]["model"])
	selection.click_actions[button_index] = _trigger_liquid
	if args.has("liquid-trigger"):
		_after_frames(int(args["liquid-trigger"]), _trigger_liquid)


func _trigger_liquid() -> void:
	if liquid != null and bool(liquid.call(&"can_trigger")):
		liquid.call(&"trigger")


## Hands each catapult model to the CATAPULT module; clicks on it call try_mount() on the returned controller.
func _setup_catapults() -> void:
	if not ResourceLoader.exists(CATAPULT_FACTORY_PATH):
		return
	var factory: Resource = load(CATAPULT_FACTORY_PATH)
	if not (factory is GDScript) or not (factory as GDScript).can_instantiate():
		return
	var has_attach: bool = false
	for m: Dictionary in (factory as GDScript).get_script_method_list():
		if m["name"] == "attach":
			has_attach = true
	if not has_attach:
		return
	for i: int in spawner.buildings.size():
		var b: Dictionary = spawner.buildings[i]
		if b["kind"] != &"catapult":
			continue
		var controller: Variant = (factory as GDScript).call(&"attach", b["model"])
		if controller is Object and (controller as Object).has_method(&"try_mount"):
			selection.mount_targets[i] = controller
			_catapult_controller = controller


## Dev: puts the player right in front of the catapult and mounts it (`--catapult-auto=<frame>`).
func _catapult_auto() -> void:
	if _catapult_controller == null or player == null:
		push_warning("[catapult-auto] no catapult controller or player")
		return
	var center: Vector2 = Layout.catapult_center()
	var front: Vector2 = center + (Layout.CATAPULT_TARGET - center).normalized() * 2.6
	player.global_position = Vector3(front.x, Shape.ground_height(front) + 0.05, front.y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[catapult-auto] try_mount -> ", _catapult_controller.call(&"try_mount"))


## Pre-synthesizes sounds and draws each one-shot FX once, hidden under the ground at the view center,
## so the first bump, collect or splash does not hitch on synthesis or pipeline compilation.
func _warm_up() -> void:
	const Sfx := preload("res://scripts/world/sfx_bridge.gd")
	var presets: Array[StringName] = [&"ui_pop", &"ui_select", &"ui_tick", &"coin_clink", &"mana_bloop", &"collect_whoosh", &"tree_rustle", &"building_thud", &"splash_big"]
	Sfx.warm(presets)
	await get_tree().process_frame
	var fx: Node = get_tree().get_first_node_in_group(&"world_fx")
	if fx == null:
		return
	var hidden: Vector3 = Vector3(rig.position.x, -2.0, rig.position.z)
	fx.call(&"dust", hidden, 0.5)
	fx.call(&"leaves", hidden)
	fx.call(&"sparks", hidden, 0.5)
	fx.call(&"splash_drops", hidden)
	var collectors: Node = get_node_or_null(^"ResourceCollectors")
	if collectors != null and collectors.has_method(&"warm_up"):
		collectors.call(&"warm_up", hidden)


## Mobile boot: overview first, then a ~1.5 s dolly that lands following the player at a readable distance.
func _mobile_intro() -> void:
	await get_tree().create_timer(Tuning.MOBILE_INTRO_HOLD).timeout
	if player == null or not is_instance_valid(player):
		return
	var from_pos: Vector3 = rig.position
	var from_dist: float = float(rig.get(&"distance"))
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var target: Vector3 = player.global_position
		rig.focus_on(from_pos.lerp(target, t), lerpf(from_dist, Tuning.MOBILE_START_DISTANCE, t), true),
		0.0, 1.0, Tuning.MOBILE_INTRO_DOLLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if rig.has_method(&"_engage_follow"):
		rig.call(&"_engage_follow", false)


## Mobile tier: cheaper shadows, 2x MSAA and FSR-upscaled 3D at 75% (2D HUD stays native).
func _apply_quality_tier() -> void:
	if not Quality.is_mobile():
		return
	var vp: Viewport = get_viewport()
	vp.msaa_3d = Tuning.MOBILE_MSAA
	# FSR1 is Forward+ only; the Mobile renderer gets bilinear.
	var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Tuning.MOBILE_SCALING_MODE if not forward_plus else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = Tuning.MOBILE_SCALE_3D
	vp.fsr_sharpness = Tuning.MOBILE_FSR_SHARPNESS
	RenderingServer.directional_shadow_atlas_set_size(Tuning.MOBILE_SHADOW_SIZE, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(Tuning.MOBILE_SHADOW_FILTER_QUALITY)
	print("[Quality] tier=mobile renderer=", RenderingServer.get_current_rendering_method())


func _setup_clouds() -> void:
	if not ResourceLoader.exists(CLOUD_FACTORY_PATH):
		return
	var factory: Resource = load(CLOUD_FACTORY_PATH)
	if not (factory is GDScript) or not (factory as GDScript).can_instantiate():
		return
	var clouds: Variant = (factory as GDScript).call(&"create", Tuning.CLOUD_AREA)
	if clouds is Node3D:
		add_child(clouds)


func _setup_fog(disabled: bool) -> void:
	if disabled or not ResourceLoader.exists(FOG_FACTORY_PATH):
		return
	var factory: Resource = load(FOG_FACTORY_PATH)
	if not (factory is GDScript) or not (factory as GDScript).can_instantiate():
		return
	var area: Rect2 = Tuning.FOG_AREA
	var fog: Variant = (factory as GDScript).call(&"create", area)
	if not (fog is Node3D):
		return
	add_child(fog)
	fog.call(&"set_obstacles", FogMasks.obstacles(area, spawner.buildings, _decor_shakers))
	fog.call(&"set_base_density", FogMasks.base_density(area, _ground))
	if player != null and ResourceLoader.exists(FOG_AGITATOR_PATH):
		var agitator_script: Resource = load(FOG_AGITATOR_PATH)
		if agitator_script is GDScript and (agitator_script as GDScript).can_instantiate():
			player.add_child((agitator_script as GDScript).new())


func _setup_day_night(start_night: bool) -> void:
	var world_env: WorldEnvironment = get_node_or_null(^"WorldEnvironment")
	var sun: DirectionalLight3D = get_node_or_null(^"Sun")
	if world_env == null or sun == null:
		push_warning("[DayNight] WorldEnvironment or Sun not found")
		return
	var life: Array[GPUParticles3D] = []
	var ambient: Node = get_node_or_null(^"AmbientLife")
	if ambient != null:
		for child: Node in ambient.get_children():
			if child is GPUParticles3D:
				life.append(child)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.call(&"setup", world_env, sun, _water_mats, life)
	if start_night:
		day_night.call(&"set_night", true, true)


func _setup_collectors(hud: CanvasLayer) -> void:
	if not ResourceLoader.exists(COLLECTORS_PATH):
		return
	var script: Resource = load(COLLECTORS_PATH)
	if not (script is GDScript) or not (script as GDScript).can_instantiate():
		return
	var collectors: Node3D = (script as GDScript).new()
	collectors.name = "ResourceCollectors"
	add_child(collectors)
	collectors.call(&"setup", spawner, rig, hud)
	collectors.call(&"set_player", player)
	selection.collectors = collectors


## Free path tile in front (+Z) of the town hall, on its center column.
func _spawn_point() -> Vector3:
	for e: Dictionary in Layout.entries():
		if e["kind"] == &"town_hall":
			var cell: Vector2i = e["cell"]
			var fp: Vector2i = spawner.footprint_of(&"town_hall")
			return Vector3(cell.x + fp.x * 0.5 - Layout.HALF, 0.0, cell.y + fp.y + 0.5 - Layout.HALF)
	return Vector3(0.0, 0.0, 3.0)


func _apply_view(view: String, args: Dictionary) -> void:
	var dist_override: float = float(args.get("distance", "0"))
	match view:
		"overview":
			rig.focus_on(Vector3(1.8, 0, 1.8), dist_override if dist_override > 0.0 else Tuning.CAMERA_DISTANCE_DEFAULT, true)
		"ditch":
			rig.focus_on(Vector3(9.5, 0, 6.5), dist_override if dist_override > 0.0 else 30.0, true)
		"pond":
			rig.focus_on(Vector3(Layout.CATAPULT_TARGET.x + 1.0, 0, Layout.CATAPULT_TARGET.y - 1.0), dist_override if dist_override > 0.0 else 16.0, true)
		"close":
			rig.focus_on(Vector3.ZERO, dist_override if dist_override > 0.0 else Tuning.CAMERA_DISTANCE_CLOSE, true)
		_:
			for i: int in spawner.buildings.size():
				var b: Dictionary = spawner.buildings[i]
				if String(b["kind"]) == view:
					var slot: Node3D = b["slot"]
					# Aim a bit up-screen so tall buildings and their name label stay framed.
					var lift: float = (b["aabb"] as AABB).end.y * 0.55
					rig.focus_on(slot.position + Vector3(-1, 0, -1).normalized() * lift, dist_override if dist_override > 0.0 else 22.0, true)
					if args.has("select"):
						selection.select(i)
					return
			push_warning("Unknown view '%s', using overview" % view)
			rig.focus_on(Vector3.ZERO, Tuning.CAMERA_DISTANCE_DEFAULT, true)


func _build_island(ground: GroundData) -> Mesh:
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/world/grass.gdshader")
	grass_mat.set_shader_parameter("ground_data", ground.texture)
	grass_mat.set_shader_parameter("data_rect", ground.data_rect())
	grass_mat.set_shader_parameter("play_half", Layout.HALF)
	var top := MeshInstance3D.new()
	top.name = "Ground"
	top.mesh = IslandBuilder.build_ground_mesh()
	top.material_override = grass_mat
	add_child(top)

	var cliff_mat := ShaderMaterial.new()
	cliff_mat.shader = load("res://shaders/world/cliff.gdshader")
	var cliff := MeshInstance3D.new()
	cliff.name = "Cliff"
	cliff.mesh = IslandBuilder.build_cliff_mesh()
	cliff.material_override = cliff_mat
	add_child(cliff)
	IslandBuilder.build_cliff_details(self, load("res://scripts/world/decor_meshes.gd").rock(2), load("res://scripts/world/world_materials.gd").vertex_color(&"rock", 0.9))

	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	seabed.mesh = plane
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color("2B8FA6")
	bed_mat.roughness = 1.0
	seabed.material_override = bed_mat
	seabed.position.y = -5.3
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seabed)
	return top.mesh


func _build_water() -> void:
	var shader: Shader = load("res://shaders/world/water.gdshader")
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = shader
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	sea.mesh = plane
	sea.material_override = sea_mat
	_water_mats.append(sea_mat)
	sea.position.y = Tuning.WATER_LEVEL
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)

	var pond_mat := ShaderMaterial.new()
	pond_mat.shader = shader
	pond_mat.set_shader_parameter("foam_width", 0.05)
	pond_mat.set_shader_parameter("ring_strength", 0.0)
	pond_mat.set_shader_parameter("splash_enabled", 1.0)
	pond_mat.set_shader_parameter("far_start", 1000.0)
	pond_mat.set_shader_parameter("far_end", 1001.0)
	pond_mat.set_shader_parameter("wave_scale", 0.45)
	pond_mat.set_shader_parameter("shallow_alpha", 0.7)
	pond_mat.set_shader_parameter("caustic_strength", 0.12)
	pond_mat.set_shader_parameter("shallow_color", Color("38B9C9"))
	pond_mat.set_shader_parameter("deep_color", Color("1E86A8"))
	pond_mat.set_shader_parameter("depth_range", 0.55)
	var pond := MeshInstance3D.new()
	pond.name = "Pond"
	var pond_plane := PlaneMesh.new()
	pond_plane.size = Vector2(8.6, 5.6)
	pond.mesh = pond_plane
	pond.material_override = pond_mat
	_water_mats.append(pond_mat)
	var pond_body: Node3D = PondBody.new()
	pond_body.name = "PondWaterBody"
	add_child(pond_body)
	var target := Marker3D.new()
	target.name = "CatapultTarget"
	target.position = Vector3(Layout.CATAPULT_TARGET.x, Shape.POND_WATER_Y, Layout.CATAPULT_TARGET.y)
	target.set_meta(&"radius", Layout.CATAPULT_TARGET_RADIUS)
	target.add_to_group(&"catapult_target")
	add_child(target)
	pond.position = Vector3(Layout.BRIDGE_CENTER.x, Shape.POND_WATER_Y, 13.5)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond)


## Dev args count rendered frames (like ScreenshotTool), not seconds.
func _after_frames(frames: int, action: Callable) -> void:
	for i: int in maxi(frames, 1):
		await get_tree().process_frame
	action.call()


func _check_landing() -> void:
	var shape := SphereShape3D.new()
	shape.radius = Layout.LANDING_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 2
	q.transform = Transform3D(Basis(), Vector3(Layout.LANDING_CENTER.x, 0.5, Layout.LANDING_CENTER.y))
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(q, 32)
	print("[check-landing] layer-2 bodies in pocket: ", hits.size())
