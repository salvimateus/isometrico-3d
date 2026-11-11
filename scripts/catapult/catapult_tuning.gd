extends RefCounted

## Every time, force, height and UI size of the catapult ride.

# --- Contracts ---
const PLAYER_GROUP: StringName = &"player"
const CAMERA_GROUP: StringName = &"camera_rig"
const FOG_GROUP: StringName = &"fog_field"
const LIQUID_GROUP: StringName = &"liquid_field"
const INTERACT_ACTION: StringName = &"player_interact"
const SFX_PATH: String = "res://scripts/audio/sfx.gd"
const BUILDING_FACTORY_PATH: String = "res://scripts/buildings/building_factory.gd"
const GROUND_LAYER: int = 1
const OBSTACLE_LAYER: int = 2
const PLAYER_LOOKUP_INTERVAL: float = 0.5
const DEFAULT_FOOTPRINT: Vector2 = Vector2(3.0, 3.0)
const DEFAULT_FIRE_ANGLE_DEG: float = 115.0
const DEFAULT_GRAVITY: float = 15.0

# --- Mount ---
const PROMPT_RANGE: float = 1.6
const CLICK_MOUNT_RANGE: float = 8.0
const MOUNT_SETTLE_MAX: float = 0.9
const MOUNT_SETTLE_MIN: float = 0.3
const MOUNT_SETTLE_DISTANCE: float = 0.2
const BUCKET_JUMP_RADIUS: float = 0.85
const BUCKET_JUMP_BELOW: float = 0.45
const BUCKET_JUMP_ABOVE: float = 1.3
const MOUNT_DIP_IMPULSE: float = -2.6
const BUCKET_SQUASH: float = 0.32
const BUCKET_SQUASH_DECAY: float = 7.0
const BUCKET_SQUASH_FREQ: float = 22.0

# --- Arm spring (rest / mount / tension) ---
const ARM_STIFFNESS: float = 260.0
const ARM_DAMPING: float = 9.0
const TENSION_PULL_DEG: float = -4.5
const TREMBLE_DEG_MIN: float = 0.15
const TREMBLE_DEG_MAX: float = 1.8
const TREMBLE_FREQ_MIN: float = 18.0
const TREMBLE_FREQ_MAX: float = 34.0

# --- Countdown ---
const COUNTDOWN_STEPS: int = 3
const COUNTDOWN_STEP_TIME: float = 1.0
const GO_TEXT: String = "VAI!"
const WINCH_SPEED_START: float = 9.0
const WINCH_SPEED_END: float = 4.0
const CREAK_DB_START: float = -20.0
const CREAK_DB_END: float = -4.0
const DUST_INTERVAL_START: float = 0.32
const DUST_INTERVAL_END: float = 0.07
const TRAUMA_RATE_START: float = 0.06
const TRAUMA_RATE_END: float = 0.5
const TRAUMA_TICK: float = 0.06
const RUMBLE_TICK: Vector3 = Vector3(0.25, 0.08, 0.09)
const RUMBLE_TICK_GROWTH: float = 0.25
const SFX_TICK_DB: float = -3.0
const SFX_TICK_PITCH_STEP: float = 0.12
const SFX_GO_DB: float = 0.0

# --- Countdown visuals (Label3D billboard at CountdownAnchor) ---
const NUMBER_FONT_SIZE: int = 220
const NUMBER_PIXEL_SIZE: float = 0.011
const NUMBER_OUTLINE: int = 46
const NUMBER_OUTLINE_COLOR: Color = Color(0.06, 0.05, 0.12, 1.0)
const NUMBER_COLORS: Array[Color] = [Color("FFFFFF"), Color("FFD23C"), Color("FF4A2E")]
const GO_COLOR: Color = Color("8CFF3C")
const GO_SCALE: float = 1.25
const POP_FROM: float = 2.1
const POP_DECAY: float = 7.5
const POP_FREQ: float = 17.0
const SQUEEZE_OUT_TIME: float = 0.16
const BURST_SIZE: float = 3.6
const BURST_TIME: float = 0.35
const GO_HOLD: float = 0.5
# Labels go through the tonemapper; lift them so white reads as white.
const LABEL_HDR_BOOST: float = 1.35

# --- Prompt bubble ---
const PROMPT_TEXT: String = "X / E"
# Touch prompt: pointing-hand emoji when the font has it, else the word.
const PROMPT_TOUCH_GLYPH: int = 0x1F446
const PROMPT_TOUCH_FALLBACK: String = "TOQUE"
const PROMPT_TOUCH_FONT_SIZE: int = 96
const HAPTICS_PATH: String = "res://scripts/input/haptics.gd"
const QUALITY_PATH: String = "res://scripts/quality.gd"
const PROMPT_HEIGHT_OFFSET: float = -0.4
const NUMBER_HEIGHT_OFFSET: float = 0.9
const PROMPT_SIZE: Vector2 = Vector2(2.3, 1.2)
const PROMPT_FONT_SIZE: int = 110
const PROMPT_PIXEL_SIZE: float = 0.0064
const PROMPT_OUTLINE: int = 24
const PROMPT_BOB_HEIGHT: float = 0.12
const PROMPT_BOB_FREQ: float = 3.2
const PROMPT_POP_IN: float = 0.32
const PROMPT_POP_OUT: float = 0.14
const PROMPT_FILL: Color = Color(0.08, 0.1, 0.18, 0.78)
const PROMPT_BORDER: Color = Color(1.0, 1.0, 1.0, 0.85)
const PROMPT_ACCENT: Color = Color("FFC93C")

# --- Fire ---
const FIRE_ACCEL: float = 70.0
const FIRE_STOP_STIFFNESS: float = 1500.0
const FIRE_STOP_DAMPING: float = 11.0
const RELEASE_FRACTION: float = 0.82
const FIRE_HOLD: float = 0.9
const WINCH_UNSPOOL_SPEED: float = -38.0
const WINCH_UNSPOOL_DECAY: float = 3.5
const TRAUMA_FIRE: float = 0.75
const RUMBLE_FIRE: Vector3 = Vector3(1.0, 1.0, 0.45)
const SFX_FIRE_DB: float = 0.0
const CREAK_STOP_FADE: float = 0.12

# --- Ballistics ---
const LAUNCH_DISTANCE_MIN: float = 17.0
const LAUNCH_DISTANCE_MAX: float = 23.0
const LAUNCH_YAW_JITTER_DEG: float = 7.0
const APEX_MIN: float = 10.0
const APEX_MAX: float = 14.0
const FLIGHT_TIME_TARGET: float = 3.0
const FLIGHT_TIME_MIN: float = 2.5
const FLIGHT_TIME_MAX: float = 3.5
const APEX_SEARCH_MAX: float = 80.0
# Water target: Marker3D in this group at the pond's deepest point, meta `radius` = safe landing radius.
const TARGET_GROUP: StringName = &"catapult_target"
const TARGET_DEFAULT_RADIUS: float = 1.5
const TARGET_JITTER_FRACTION: float = 0.6
const LANDING_CLEAR_RADIUS: float = 1.3
const LANDING_EDGE_MARGIN: float = 1.2
const LANDING_RAY_HEIGHT: float = 40.0
const LANDING_RAY_DEPTH: float = 6.0
const LANDING_MIN_GROUND_Y: float = -2.0
const LANDING_MIN_DISTANCE: float = 7.0
const LANDING_SEARCH_STEP: float = 0.7
const LANDING_SEARCH_RADIUS: float = 14.0
const LANDING_TIMEOUT_EXTRA: float = 3.0

# --- Flight FX ---
const TRAIL_POINTS: int = 26
const TRAIL_LIFETIME: float = 0.42
const TRAIL_WIDTH: float = 0.55
const TRAIL_HEIGHT: float = 0.55
const TRAIL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const STREAK_AMOUNT: int = 40
const STREAK_LIFETIME: float = 0.45
const PUFF_INTERVAL: float = 0.06
const RING_RADIUS_START: float = 2.4
const RING_RADIUS_END: float = 0.9
const RING_BLINK_START: float = 3.0
const RING_BLINK_END: float = 11.0
const RING_COLOR: Color = Color("FFD23C")
const RING_LIFT: float = 0.04

# --- Landing ---
const FOG_BURST_STRENGTH: float = 1.8
const FOG_BURST_RADIUS: float = 4.5
const LAND_DUST_COUNT: int = 46
const LAND_SHOCKWAVE_RADIUS: float = 4.2
const LAND_SHOCKWAVE_TIME: float = 0.55
# Water landing: no dust; a white-blue ring hugging the surface plus spray.
const WATER_GROUP: StringName = &"water_body"
const WATER_MIN_DEPTH: float = 0.05
const WATER_RING_COLOR: Color = Color(0.86, 0.95, 1.0, 0.9)
const WATER_RING_LIFT: float = 0.03
const SPRAY_COLOR: Color = Color(0.85, 0.95, 1.0, 0.95)
const SPRAY_COUNT: int = 40
const SPRAY_SPEED_MIN: float = 3.0
const SPRAY_SPEED_MAX: float = 6.5
const SPRAY_SIZE: float = 0.14
const SPRAY_LIFETIME: float = 0.9

# --- Rearm ---
const REARM_TIME: float = 3.0
const REARM_WINCH_SPEED: float = -7.0
const REARM_CREAK_DB: float = -14.0
const REARM_SETTLE_IMPULSE: float = 1.6

# --- Load-time prewarm ---
const PREWARM_DEPTH: float = 3.0
const PREWARM_FRAMES: int = 3

# --- Dust ---
const DUST_COLOR: Color = Color("E3CB9C")
const DUST_POOL: int = 12
const DUST_LIFETIME: float = 0.8
const DUST_SIZE: float = 0.32

# --- SFX ---
const SFX_CREAK_LOOP: StringName = &"rope_creak"
# Synthesized on attach so the ride never stalls on first use (CHARACTER ones included).
const SFX_WARM: Array[StringName] = [
	&"countdown_tick", &"countdown_go", &"rope_creak", &"catapult_fire",
	&"viking_scream", &"impact_heavy", &"dizzy_tweet", &"ui_pop", &"thud",
]
