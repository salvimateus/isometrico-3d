extends RefCounted

## Cost profile of the liquid system: "high" (desktop) or "mobile". Reads the WORLD's quality.gd when it
## exists; otherwise falls back to the platform feature or `--quality=mobile`. Values are fixed at first use.

const LT := preload("res://scripts/liquid/liquid_tuning.gd")
const QUALITY_PATH: String = "res://scripts/quality.gd"

static var _resolved: bool = false
static var _mobile: bool = false


static func is_mobile() -> bool:
	if not _resolved:
		_resolved = true
		if ResourceLoader.exists(QUALITY_PATH):
			var q: Script = load(QUALITY_PATH)
			var names: Dictionary = {}
			for m: Dictionary in q.get_script_method_list():
				names[StringName(m["name"])] = true
			if names.has(&"tier"):
				_mobile = StringName(q.call(&"tier")) == &"mobile"
			elif names.has(&"is_mobile"):
				_mobile = bool(q.call(&"is_mobile"))
		else:
			_mobile = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--quality=mobile")
	return _mobile


static func pick(high: Variant, mobile: Variant) -> Variant:
	return mobile if is_mobile() else high


static func sim_resolution() -> int:
	return pick(LT.SIM_RESOLUTION, LT.MOBILE_SIM_RESOLUTION)


static func surface_grid() -> int:
	return pick(LT.SURFACE_GRID, LT.MOBILE_SURFACE_GRID)


static func sim_hz() -> float:
	return pick(LT.SIM_HZ, LT.MOBILE_SIM_HZ)


static func calm_sim_hz() -> float:
	return pick(LT.CALM_SIM_HZ, LT.MOBILE_CALM_SIM_HZ)


static func max_steps() -> int:
	return pick(LT.SIM_MAX_STEPS_PER_FRAME, LT.MOBILE_SIM_MAX_STEPS_PER_FRAME)


static func droplet_amount() -> int:
	return pick(LT.DROPLET_AMOUNT, LT.MOBILE_DROPLET_AMOUNT)


static func fall_amount() -> int:
	return pick(LT.FALL_AMOUNT, LT.MOBILE_FALL_AMOUNT)


static func mist_amount() -> int:
	return pick(LT.MIST_AMOUNT, LT.MOBILE_MIST_AMOUNT)


static func fall_particles_per_unit() -> float:
	return pick(LT.FALL_PARTICLES_PER_UNIT, LT.MOBILE_FALL_PARTICLES_PER_UNIT)


static func jet_segments() -> int:
	return pick(LT.JET_SEGMENTS, LT.MOBILE_JET_SEGMENTS)


static func jet_sides() -> int:
	return pick(LT.JET_SIDES, LT.MOBILE_JET_SIDES)


static func water_fx_max_drops() -> int:
	return pick(LT.WATER_FX_MAX_DROPS, LT.MOBILE_WATER_FX_MAX_DROPS)


static func water_fx_mist_amount() -> int:
	return pick(LT.WATER_FX_MIST_AMOUNT, LT.MOBILE_WATER_FX_MIST_AMOUNT)


## Fall path sample stride: mobile keeps every 4th step instead of every 2nd (half the curtain triangles).
static func curtain_stride() -> int:
	return pick(2, 4)


static func splash_scale() -> float:
	return pick(1.0, LT.MOBILE_SPLASH_SCALE)


static var _lite_cache: Dictionary = {}


## Mobile: a copy of `shader` compiled with LITE (no screen-texture refraction, fewer octaves).
static func shader(base: Shader) -> Shader:
	if not is_mobile():
		return base
	if not _lite_cache.has(base):
		var lite := Shader.new()
		lite.code = base.code.replace("shader_type spatial;", "shader_type spatial;\n#define LITE")
		_lite_cache[base] = lite
	return _lite_cache[base]
