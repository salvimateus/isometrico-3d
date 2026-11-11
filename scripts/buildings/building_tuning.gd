extends RefCounted
## GPU-cost and idle-animation knobs for every building.

const QUALITY_SCRIPT: String = "res://scripts/quality.gd"

## Mobile tier, read once: the WORLD's quality.gd when present, otherwise the Mobile renderer,
## the `mobile` OS feature or `--quality=mobile` on the command line.
static var MOBILE: bool = _detect_mobile()

# Geometry density (lower on mobile, same toy silhouette)
static var BEVEL_SEGMENTS: int = 2 if MOBILE else 3
static var CYLINDER_SIDES: int = 18 if MOBILE else 32
static var CYLINDER_SIDES_SMALL: int = 10 if MOBILE else 14
static var SPHERE_SIDES: int = 16 if MOBILE else 32
static var SPHERE_RINGS: int = 10 if MOBILE else 18

# Particles
static var SMOKE_AMOUNT: int = 5 if MOBILE else 9
static var SMOKE_AMOUNT_SMALL: int = 3 if MOBILE else 6
const SMOKE_LIFETIME: float = 3.2
static var BUBBLE_AMOUNT: int = 7 if MOBILE else 14
const BUBBLE_LIFETIME: float = 1.6

# Emission
const EMISSION_WINDOW: float = 2.6
const EMISSION_MANA: float = 1.25
const EMISSION_MANA_CRYSTAL: float = 1.6
const EMISSION_LANTERN: float = 3.0
const EMISSION_GOLD: float = 0.12

# Night mode (amount 0 = day, 1 = night)
## Mobile has no projected night lights, so emission works harder there.
static var NIGHT_WINDOW_EMISSION: float = 3.0 if MOBILE else 2.3
const NIGHT_WINDOW_COLOR: Color = Color(1.0, 0.46, 0.12)
const DAY_LANTERN_EMISSION: float = 1.2
static var NIGHT_LANTERN_EMISSION: float = 4.2 if MOBILE else 2.8
static var NIGHT_MANA_MULTIPLIER: float = 2.6 if MOBILE else 2.1
const NIGHT_LIGHT_ENERGY: float = 0.9
const NIGHT_LIGHT_RANGE: float = 2.6
const NIGHT_LIGHT_COLOR: Color = Color(1.0, 0.72, 0.38)
const NIGHT_LIGHT_THRESHOLD_MIN: float = 0.25
const NIGHT_LIGHT_THRESHOLD_MAX: float = 0.85
const NIGHT_LIGHT_FLICKER: float = 0.12
const NIGHT_LIGHT_POP_TIME: float = 0.35

# Lights (one small omni per mana building)
## Mobile builds no OmniLight3D at all (lanterns and mana).
static var USE_OMNI_LIGHTS: bool = not MOBILE
## Runtime switch for every building light (performance panel); see building_factory.set_lights_enabled.
static var lights_enabled: bool = true
## Mobile stand-in for lamp light: additive halo size and night strength.
const HALO_SIZE: float = 1.1
const HALO_NIGHT_INTENSITY: float = 0.55
const MANA_LIGHT_GROUP: StringName = &"building_mana_lights"
const MANA_LIGHT_ENERGY: float = 1.1
const MANA_LIGHT_RANGE: float = 2.4

# Idle animation
const MANA_PULSE_SPEED: float = 1.7
const MANA_RIPPLE: float = 0.025
const FLAG_WAVE_SPEED: float = 4.0
const FLAG_WAVE_AMPLITUDE: float = 0.07
const WHEEL_SPEED: float = 0.9
const GEAR_SPEED: float = 1.6
const PISTON_SPEED: float = 2.2
const PISTON_TRAVEL: float = 0.12
const CANNON_TURN_SPEED: float = 0.7
const CANNON_PAUSE_MIN: float = 1.2
const CANNON_PAUSE_MAX: float = 3.2
const CANNON_ARC_DEG: float = 70.0
const SIGN_SWAY_DEG: float = 6.0
const SIGN_SWAY_SPEED: float = 1.4
const GOLD_SPARKLE_SPEED: float = 1.2


static func _detect_mobile() -> bool:
	if ResourceLoader.exists(QUALITY_SCRIPT):
		var q := load(QUALITY_SCRIPT) as Script
		if q != null:
			for m: Dictionary in q.get_script_method_list():
				if m.get("name") == "is_mobile":
					return bool(q.call(&"is_mobile"))
	if OS.get_cmdline_user_args().has("--quality=mobile"):
		return true
	if OS.has_feature("mobile"):
		return true
	return RenderingServer.get_current_rendering_method() == "mobile"
