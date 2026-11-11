extends RefCounted

## Cost and look knobs for the volumetric clouds. Read-only constants, preload this script.

# --- Cost ---
const MAX_BLOBS: int = 12
const NOISE_SIZE: int = 64
const MAX_STEPS: int = 96
const STEP_LENGTH: float = 0.24
const LIGHT_STEPS: int = 5
const SHADOW_MAP_SIZE: int = 256
const LIGHT_NOISE: bool = true
const SHADOW_REFRESH: float = 0.0
const LOBE_NOISE: bool = true

# --- Mobile profile (Mobile renderer / quality tier "mobile") ---
const MOBILE_MAX_STEPS: int = 14
const MOBILE_STEP_LENGTH: float = 0.9
const MOBILE_LIGHT_STEPS: int = 1
# Envelope-only light march: no noise fetch per light sample.
const MOBILE_LIGHT_NOISE: bool = false
# Lobe normals from the sphere envelope only (no noise fetches).
const MOBILE_LOBE_NOISE: bool = false
const MOBILE_RING_LANES: PackedFloat32Array = [-26.0, 16.0, 30.0]
# The crosser is the worst-case cost (a cloud filling half the screen); off on mobile.
const MOBILE_CROSSER_ENABLED: bool = false
const MOBILE_SKY_COUNT: int = 4
const MOBILE_SHADOW_MAP_SIZE: int = 64
const MOBILE_SHADOW_REFRESH: float = 0.5

# --- Distribution ---
const SKY_COUNT: int = 22
const SKY_ALTITUDE_MIN: float = 11.0
const SKY_ALTITUDE_MAX: float = 18.0
const SKY_SIZE_MIN: float = 9.0
const SKY_SIZE_MAX: float = 15.0
const SKY_HEIGHT_RATIO_MIN: float = 0.36
const SKY_HEIGHT_RATIO_MAX: float = 0.44
# Lateral distance from the iso frame center that sky lanes keep clear (they live on the horizon).
const SKY_CLEAR_RADIUS: float = 36.0
const EDGE_FADE_DISTANCE: float = 22.0

# Ring: low diorama clouds on fixed lanes across the wind, framing the island in the iso view.
# Lanes are offsets from the island's on-screen center; the innermost ones brush the island edge.
const RING_LANES: PackedFloat32Array = [-34.0, -24.0, -15.0, 15.0, 24.0, 34.0]
const RING_LANE_JITTER: float = 3.0
const RING_HALF_SIZE: float = 42.0
const RING_EDGE_FADE_DISTANCE: float = 12.0
const RING_ALTITUDE_MIN: float = 6.5
const RING_ALTITUDE_MAX: float = 10.5
const RING_SIZE_MIN: float = 12.0
const RING_SIZE_MAX: float = 17.0
const RING_HEIGHT_RATIO_MIN: float = 0.28
const RING_HEIGHT_RATIO_MAX: float = 0.36

# Drifts away from the iso camera so ring lanes spread across the wide screen axis.
const WIND_DIRECTION: Vector2 = Vector2(-1.0, -0.8)
const WIND_SPEED: float = 1.1
const WIND_SPEED_JITTER: float = 0.2
const SPAWN_FADE_TIME: float = 6.0

# Crosser: sized and placed by the camera height so it reads as a cloud passing, not a wall.
const CROSSER_SIZE: float = 9.0
const CROSSER_HEIGHT_FRACTION: float = 0.3
const CROSSER_ALTITUDE_MIN: float = 6.0
const CROSSER_ALTITUDE_MAX: float = 14.0
const CROSSER_LATERAL_JITTER: float = 2.0
const CROSSER_INTERVAL: float = 38.0
const CROSSER_INTERVAL_JITTER: float = 14.0
const CROSSER_LEAD_DISTANCE: float = 30.0
const SUPPRESS_FADE_TIME: float = 0.6
const ENABLE_FADE_TIME: float = 0.6
# Island outline used by set_suppressed (superellipse centered at the origin).
const ISLAND_HALF_SIZE: float = 16.8
const ISLAND_SUPERELLIPSE_N: float = 4.2
const ISO_VIEW_DIR: Vector3 = Vector3(0.5, 0.7071, 0.5)
const ISO_REFERENCE_HEIGHT: float = 21.0

# --- Shape and motion ---
const DENSITY: float = 1.0
const ABSORPTION: float = 3.2
const SOFTNESS: float = 0.75
const EROSION: float = 1.1
const DETAIL_EROSION: float = 0.45
const NOISE_SCALE: float = 0.09
const DETAIL_SCALE: float = 0.21
const EVOLVE_SPEED: float = 0.3
const BREATHE_AMOUNT: float = 0.05
const BREATHE_SPEED: float = 0.12

# --- Lighting (day) ---
const SUN_COLOR: Color = Color(1.0, 0.93, 0.8)
const SUN_INTENSITY: float = 1.3
const TOP_COLOR: Color = Color(0.74, 0.8, 0.93)
const BASE_COLOR: Color = Color(0.46, 0.55, 0.74)
const RIM_COLOR: Color = Color(1.0, 0.97, 0.9)
const LIGHT_ABSORPTION: float = 1.5
const POWDER_STRENGTH: float = 0.55
const PHASE_FORWARD_G: float = 0.6
const PHASE_BACK_G: float = -0.2
const RIM_STRENGTH: float = 1.0
const LOBE_SHADING: float = 0.8
const LOBE_SHADOW_TINT: Color = Color(0.55, 0.63, 0.82)

# --- Lighting (night) ---
const NIGHT_SUN_COLOR: Color = Color(0.62, 0.71, 1.0)
const NIGHT_SUN_INTENSITY: float = 0.42
const NIGHT_TOP_COLOR: Color = Color(0.16, 0.21, 0.36)
const NIGHT_BASE_COLOR: Color = Color(0.05, 0.075, 0.14)
const NIGHT_RIM_COLOR: Color = Color(0.78, 0.85, 1.0)
const NIGHT_RIM_STRENGTH: float = 1.6
const NIGHT_LOBE_SHADOW_TINT: Color = Color(0.68, 0.72, 0.85)
const LIGHT_DIR_SMOOTHING: float = 3.0

# --- Veil (cloud between camera and game) ---
const NEAR_FADE_START: float = 1.5
const NEAR_FADE_END: float = 9.0
# Island rect whose ground counts as game content behind a cloud.
const CONTENT_RECT: Rect2 = Rect2(-17.0, -17.0, 34.0, 34.0)
const CONTENT_SOFT_EDGE: float = 8.0
# Optical depth scale with ground behind (1 = untouched) and over the island; thin parts clear first.
const VEIL_GROUND_DEPTH: float = 0.85
const VEIL_CONTENT_DEPTH: float = 0.45
const VEIL_CONTENT_CAP: float = 0.72
const VEIL_CENTER: float = 0.8
const VEIL_CENTER_RADIUS: float = 0.3
const VEIL_PLAYER: float = 0.3
const VEIL_PLAYER_RADIUS: float = 0.13
const VEIL_EDGE_NOISE: float = 0.9

# --- Ground shadows ---
const SHADOW_SOFTNESS: float = 1.35
