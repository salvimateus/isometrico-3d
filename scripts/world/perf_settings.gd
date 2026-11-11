extends Node

## Runtime performance settings (perf panel): applies, persists to user://perf.cfg, and drives the
## mobile dynamic 3D resolution. Defaults come from the quality tier.

signal changed

const Tuning := preload("res://scripts/tuning.gd")
const Quality := preload("res://scripts/quality.gd")
const FACTORY_PATH: String = "res://scripts/buildings/building_factory.gd"
const CONFIG_PATH: String = "user://perf.cfg"

const SHADOW_CHOICES: Array[int] = [0, 1024, 2048]
const MSAA_CHOICES: Array[int] = [0, 2]
## 0.0 means automatic (dynamic resolution).
const SCALE_CHOICES: Array[float] = [0.0, 0.5, 0.6, 0.75, 1.0]
const FOLIAGE_CHOICES: Array[float] = [0.25, 0.5, 1.0]
const FPS_CHOICES: Array[int] = [30, 60]

var values: Dictionary = {}
var main: Node3D
var dynamic_scale: float = 0.6

var _frame_accum: float = 0.0
var _frame_count: int = 0
var _foliage_full: Dictionary = {}


func setup(p_main: Node3D) -> void:
	main = p_main
	add_to_group(&"perf_settings")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	values = _defaults()
	var shot_run: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_run = true
		if a == "--postfx=0":
			values["postfx"] = false
			values["dof"] = false
	# Screenshot runs ignore saved choices so validations stay deterministic.
	var cfg := ConfigFile.new()
	if not shot_run and cfg.load(CONFIG_PATH) == OK:
		for k: String in values.keys():
			values[k] = cfg.get_value("perf", k, values[k])
	dynamic_scale = Tuning.MOBILE_SCALE_3D if Quality.is_mobile() else 1.0
	_capture_foliage()
	apply_all.call_deferred()


func _defaults() -> Dictionary:
	var m: bool = Quality.is_mobile()
	return {
		"postfx": Tuning.MOBILE_POSTFX_ENABLED if m else Tuning.POSTFX_ENABLED,
		"dof": Tuning.MOBILE_DOF_ENABLED if m else true,
		"glow": Tuning.MOBILE_GLOW_ENABLED if m else Tuning.GLOW_ENABLED,
		"shadows": Tuning.MOBILE_SHADOW_SIZE if m else 4096,
		"msaa": 0 if m else 4,
		"scale": 0.0 if m else 1.0,
		"fog": true,
		"clouds": true,
		"night_lights": true,
		"water": true,
		"foliage": 1.0,
		"fps_cap": Tuning.MOBILE_FPS_CAP if m else 0,
	}


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	var cfg := ConfigFile.new()
	for k: String in values.keys():
		cfg.set_value("perf", k, values[k])
	cfg.save(CONFIG_PATH)
	apply_all()


func apply_all() -> void:
	var vp: Viewport = get_viewport()
	var post: CanvasLayer = main.get_node_or_null(^"PostFx")
	if post != null:
		post.visible = bool(values["postfx"])
	var rig: Node = get_tree().get_first_node_in_group(&"camera_rig")
	if rig != null:
		rig.set(&"_dof_on", bool(values["dof"]))
	var env_node: WorldEnvironment = main.get_node_or_null(^"WorldEnvironment")
	if env_node != null:
		env_node.environment.glow_enabled = bool(values["glow"])
	var shadow: int = int(values["shadows"])
	for light: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).shadow_enabled = shadow > 0
	if shadow > 0:
		RenderingServer.directional_shadow_atlas_set_size(shadow, true)
	var msaa: int = int(values["msaa"])
	vp.msaa_3d = Viewport.MSAA_DISABLED if msaa == 0 else (Viewport.MSAA_2X if msaa == 2 else Viewport.MSAA_4X)
	var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if forward_plus and _scale() < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _scale()
	for group: StringName in [&"fog_field", &"cloud_field"]:
		var on: bool = bool(values["fog" if group == &"fog_field" else "clouds"])
		for n: Node in get_tree().get_nodes_in_group(group):
			if n.has_method(&"set_enabled"):
				n.call(&"set_enabled", on)
			elif n is Node3D:
				(n as Node3D).visible = on
	var lights_on: bool = bool(values["night_lights"])
	if ResourceLoader.exists(FACTORY_PATH):
		var f: Resource = load(FACTORY_PATH)
		if f is GDScript and (f as GDScript).can_instantiate() and (f as GDScript).has_method(&"set_lights_enabled"):
			(f as GDScript).call(&"set_lights_enabled", get_tree(), lights_on)
	main.set(&"night_lights_enabled", lights_on)
	var dn: Node = main.get_node_or_null(^"DayNight")
	if dn != null and dn.has_method(&"refresh"):
		dn.call(&"refresh")
	var liquid: Node = get_tree().get_first_node_in_group(&"liquid_field")
	if liquid != null:
		liquid.process_mode = Node.PROCESS_MODE_INHERIT if bool(values["water"]) else Node.PROCESS_MODE_DISABLED
	_apply_foliage(float(values["foliage"]))
	Engine.max_fps = int(values["fps_cap"])
	changed.emit()


func _scale() -> float:
	var s: float = float(values["scale"])
	return dynamic_scale if s <= 0.0 else s


func _capture_foliage() -> void:
	var decor: Node = main.get_node_or_null(^"Decor")
	if decor == null:
		return
	for c: Node in decor.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null and not String(mmi.name).begins_with("Rocks") and mmi.name != &"LilyPads":
			_foliage_full[mmi] = mmi.multimesh.instance_count


func _apply_foliage(ratio: float) -> void:
	for mmi: MultiMeshInstance3D in _foliage_full.keys():
		if is_instance_valid(mmi):
			var full: int = _foliage_full[mmi]
			mmi.multimesh.visible_instance_count = -1 if ratio >= 0.999 else maxi(0, int(full * ratio))


func gpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func cpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()


func current_scale() -> float:
	return get_viewport().scaling_3d_scale


## Dynamic resolution: only on mobile with scale on "auto"; steps by DYNRES_STEP once per window.
func _process(delta: float) -> void:
	if not Quality.is_mobile() or float(values.get("scale", 1.0)) > 0.0:
		return
	_frame_accum += delta
	_frame_count += 1
	if _frame_accum < Tuning.DYNRES_WINDOW:
		return
	var ms: float = _frame_accum / _frame_count * 1000.0
	_frame_accum = 0.0
	_frame_count = 0
	var before: float = dynamic_scale
	if ms > Tuning.DYNRES_DOWN_ABOVE_MS:
		dynamic_scale = maxf(Tuning.DYNRES_MIN, dynamic_scale - Tuning.DYNRES_STEP)
	elif ms < Tuning.DYNRES_UP_BELOW_MS:
		dynamic_scale = minf(Tuning.DYNRES_MAX, dynamic_scale + Tuning.DYNRES_STEP)
	if not is_equal_approx(before, dynamic_scale):
		get_viewport().scaling_3d_scale = dynamic_scale
