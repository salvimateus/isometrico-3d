extends RefCounted

## Central knobs for GPU cost and game feel. Read-only constants, preload this script.

# --- Rendering cost ---
const SHADOW_MAX_DISTANCE: float = 110.0
const SHADOW_BLUR: float = 1.4
const SUN_ANGULAR_SIZE_DEG: float = 1.2
const SSAO_ENABLED: bool = true
const SSAO_RADIUS: float = 1.1
const SSAO_INTENSITY: float = 1.6
const SSAO_POWER: float = 1.6
const SSIL_ENABLED: bool = false
const GLOW_ENABLED: bool = true
const GLOW_INTENSITY: float = 0.6
const GLOW_HDR_THRESHOLD: float = 2.2
const FOG_ENABLED: bool = true
const FOG_AERIAL_PERSPECTIVE: float = 0.6

# --- Post process (one fullscreen pass, below the HUD; F2 toggles) ---
const POSTFX_ENABLED: bool = true
const POSTFX_LAYER: int = 5
const POSTFX_CA_STRENGTH: float = 0.0042
const POSTFX_CA_START: float = 0.35
const POSTFX_GRAIN_STRENGTH: float = 0.036
const POSTFX_GRAIN_SIZE: float = 1.0
const POSTFX_GRAIN_FPS: float = 24.0
const POSTFX_GRAIN_HIGHLIGHT_KEEP: float = 0.35

# --- Mobile tier (scripts/quality.gd) ---
const MOBILE_SHADOW_SIZE: int = 1024
const MOBILE_SHADOW_FILTER_QUALITY: int = 2
const MOBILE_SHADOW_MAX_DISTANCE: float = 45.0
const MOBILE_MSAA: Viewport.MSAA = Viewport.MSAA_DISABLED
const MOBILE_SCALE_3D: float = 0.6
const MOBILE_SCALING_MODE: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR  # FSR1 is Forward+ only
const MOBILE_FSR_SHARPNESS: float = 0.35
const MOBILE_SCATTER_SCALE: float = 0.3
const MOBILE_PARTICLE_SCALE: float = 0.3
const MOBILE_GLOW_ENABLED: bool = false
const MOBILE_POSTFX_ENABLED: bool = false
const MOBILE_DOF_ENABLED: bool = false
const MOBILE_NIGHT_OMNI_LIGHTS: bool = false
const MOBILE_FPS_CAP: int = 60
## Dynamic 3D resolution (mobile): keeps frame time near the 30 FPS budget with hysteresis.
const DYNRES_MIN: float = 0.5
const DYNRES_MAX: float = 0.8
const DYNRES_TARGET_MS: float = 33.3
const DYNRES_DOWN_ABOVE_MS: float = 34.5
const DYNRES_UP_BELOW_MS: float = 26.0
const DYNRES_STEP: float = 0.05
const DYNRES_WINDOW: float = 1.0
## Mobile boot: overview, short hold, then a smooth dolly to the player at this distance.
const MOBILE_START_DISTANCE: float = 24.0
const MOBILE_INTRO_HOLD: float = 0.4
const MOBILE_INTRO_DOLLY_TIME: float = 1.5

# --- Scatter density ---
const TREE_PINE_COUNT: int = 195
const BUSH_COUNT: int = 80
const ROCK_COUNT: int = 70
const FLOWER_COUNT: int = 700
const MUSHROOM_COUNT: int = 60
const GRASS_TUFT_COUNT: int = 4200
const PEBBLE_COUNT: int = 28

# --- Ambient particles ---
const BUTTERFLY_COUNT: int = 14
const LEAF_COUNT: int = 26
const BIRD_COUNT: int = 5

# --- Island geometry ---
const ISLAND_HALF_SIZE: float = 16.8
const ISLAND_SUPERELLIPSE_N: float = 4.2
const ISLAND_OUTLINE_SEGMENTS: int = 220
const GROUND_GRID_STEP: float = 0.5
const CLIFF_HEIGHT: float = 3.2
const WATER_LEVEL: float = -2.45

# --- Camera feel ---
const HUD_LAYER: int = 10
const CAMERA_FOV: float = 30.0
const CAMERA_YAW_DEG: float = 45.0
const CAMERA_PITCH_DEG: float = -45.0
const CAMERA_DISTANCE_DEFAULT: float = 76.0
const CAMERA_DISTANCE_CLOSE: float = 30.0
const CAMERA_DISTANCE_MIN: float = 16.0
const CAMERA_DISTANCE_MAX: float = 110.0
const CAMERA_ZOOM_STEP: float = 0.14
const CAMERA_ZOOM_SMOOTHING: float = 12.0
const CAMERA_INERTIA_DAMPING: float = 5.5
const CAMERA_PAN_LIMIT: float = 13.0
const CAMERA_FOCUS_SMOOTHING: float = 6.0
const CLICK_MAX_DRAG_PX: float = 6.0
const CAMERA_FOLLOW_SMOOTHING: float = 4.0
const CAMERA_FOLLOW_DISTANCE: float = 30.0
const CAMERA_FOLLOW_ENGAGE_MAX_DISTANCE: float = 48.0
const CAMERA_LOOKAHEAD_TIME: float = 0.45
const CAMERA_LOOKAHEAD_MAX: float = 2.2
const CAMERA_LOOKAHEAD_SMOOTHING: float = 2.5
const STICK_ZOOM_DEADZONE: float = 0.22
const STICK_ZOOM_SPEED: float = 1.6
const CAMERA_KEY_ZOOM_SPEED: float = 1.3
const CAMERA_MODE_BLEND_TIME: float = 0.6
const CAMERA_NEAR_ISO: float = 0.5
const CAMERA_FAR: float = 400.0
# Trauma shake (shake = trauma^2); angles are for CAMERA_SHAKE_REF_FOV and scale with the FOV.
const CAMERA_TRAUMA_DECAY: float = 1.5
const CAMERA_SHAKE_MAX_ANGLE_DEG: Vector3 = Vector3(1.4, 1.4, 2.2)
const CAMERA_SHAKE_REF_FOV: float = 55.0
const CAMERA_SHAKE_MAX_OFFSET: float = 0.05
const CAMERA_SHAKE_FREQUENCY: float = 16.0
const CAMERA_SHAKE_ZOOM_PUNCH: float = 0.035
# Over-the-shoulder mode
const SHOULDER_FOV: float = 57.0
const SHOULDER_NEAR: float = 0.05
const SHOULDER_PIVOT_HEIGHT: float = 1.1
# Composition: the anchor (player chest) is placed at this screen point (fractions from top-left,
# X mirrored on the left shoulder) at SHOULDER_DISTANCE depth along the view.
const SHOULDER_ANCHOR_HEIGHT: float = 0.6
const SHOULDER_SCREEN_X: float = 0.33
const SHOULDER_SCREEN_Y: float = 0.58
const SHOULDER_DISTANCE_DEFAULT: float = 2.1
const SHOULDER_DISTANCE_MIN: float = 1.5
const SHOULDER_DISTANCE_MAX: float = 3.4
const SHOULDER_DISTANCE_SMOOTHING: float = 10.0
const SHOULDER_KEY_ZOOM_SPEED: float = 1.1
const SHOULDER_PITCH_DEFAULT_DEG: float = -11.0
const SHOULDER_PITCH_MIN_DEG: float = -35.0
const SHOULDER_PITCH_MAX_DEG: float = 25.0
const SHOULDER_SWAP_SMOOTHING: float = 6.0
const SHOULDER_STICK_DEADZONE: float = 0.14
const SHOULDER_STICK_CURVE: float = 1.7
const SHOULDER_STICK_YAW_SPEED_DEG: float = 140.0
const SHOULDER_STICK_PITCH_SPEED_DEG: float = 90.0
const SHOULDER_STICK_BOOST: float = 1.6
const SHOULDER_STICK_BOOST_TIME: float = 0.45
const SHOULDER_STICK_SMOOTHING: float = 14.0
const SHOULDER_MOUSE_SENSITIVITY_DEG: float = 0.22
const SHOULDER_COLLISION_MASK: int = 3
# Occlusion: sweep a sphere from the head to the composed position; when blocked, tilt the orbit
# downward in steps (camera rises over the shoulder), then pull in and re-aim at the anchor.
const SHOULDER_ARM_RADIUS: float = 0.18
const SHOULDER_ARM_RETURN_SMOOTHING: float = 4.0
const SHOULDER_CLEAR_FRACTION: float = 0.85
const SHOULDER_OCCLUSION_LIFTS_DEG: Array[float] = [0.0, 10.0, 20.0, 32.0, 45.0, 60.0, 72.0, 80.0]
const SHOULDER_OCCLUSION_SWINGS_DEG: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 100.0, -100.0, 150.0, -150.0]
const SHOULDER_OCCLUSION_SWING_COST: float = 0.8
const SHOULDER_LIFT_RISE_SMOOTHING: float = 12.0
const SHOULDER_LIFT_FALL_SMOOTHING: float = 1.8
const SHOULDER_AIM_SMOOTHING: float = 8.0
const SHOULDER_VIS_MIN_DISTANCE: float = 1.3
const SHOULDER_VISUAL_MARGIN: float = 0.5
const CANOPY_MIN_ASPECT: float = 4.0
const CANOPY_RADIUS_SCALE: float = 3.6
const CANOPY_BOTTOM_FRAC: float = 0.25
const CANOPY_TOP_FRAC: float = 1.6
const CANOPY_SAMPLES: int = 16
const SHOULDER_RUN_SPEED_LOW: float = 2.4
const SHOULDER_RUN_SPEED_HIGH: float = 4.3
const SHOULDER_BOB_KICK_WALK: float = 0.16
const SHOULDER_BOB_KICK_RUN: float = 0.34
const SHOULDER_SWAY_KICK_WALK: float = 0.07
const SHOULDER_SWAY_KICK_RUN: float = 0.16
const SHOULDER_SPRING_STIFFNESS: float = 110.0
const SHOULDER_SPRING_DAMPING: float = 14.0
const SHOULDER_RUN_FOV_KICK: float = 5.0
const SHOULDER_FOV_SPRING_STIFFNESS: float = 30.0
const SHOULDER_FOV_SPRING_DAMPING: float = 8.0
const SHOULDER_LAND_MIN_SPEED: float = 2.0
const SHOULDER_LAND_DIP_PER_SPEED: float = 0.22
const SHOULDER_LAND_DIP_MAX: float = 2.2
# Depth of field (CameraAttributesPractical); iso distances are fractions of the focus distance.
const DOF_ENABLED: bool = true
const DOF_FOCUS_SMOOTHING: float = 7.0
const DOF_ISO_FAR_START_FRAC: float = 0.12
const DOF_ISO_FAR_TRANSITION_FRAC: float = 0.32
const DOF_ISO_NEAR_START_FRAC: float = 0.14
const DOF_ISO_NEAR_TRANSITION_FRAC: float = 0.22
const DOF_ISO_AMOUNT_ZOOMED_OUT: float = 0.05
const DOF_ISO_AMOUNT_ZOOMED_IN: float = 0.13
const DOF_SHOULDER_RAY_LENGTH: float = 90.0
const DOF_SHOULDER_FOCUS_MIN: float = 2.0
const DOF_SHOULDER_FAR_OFFSET_MIN: float = 8.0
const DOF_SHOULDER_FAR_OFFSET_FRAC: float = 1.2
const DOF_SHOULDER_FAR_TRANSITION: float = 40.0
const DOF_SHOULDER_AMOUNT: float = 0.06
# Mobile tier (scripts/quality.gd): cheaper, softer DOF.
const DOF_MOBILE_ENABLED: bool = false
const DOF_MOBILE_QUALITY: int = 1
const DOF_MOBILE_AMOUNT_SCALE: float = 0.6
const TOUCH_ORBIT_SENSITIVITY_DEG: float = 0.25
# Catapult flight (player.is_launched()): wider, firmer iso follow and a chase cam in shoulder mode.
const LAUNCH_BLEND_IN: float = 2.0
const LAUNCH_BLEND_OUT: float = 1.6
const LAUNCH_ZOOM_STIFFNESS: float = 8.0
const LAUNCH_ZOOM_DAMPING: float = 5.0
const LAUNCH_FOLLOW_SMOOTHING: float = 10.0
const LAUNCH_PAN_LIMIT_EXTRA: float = 20.0
# The look point sits this far from the player toward the predicted landing; the player must stay
# within LAUNCH_CENTER_NDC of screen center (1/3 = central third) at LAUNCH_ISO_DISTANCE.
const LAUNCH_LANDING_BIAS: float = 0.3
const LAUNCH_CENTER_NDC: float = 0.24
const LAUNCH_ISO_DISTANCE: float = 24.0
const LAUNCH_IMPACT_DISTANCE: float = 21.0
const LAUNCH_IMPACT_ZOOM_STIFFNESS: float = 60.0
const LAUNCH_IMPACT_ZOOM_DAMPING: float = 14.0
const LAUNCH_IMPACT_LEAD: float = 0.3
const LAUNCH_DOF_STRENGTH_SCALE: float = 0.5
const LAUNCH_MOUNT_LOOK_LIFT: float = 1.2
const LAUNCH_IMPACT_HOLD: float = 0.4
const LAUNCH_IMPACT_TRAUMA: float = 0.45
const LAUNCH_CHASE_BLEND_IN: float = 6.0
const LAUNCH_POST_YAW_SMOOTHING: float = 2.5
const LAUNCH_GRAVITY_SMOOTHING: float = 8.0
const LAUNCH_LAND_GRACE: float = 0.25
const LAUNCH_LAND_MAX_VY: float = 0.5
const LAUNCH_LAND_PROBE: float = 0.3
const LAUNCH_REST_SPEED: float = 0.3
const LAUNCH_REST_TIME: float = 0.15
const LAUNCH_DIR_SMOOTHING: float = 6.0
const LAUNCH_CHASE_DISTANCE: float = 4.2
const LAUNCH_CHASE_HEIGHT: float = 1.6
const LAUNCH_CHASE_AIM_AHEAD: float = 2.5
const LAUNCH_CHASE_FOV: float = 64.0
const LAUNCH_CHASE_CLIMB_INFLUENCE: float = 0.3
const LAUNCH_CHASE_DOWN_TILT: float = 0.3

# --- Selection juice ---
const BOUNCE_SQUASH: Vector3 = Vector3(1.12, 0.84, 1.12)
const BOUNCE_STRETCH: Vector3 = Vector3(0.94, 1.1, 0.94)
const BOUNCE_TIME: float = 0.32
const HOVER_RIM_STRENGTH: float = 0.35
const SELECT_RIM_STRENGTH: float = 0.6
const HIGHLIGHT_RIM_POWER: float = 5.0
const HOVER_FILL: float = 0.015
const SELECT_FILL: float = 0.025
const SELECT_PULSE: float = 0.35
const HOVER_POP_SCALE: float = 1.05
const HOVER_POP_TIME: float = 0.4
const LABEL_HEIGHT_OFFSET: float = 0.3
const LABEL_HEIGHT_FACTOR: float = 0.85
const LABEL_FLOAT_AMPLITUDE: float = 0.08

# --- Bumps and FX bursts ---
const BUMP_COOLDOWN: float = 0.25
const BUMP_REFERENCE_IMPULSE: float = 6.0
const BUMP_TILT_DEG: float = 5.0
const BUMP_SQUASH: float = 0.08
const BUMP_WOBBLE_TIME: float = 0.7
const FX_DUST_COUNT: int = 18
const FX_LEAF_COUNT: int = 10
const FX_SPARK_COUNT: int = 12

# --- Interactive foliage ---
const FOLIAGE_PUSH_SPRING: float = 60.0
const FOLIAGE_PUSH_DAMPING: float = 7.0
const FOLIAGE_PUSH_RADIUS: float = 0.9
const FOLIAGE_PUSH_TUFT: float = 0.35
const FOLIAGE_PUSH_FLOWER: float = 0.12
const FOLIAGE_PUSH_BUSH: float = 0.22
const FOLIAGE_PUSH_REED: float = 0.25
const TREE_SHAKE_AMOUNT: float = 0.22
const BUSH_SHAKE_AMOUNT: float = 0.18
const BUTTERFLY_FLEE_STRENGTH: float = -9.0
const BUTTERFLY_FLEE_RADIUS: float = 2.6

# --- Day lighting (neutrals read cream / warm grey, shadows slightly cool) ---
const DAY_SUN_COLOR: Color = Color("FFEBC8")
const DAY_SUN_ENERGY: float = 1.55
const DAY_AMBIENT_COLOR: Color = Color("D9D3C6")
const DAY_AMBIENT_SKY_CONTRIBUTION: float = 0.45
const DAY_AMBIENT_ENERGY: float = 0.5

# --- Day / night ---
const NIGHT_TRANSITION_TIME: float = 3.0
const NIGHT_SUN_SINK_DEG: float = 40.0
const NIGHT_MOON_COLOR: Color = Color("9DB4FF")
const NIGHT_MOON_ENERGY: float = 0.95
const NIGHT_MOON_DIRECTION: Vector3 = Vector3(0.55, 0.85, -0.6)
const NIGHT_AMBIENT_COLOR: Color = Color("2D5A70")
const NIGHT_AMBIENT_SKY_CONTRIBUTION: float = 0.15
const NIGHT_AMBIENT_ENERGY: float = 0.9
const NIGHT_EXPOSURE: float = 1.2
const NIGHT_GLOW_INTENSITY: float = 0.9
const NIGHT_GLOW_THRESHOLD: float = 0.9
const NIGHT_FOG_COLOR: Color = Color("1C3346")
const NIGHT_SATURATION: float = 0.72
const NIGHT_SKY_TOP: Color = Color("0B1A2E")
const NIGHT_SKY_HORIZON: Color = Color("24455A")
const LANTERN_LIGHT_RANGE: float = 2.6
const LANTERN_LIGHT_ENERGY: float = 1.6

# --- Foliage near-camera fade (shoulder camera) ---
const FOLIAGE_CAMERA_FADE_NEAR: float = 0.45
const FOLIAGE_CAMERA_FADE_FAR: float = 1.2

# --- Cloud field (CLOUDS agent) ---
const CLOUD_AREA: Rect2 = Rect2(-110.0, -110.0, 220.0, 220.0)

# --- Fog field masks (FOG agent's simulation) ---
const FOG_AREA: Rect2 = Rect2(-17, -17, 34, 34)
const FOG_MASK_PX_PER_UNIT: float = 4.0
const FOG_DENSITY_VILLAGE: float = 0.07
const FOG_DENSITY_WILD: float = 1.0
const FOG_DENSITY_PATH: float = 0.0

# --- Liquid field (LIQUID agent) ---
const LIQUID_AREA: Rect2 = Rect2(-19.5, -19.5, 39, 39)
const LIQUID_TERRAIN_RES: int = 256

# --- Pond water body ---
const POND_SHORE_OFFSET: float = 0.9
const POND_SHORE_CLEARANCE: float = 0.45
const POND_SHORE_CAMERA_ROOM: float = 1.5
const POND_SPLASH_DROPS: int = 26

# --- Android back button ---
const BACK_DOUBLE_PRESS_WINDOW: float = 2.0

# --- FPS counter ---
const FPS_REFRESH_INTERVAL: float = 0.25

# --- Wind ---
const WIND_STRENGTH: float = 1.0
const WIND_SPEED: float = 1.2

# --- Resource collection (owned by resource_collectors.gd / hud.gd) ---
const GOLD_COLOR: Color = Color("FFC93C")
const GOLD_COLOR_DARK: Color = Color("D48A12")
const MANA_COLOR: Color = Color("C24BE0")
const MANA_COLOR_DARK: Color = Color("8E2BB0")
const COLLECT_FILL_TIME_MIN: float = 20.0
const COLLECT_FILL_TIME_MAX: float = 30.0
const COLLECT_START_FULL_FILL: float = 0.97
const COLLECT_BUBBLE_THRESHOLD: float = 0.6
const COLLECT_MIN_FILL: float = 0.12
const COLLECT_GOLD_CAPACITY: int = 1250
const COLLECT_MANA_CAPACITY: int = 900
const COLLECT_AUTO_RADIUS_TILES: float = 1.6
const COLLECT_BUBBLE_SIZE: float = 1.35
const COLLECT_BUBBLE_HEIGHT: float = 0.85
const COLLECT_BUBBLE_HOP_HEIGHT: float = 0.16
const COLLECT_BUBBLE_HOP_SPEED: float = 2.6
const COLLECT_BUBBLE_SQUASH: float = 0.1
const COLLECT_BUBBLE_FULL_PULSE: float = 0.05
const COLLECT_BUBBLE_POP_IN_TIME: float = 0.7
const COLLECT_BUBBLE_POP_OUT_TIME: float = 0.18
const COLLECT_GOLD_PIECES: int = 8
const COLLECT_MANA_PIECES: int = 7
const COLLECT_PIECE_STAGGER: float = 0.035
const COLLECT_BURST_TIME: float = 0.48
const COLLECT_BURST_SPREAD: float = 1.5
const COLLECT_BURST_HEIGHT: float = 1.7
const COLLECT_BURST_SPIN: float = 9.0
const COLLECT_PIECE_SCALE: float = 1.0
const COLLECT_MANA_EMISSION: float = 1.4
const COLLECT_FLY_TIME: float = 0.6
const COLLECT_FLY_TIME_JITTER: float = 0.12
const COLLECT_FLY_CURVE: float = 0.32
const COLLECT_FLYER_END_SCALE: float = 0.7
const COLLECT_BUILDING_SQUASH: Vector3 = Vector3(1.1, 0.86, 1.1)
const COLLECT_BUILDING_BOUNCE_TIME: float = 0.42
const COLLECT_SFX_VOLUME_DB: float = -6.0
const COLLECT_SFX_PITCH_JITTER: float = 0.09
const HUD_GOLD_START: int = 184250
const HUD_MANA_START: int = 96410
const HUD_GOLD_CAP: int = 300000
const HUD_MANA_CAP: int = 250000
const HUD_ROLL_TIME: float = 0.5
const HUD_POP_SCALE: float = 1.12
const HUD_POP_TIME: float = 0.3
const HUD_ICON_POP_SCALE: float = 1.3
const HUD_GLOW_TIME: float = 0.5
const HUD_BAR_TWEEN_TIME: float = 0.55
const HUD_BREATH_AMPLITUDE: float = 0.035
const HUD_BREATH_SPEED: float = 1.7
const HUD_SHINE_PERIOD: float = 3.8
const HUD_SHINE_TIME: float = 0.6

# --- Touch controls ---
const TOUCH_LAYER_OFFSET: int = 1
const TOUCH_REFERENCE_SHORT_SIDE: float = 900.0
const TOUCH_UI_SCALE_MIN: float = 0.7
const TOUCH_UI_SCALE_MAX: float = 1.35
const TOUCH_MARGIN: float = 34.0
const TOUCH_TOP_BAND: float = 0.17
const TOUCH_LEFT_ZONE: float = 0.45
const TOUCH_FADE_TIME: float = 0.25
const TOUCH_STICK_RADIUS: float = 104.0
const TOUCH_KNOB_RADIUS: float = 44.0
const TOUCH_STICK_DEADZONE: float = 0.08
const TOUCH_STICK_RUN_BAND: float = 0.85
const TOUCH_STICK_RETURN_TIME: float = 0.22
const TOUCH_STICK_GHOST_ALPHA: float = 0.3
const TOUCH_STICK_ACTIVE_ALPHA: float = 0.6
const TOUCH_STICK_FILL_ALPHA: float = 0.32
const TOUCH_KNOB_ALPHA: float = 0.8
const TOUCH_BUTTON_IDLE_ALPHA: float = 0.45
const TOUCH_BUTTON_PRESSED_ALPHA: float = 0.8
const TOUCH_BUTTON_FILL_ALPHA: float = 0.55
const TOUCH_ICON_ALPHA: float = 0.85
const TOUCH_INTERACT_DIM_ALPHA: float = 0.25
const TOUCH_INTERACT_LIT_ALPHA: float = 0.85
const TOUCH_GADGET_IDLE_DELAY: float = 3.0
const TOUCH_GADGET_IDLE_ALPHA: float = 0.2
const TOUCH_GADGET_IDLE_FADE: float = 0.6
const TOUCH_STICK_HOME: Vector2 = Vector2(196.0, 196.0)
const TOUCH_JUMP_RADIUS: float = 88.0
const TOUCH_JUMP_INSET: Vector2 = Vector2(150.0, 150.0)
const TOUCH_INTERACT_RADIUS: float = 58.0
const TOUCH_INTERACT_OFFSET: Vector2 = Vector2(-190.0, -86.0)
const TOUCH_GADGET_RADIUS: float = 32.0
const TOUCH_GADGET_GAP: float = 80.0
const TOUCH_HIT_SLOP: float = 1.18
const TOUCH_RIPPLE_TIME: float = 0.42
const TOUCH_AIR_RING_TIME: float = 0.9
const TOUCH_INTERACT_PULSE_HZ: float = 1.6
const TOUCH_TAP_SLOP: float = 18.0
const TOUCH_TAP_TIME: float = 0.35
const TOUCH_ORBIT_GAIN: float = 1.0
const TOUCH_SFX_DB: float = -9.0
const TOUCH_GAMEPAD_AXIS_HIDE: float = 0.45
const TOUCH_MIN_HOLD: float = 0.07
