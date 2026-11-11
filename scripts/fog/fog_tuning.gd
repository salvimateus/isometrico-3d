extends RefCounted

## Central knobs for the ground fog: GPU cost first, then feel. Read-only constants, preload this script.

# --- Simulation cost ---
const SIM_RESOLUTION: int = 256 # cells along the longer side of the area
const SIM_HZ: float = 60.0 # fixed timestep, decoupled from framerate
const SIM_MAX_STEPS_PER_FRAME: int = 3
const PRESSURE_ITERATIONS: int = 30 # Jacobi iterations, rounded up to even
const MAX_SPLATS_PER_STEP: int = 64

# --- Local lights in the fog (lanterns, windows): up to 8 nearest OmniLight3D ---
const FOG_LIGHTS_MAX: int = 8
const FOG_LIGHT_GAIN: float = 0.3 # warm glow strength of a light inside the fog
const FOG_LIGHT_RANGE_SCALE: float = 0.6 # fraction of the light's own range that lights the fog
const FOG_LIGHT_REFRESH: float = 0.25 # s between nearest-light picks
const FOG_LIGHT_SCAN: float = 2.0 # s between scene scans for OmniLight3D nodes

# --- Mobile profile (tier &"mobile" from res://scripts/quality.gd, or --quality=mobile) ---
const MOBILE_SIM_RESOLUTION: int = 80
const MOBILE_SIM_HZ: float = 20.0
const MOBILE_PRESSURE_ITERATIONS: int = 14
const MOBILE_MARCH_STEPS_MIN: int = 4
const MOBILE_MARCH_STEPS_MAX: int = 8
const MOBILE_MARCH_STEP_LENGTH: float = 0.3
const MOBILE_HIGH_LIGHTING: bool = false # skips the self-shadow probe and obstacle shafts
const MOBILE_NIGHT_STEPS_MAX: int = 6 # night fog is denser and saturates sooner: fewer steps keep night cost at day level

# --- Render cost ---
const MARCH_STEPS_MIN: int = 14
const MARCH_STEPS_MAX: int = 40
const MARCH_STEP_LENGTH: float = 0.12 # target world length per step before clamping the count
const MARCH_MAX_DISTANCE: float = 60.0 # ray length cap inside the fog slab (grazing third-person views)
const NOISE_TEXTURE_SIZE: int = 256
const TOGGLE_FADE_TIME: float = 0.5 # set_enabled fade, seconds
const CAMERA_CLEAR_NEAR: float = 0.35 # fog fades out this close to the camera (no white-out inside it)
const CAMERA_CLEAR_FAR: float = 2.0 # shoulder camera sits ~1.6 behind the runner, where the plume rises
# Grazing views (shoulder camera): fog thins with distance and accumulated opacity is capped,
# so far banks read as layers instead of a solid wall. Iso rays (|dir.y| ~0.7) are unaffected.
const GRAZING_DIR_Y_MIN: float = 0.12 # |ray dir y| at or below this counts as fully grazing
const GRAZING_DIR_Y_MAX: float = 0.42 # above this the ray is not grazing
const GRAZING_FADE_NEAR: float = 3.0
const GRAZING_FADE_FAR: float = 26.0
const GRAZING_FAR_DENSITY: float = 0.28 # density multiplier at GRAZING_FADE_FAR
const GRAZING_MAX_ALPHA: float = 0.65

# --- Shape ---
const FOG_HEIGHT: float = 0.34 # calm top on thick fog; wisp peaks reach ~0.45
const FOG_BOX_HEIGHT: float = 1.9 # render ceiling: calm top + LIFT_MAX # render volume ceiling, leaves room for lifted fog
const FOG_TOP_MIN: float = 0.3 # top height ratio at zero density (keeps a thin floor layer)
const FOG_TOP_SOFTNESS: float = 0.55 # fraction of the top where density fades out
const FOG_EXTINCTION: float = 3.4 # optical density per unit length at density 1
const FOG_EDGE_FADE: float = 2.2 # world units of fade at the area border
const WISP_SCALE: float = 0.6 # noise frequency per world unit for the advected wisps
const WISP_STRENGTH: float = 0.7
const TOP_NOISE_SCALE: float = 0.16
const TOP_NOISE_STRENGTH: float = 0.38
const BILLOW_SHADING: float = 0.3 # day: brightness swing between swell crests and troughs
const NIGHT_BILLOW_SHADING: float = 0.55
const FLOW_PERIOD: float = 1.7 # seconds per flow-map phase (two phases offset by half)

# --- Look ---
const SUN_FALLBACK_DIR: Vector3 = Vector3(-0.85, 1.05, 0.38) # toward the sun, used without a DirectionalLight3D
const SUN_FALLBACK_COLOR: Color = Color("FFF0D2")
const SUN_SCATTER: float = 1.45 # lit tops land near luminous warm white after ACES
const FOG_TOP_COLOR: Color = Color("FFF4E2")
const FOG_SHADOW_COLOR: Color = Color("A8C4EE")
const FOG_AMBIENT: float = 0.56
const SELF_SHADOW: float = 1.7
const DENSITY_CONTRAST: float = 2.0 # >1 makes thick patches puffier and thin areas clearer
const LIGHT_PROBE: float = 0.35 # world distance of the self-shadow probe toward the light
const OBSTACLE_SHADOW_HEIGHT: float = 2.6 # assumed height of masked obstacles for shadows in the fog
const OBSTACLE_SHADOW: float = 0.5
const FORWARD_SCATTER: float = 0.35

# --- Ambient behavior ---
# Base map value is the density fraction of BASE_DENSITY_MAX (no floor): 0 = clear, 1 = thickest.
const PATCH_AMOUNT: float = 0.3 # drifting sparse wisps added where the map is thin (scaled by 1 - map)
const PATCH_FREQUENCY: float = 0.35 # per world unit
const PATCH_SPEED: float = 0.12
const BASE_DENSITY_MAX: float = 1.15
const BASE_NOISE_FREQUENCY: float = 0.09 # per world unit, internal base map without a mask
const REGEN_RATE: float = 0.3 # 1/s pull of density back to the base map
const WIND: Vector2 = Vector2(0.16, 0.05) # world units/s in XZ
const AMBIENT_COUPLING: float = 0.45 # 1/s pull of velocity back to ambient wind + drift
const DRIFT_STRENGTH: float = 0.22 # slow curl-noise eddies, world units/s
const DRIFT_FREQUENCY: float = 0.12
const DRIFT_SPEED: float = 0.05
const VORTICITY: float = 1.3 # vorticity confinement epsilon

# --- Interaction ---
const IMPULSE_COUPLING: float = 0.55 # how hard the body drags fog toward its velocity (per step, at core)
const IMPULSE_CARVE: float = 0.14 # density removed per step at the body core
const IMPULSE_PUSH: float = 0.35 # extra forward bow push as a fraction of body velocity
const BURST_SOURCE: float = 20.0 # divergence source per unit strength
const BURST_RADIAL: float = 2.6 # direct radial velocity kick per unit strength
const BURST_SWIRL: float = 1.2 # tangential noise in the ring per unit strength
const BURST_CARVE: float = 0.9 # density carved from the center per unit strength
const BURST_RING_GAIN: float = 0.7 # carved density redeposited on the rim
const BURST_LIFT: float = 0.6 # extra density on the rim that also raises the top
const SOURCE_DECAY: float = 6.0 # 1/s decay of the divergence source
const RECOIL_DELAY: float = 0.32 # s after a burst until the inward recoil
const RECOIL_RATIO: float = 0.4 # recoil strength as fraction of the burst
const RECOIL_RADIUS_SCALE: float = 1.9

# --- Lift (interaction throws fog upward; ballistic with soft gravity) ---
const LIFT_GRAVITY: float = 4.6 # world units/s^2 pulling lifted fog back down
const LIFT_DRAG: float = 0.4 # 1/s damping of the vertical velocity
const LIFT_DECAY: float = 0.15 # 1/s slow height relaxation on top of gravity
const LIFT_MAX: float = 1.3
const LIFT_RUN_VELOCITY: float = 2.8 # upward velocity behind a full-speed run (plume peak ~0.85)
const LIFT_BURST_VELOCITY: float = 2.9 # upward kick of the burst rim per sqrt(strength) (landing peak ~1.1)
const LIFT_BURST_CORE: float = 0.35 # fraction of the rim kick also given to the burst center
const LIFT_DENSITY: float = 0.25 # extra density per unit of lift so plumes read as substance
const LIFT_SPREAD: float = 0.75 # 0..1: how much a lifted column thins (mass spread over its new height)
const LIFT_FLOOR_GAP: float = 0.3 # lifted fog leaves this fraction of its lift as a thinner gap below

# --- Agitator (helper that drives the API from a CharacterBody3D) ---
const AGITATE_RADIUS_WALK: float = 0.38
const AGITATE_RADIUS_RUN: float = 0.5
const AGITATE_MAX_HEIGHT: float = 1.0 # body feet above this height stop touching fog
const AGITATE_WALK_GAIN: float = 0.4
const AGITATE_RUN_SPEED: float = 3.6 # speed considered a full run
const AGITATE_SIDE_KICK: float = 0.55 # alternating lateral push while running, fraction of speed
const AGITATE_SIDE_FREQUENCY: float = 2.6 # Hz of the alternating lateral push
const AGITATE_SIDE_OFFSET: float = 0.42
const TAKEOFF_STRENGTH: float = 0.35
const TAKEOFF_RADIUS: float = 0.6
const LANDING_STRENGTH_MIN: float = 0.6
const LANDING_STRENGTH_MAX: float = 1.5
const LANDING_FALL_SPEED_FULL: float = 7.0
const LANDING_RADIUS: float = 1.1
const LANDING_MIN_AIR_TIME: float = 0.15 # ignore floor flicker and spawn settling

# --- Night (set_night(amount) blends day -> night) ---
const NIGHT_DENSITY_SCALE: float = 1.35
const NIGHT_HEIGHT_SCALE: float = 1.08 # night is denser, not taller: top ~0.4, peaks ~0.55
const NIGHT_VILLAGE_FLOOR: float = 0.8 # base fraction the whole ground reaches at full night (near forest density)
const NIGHT_FLOOR_VARIATION: float = 0.55 # how much thinner the night floor gets on drifting rises (0 = uniform)
const NIGHT_FRONT_OVERSHOOT: float = 0.25 # how far past the clearest area the night front sweeps at night = 1
const NIGHT_REACH_BLUR: int = 12 # base map downscale factor for the reach map (bigger = wider, softer front)
const NIGHT_PATCH_AMOUNT: float = 0.45
const NIGHT_BASE_MAX: float = 1.3
const NIGHT_REGEN_RATE: float = 0.32 # also how slowly the trail behind the viking closes at night
const NIGHT_DRIFT_SCALE: float = 0.45 # wind and eddies slow down
const NIGHT_MOON_COLOR: Color = Color("9DB4FF")
const NIGHT_MOON_ENERGY: float = 0.55 # scatter brightness of the moonlight in the fog
const NIGHT_SUN_SCATTER: float = 1.5
const NIGHT_SELF_SHADOW: float = 1.5
const NIGHT_TOP_COLOR: Color = Color("93A8D2") # moonlit silver-blue tops
const NIGHT_SHADOW_COLOR: Color = Color("1C2440")
const NIGHT_AMBIENT: float = 0.4
const NIGHT_FORWARD_SCATTER: float = 1.4 # stronger halo toward the moon reads as light shafts
const NIGHT_OBSTACLE_SHADOW: float = 0.92
