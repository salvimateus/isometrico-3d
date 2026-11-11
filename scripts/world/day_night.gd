extends Node

## Day/night cycle toggled by Left arrow / D-pad left. Blends sun, moon, ambient, exposure, glow,
## fog, sky, water and ambient life, and drives optional set_night() hooks of BUILDINGS and FOG.

const Tuning := preload("res://scripts/tuning.gd")
const Quality := preload("res://scripts/quality.gd")
const FACTORY_PATH: String = "res://scripts/buildings/building_factory.gd"
const WATER_FX_PATH: String = "res://scripts/liquid/water_fx.gd"

var amount: float = 0.0

var _env: Environment
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _water: Array[ShaderMaterial] = []
var _life: Array[GPUParticles3D] = []
var _day: Dictionary = {}
var _target: float = 0.0
var _tween: Tween
var _factory: Script = null
var _factory_checked: bool = false


func setup(world_env: WorldEnvironment, sun: DirectionalLight3D, water: Array[ShaderMaterial], life: Array[GPUParticles3D]) -> void:
	_env = world_env.environment
	_sun = sun
	_water = water
	_life = life
	_day = {
		"sun_energy": sun.light_energy,
		"sun_color": sun.light_color,
		"sun_basis": sun.global_basis,
		"ambient_energy": _env.ambient_light_energy,
		"ambient_sky": _env.ambient_light_sky_contribution,
		"ambient_color": _env.ambient_light_color,
		"exposure": _env.tonemap_exposure,
		"glow_intensity": _env.glow_intensity,
		"glow_threshold": _env.glow_hdr_threshold,
		"fog_color": _env.fog_light_color,
		"saturation": _env.adjustment_saturation,
	}
	var sky_mat: Material = _env.sky.sky_material if _env.sky != null else null
	if sky_mat is ProceduralSkyMaterial:
		var p := sky_mat as ProceduralSkyMaterial
		_day["sky_top"] = p.sky_top_color
		_day["sky_horizon"] = p.sky_horizon_color
		_day["ground_bottom"] = p.ground_bottom_color
		_day["ground_horizon"] = p.ground_horizon_color
		_day["sky_energy"] = p.sky_energy_multiplier
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Tuning.NIGHT_MOON_COLOR
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.shadow_blur = Tuning.SHADOW_BLUR * 1.6
	_moon.light_angular_distance = Tuning.SUN_ANGULAR_SIZE_DEG * 2.0
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_moon.directional_shadow_max_distance = Tuning.SHADOW_MAX_DISTANCE
	_moon.shadow_normal_bias = 1.2
	_moon.visible = false
	# Mobile: a single directional light that turns into the moon (no second shadow pass).
	if Quality.is_mobile():
		_moon.free()
		_moon = null
	else:
		sun.get_parent().add_child(_moon)


func toggle() -> void:
	set_night(_target < 0.5, false)


func set_night(on: bool, instant: bool) -> void:
	_target = 1.0 if on else 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	if instant:
		_apply(_target)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, amount, _target, Tuning.NIGHT_TRANSITION_TIME * absf(_target - amount)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_LEFT:
		pressed = true
	elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_LEFT:
		pressed = true
	if pressed:
		toggle()
		get_viewport().set_input_as_handled()


func _apply(t: float) -> void:
	amount = t
	var sun_fade: float = 1.0 - smoothstep(0.0, 0.6, t)
	var moon_rise: float = smoothstep(0.35, 1.0, t)
	var day_basis: Basis = _day["sun_basis"]
	var moon_dir: Vector3 = Tuning.NIGHT_MOON_DIRECTION.normalized()
	var rise_dir: Vector3 = moon_dir.lerp(Vector3(moon_dir.x, -0.15, moon_dir.z), 1.0 - moon_rise).normalized()
	if _moon != null:
		_sun.global_basis = Basis(Vector3(0, 0, 1).rotated(Vector3.UP, 0.6), deg_to_rad(Tuning.NIGHT_SUN_SINK_DEG) * t) * day_basis
		_sun.light_energy = float(_day["sun_energy"]) * sun_fade
		_sun.visible = sun_fade > 0.001
		_moon.look_at_from_position(rise_dir * 30.0, Vector3.ZERO, Vector3.UP if absf(rise_dir.y) < 0.99 else Vector3.FORWARD)
		_moon.light_energy = Tuning.NIGHT_MOON_ENERGY * moon_rise
		_moon.visible = moon_rise > 0.001
	else:
		var day_q: Quaternion = day_basis.get_rotation_quaternion()
		var night_q: Quaternion = Basis.looking_at(-moon_dir, Vector3.UP).get_rotation_quaternion()
		_sun.global_basis = Basis(day_q.slerp(night_q, smoothstep(0.0, 1.0, t)))
		_sun.light_color = (_day["sun_color"] as Color).lerp(Tuning.NIGHT_MOON_COLOR, smoothstep(0.2, 0.8, t))
		_sun.light_energy = lerpf(float(_day["sun_energy"]), Tuning.NIGHT_MOON_ENERGY, smoothstep(0.0, 1.0, t)) * (1.0 - 0.6 * sin(PI * t))
		_sun.visible = true

	_env.ambient_light_color = (_day["ambient_color"] as Color).lerp(Tuning.NIGHT_AMBIENT_COLOR, t)
	_env.ambient_light_sky_contribution = lerpf(_day["ambient_sky"], Tuning.NIGHT_AMBIENT_SKY_CONTRIBUTION, t)
	_env.ambient_light_energy = lerpf(_day["ambient_energy"], Tuning.NIGHT_AMBIENT_ENERGY, t)
	_env.tonemap_exposure = lerpf(_day["exposure"], Tuning.NIGHT_EXPOSURE, t)
	_env.glow_intensity = lerpf(_day["glow_intensity"], Tuning.NIGHT_GLOW_INTENSITY, t)
	_env.glow_hdr_threshold = lerpf(_day["glow_threshold"], Tuning.NIGHT_GLOW_THRESHOLD, t)
	_env.fog_light_color = (_day["fog_color"] as Color).lerp(Tuning.NIGHT_FOG_COLOR, t)
	_env.adjustment_saturation = lerpf(_day["saturation"], Tuning.NIGHT_SATURATION, t)

	var sky_mat: Material = _env.sky.sky_material if _env.sky != null else null
	if sky_mat is ShaderMaterial:
		(sky_mat as ShaderMaterial).set_shader_parameter(&"night", t)
		(sky_mat as ShaderMaterial).set_shader_parameter(&"moon_direction", moon_dir)
	elif sky_mat is ProceduralSkyMaterial:
		var p := sky_mat as ProceduralSkyMaterial
		p.sky_top_color = (_day["sky_top"] as Color).lerp(Tuning.NIGHT_SKY_TOP, t)
		p.sky_horizon_color = (_day["sky_horizon"] as Color).lerp(Tuning.NIGHT_SKY_HORIZON, t)
		p.ground_horizon_color = (_day["ground_horizon"] as Color).lerp(Tuning.NIGHT_SKY_HORIZON, t)
		p.ground_bottom_color = (_day["ground_bottom"] as Color).lerp(Tuning.NIGHT_SKY_TOP, t)

	RenderingServer.global_shader_parameter_set(&"night_amount", t)
	for m: ShaderMaterial in _water:
		m.set_shader_parameter(&"night", t)
	for p: GPUParticles3D in _life:
		p.amount_ratio = 1.0 - smoothstep(0.0, 0.5, t)
		p.visible = p.amount_ratio > 0.01

	var lit: float = smoothstep(0.3, 0.9, t)
	var allow: bool = bool(get_parent().get(&"night_lights_enabled")) and (Tuning.MOBILE_NIGHT_OMNI_LIGHTS or not Quality.is_mobile())
	for node: Node in get_tree().get_nodes_in_group(&"night_lights"):
		var light := node as Light3D
		light.light_energy = float(light.get_meta(&"night_energy", 1.0)) * lit
		light.visible = allow and lit > 0.01
	_call_hooks(t)


func _call_hooks(t: float) -> void:
	if not _factory_checked:
		_factory_checked = true
		if ResourceLoader.exists(FACTORY_PATH):
			var s: Resource = load(FACTORY_PATH)
			if s is GDScript and (s as GDScript).can_instantiate():
				for m: Dictionary in (s as GDScript).get_script_method_list():
					if m["name"] == "set_night":
						_factory = s
						break
	if _factory != null:
		_factory.call(&"set_night", get_tree(), t)
	if ResourceLoader.exists(WATER_FX_PATH):
		var wfx: Resource = load(WATER_FX_PATH)
		if wfx is GDScript and (wfx as GDScript).can_instantiate():
			var node: Variant = (wfx as GDScript).call(&"get_or_create", get_tree())
			if node is Object and (node as Object).has_method(&"set_night"):
				(node as Object).call(&"set_night", t)
	for group: StringName in [&"fog_field", &"cloud_field", &"liquid_field"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node.has_method(&"set_night"):
				node.call(&"set_night", t)


## Re-applies the current amount (after perf settings change).
func refresh() -> void:
	_apply(amount)
