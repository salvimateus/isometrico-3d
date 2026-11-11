extends RefCounted

## Central knobs for the player character: movement, jump, animation, particles, rumble, SFX and juice.

# --- Body / collision ---
const CAPSULE_RADIUS: float = 0.3
const CAPSULE_HEIGHT: float = 1.0
const COLLISION_LAYER: int = 4
const COLLISION_MASK: int = 1 | 2 | 16
const OBSTACLE_LAYER_BIT: int = 2
const VISUAL_SCALE: float = 0.85

# --- Input ---
const STICK_DEADZONE: float = 0.2
const ACTION_DEADZONE: float = 0.05

# --- Ground movement ---
const WALK_SPEED: float = 2.1
const RUN_SPEED: float = 4.6
const ACCELERATION: float = 13.0
const RUN_ACCELERATION: float = 16.0
const DECELERATION: float = 17.0
const TURN_SPEED: float = 12.0
const MOVING_EPSILON: float = 0.15

# --- Skid (reversing direction at speed) ---
const SKID_MIN_SPEED: float = 2.6
const SKID_REVERSE_DOT: float = -0.35
const SKID_DECELERATION: float = 30.0
const SKID_LEAN_BACK_DEG: float = 16.0
const SKID_DUST_INTERVAL: float = 0.05
const SKID_SOUND_COOLDOWN: float = 0.45

# --- Jump (base gravity is project gravity * GRAVITY_SCALE) ---
const GRAVITY_SCALE: float = 2.2
const JUMP_HEIGHT: float = 1.05
const JUMP_CUT_FACTOR: float = 0.45
const APEX_SPEED_THRESHOLD: float = 1.6
const APEX_GRAVITY_MULT: float = 0.5
const FALL_GRAVITY_MULT: float = 1.65
const MAX_FALL_SPEED: float = 16.0
const COYOTE_TIME: float = 0.1
const JUMP_BUFFER_TIME: float = 0.12
const AIR_CONTROL: float = 0.6
const LAND_SOFT_SPEED: float = 2.0
const LAND_HARD_SPEED: float = 7.0

# --- Gait ---
const WALK_STRIDE: float = 0.42
const RUN_STRIDE: float = 0.64
const WALK_LEG_SWING_DEG: float = 30.0
const RUN_LEG_SWING_DEG: float = 55.0
const WALK_ARM_SWING_DEG: float = 30.0
const RUN_ARM_SWING_DEG: float = 70.0
const RUN_ARM_BEND_DEG: float = 30.0
const WALK_FOOT_LIFT: float = 0.045
const RUN_FOOT_LIFT: float = 0.1
const WALK_BOB: float = 0.03
const RUN_BOB: float = 0.08
const WALK_LEAN_DEG: float = 4.0
const RUN_LEAN_DEG: float = 15.0
const ACCEL_LEAN_DEG: float = 0.9
const MAX_ACCEL_LEAN_DEG: float = 9.0
const BANK_DEG_PER_RAD_S: float = 3.0
const MAX_BANK_DEG: float = 14.0
const HIP_TWIST_DEG: float = 8.0
const SHOULDER_TWIST_DEG: float = 12.0
const SHOULDER_ROLL_DEG: float = 6.0
const RUN_BLEND_SPEED: float = 6.0
const GAIT_BLEND_SPEED: float = 8.0
const AIR_BLEND_SPEED: float = 14.0
const WADE_BLEND_SPEED: float = 5.0
const WADE_FOOT_LIFT: float = 0.09
const WADE_ARM_RAISE_DEG: float = 38.0
const WADE_LEAN_DEG: float = 6.0

# --- Idle ---
const BREATH_RATE: float = 2.1
const BREATH_AMOUNT: float = 0.03
const IDLE_SWAY_DEG: float = 2.0
const BLINK_INTERVAL_MIN: float = 1.8
const BLINK_INTERVAL_MAX: float = 4.5
const BLINK_DURATION: float = 0.13
const IDLE_LOOK_INTERVAL: float = 3.2
const IDLE_LOOK_DEG: float = 22.0
const FIDGET_DELAY_MIN: float = 2.5
const FIDGET_DELAY_MAX: float = 5.5
const FIDGET_DURATION: float = 1.3

# --- Squash and stretch (spring on a scalar; positive = stretch) ---
const SQUASH_STIFFNESS: float = 260.0
const SQUASH_DAMPING: float = 14.0
const SQUASH_START_KICK: float = 2.2
const SQUASH_RUN_START_KICK: float = 3.2
const SQUASH_STOP_KICK: float = -2.6
const SQUASH_BUMP_KICK: float = -3.2
const SQUASH_JUMP_PRESET: float = -0.12
const SQUASH_JUMP_KICK: float = 5.5
const SQUASH_LAND_KICK_PER_SPEED: float = -0.75
const SQUASH_MAX: float = 0.22
const AIR_STRETCH_PER_SPEED: float = 0.012
const START_SPEED_RATIO: float = 0.35
const STOP_SPEED_RATIO: float = 0.25

# --- Secondary motion (shield, braids, axe) ---
const JIGGLE_STIFFNESS: float = 180.0
const JIGGLE_DAMPING: float = 9.0
const JIGGLE_GAIN_DEG: float = 260.0

# --- Hair and fur lock springs, per layer: crown, nape, back, pelt tufts ---
const HAIR_STIFFNESS: Array[float] = [260.0, 170.0, 110.0, 200.0]
const HAIR_DAMPING: Array[float] = [11.0, 8.0, 6.0, 9.0]
const HAIR_GAIN: Array[float] = [0.35, 0.6, 0.75, 0.4]
const HAIR_LAG_MOVE: float = 0.22
const HAIR_LAG_RUN: float = 0.38
const HAIR_LAG_LEAN: float = 0.8
const HAIR_LIFT_PER_FALL_SPEED: float = 0.07
const HAIR_LIFT_MAX: float = 0.7
const HAIR_LAND_KICK: float = -0.9
const HAIR_JUMP_KICK: float = -0.6
const HAIR_SWAY_BANK: float = 0.9
const HAIR_WIND_DEG: float = 3.5
const HAIR_WIND_FREQ: float = 1.3

# --- Dust ---
const DUST_POOL_SIZE: int = 8
const DUST_PER_STEP: int = 5
const DUST_LIFETIME: float = 0.55
const DUST_SIZE: float = 0.09
const DUST_MIN_SPEED_RATIO: float = 0.55
const DUST_WALK: bool = false
const DUST_COLOR: Color = Color("E6CFA4")
const DUST_RING_AMOUNT: int = 16
const DUST_RING_MIN_SPEED: float = 3.0
const TRAIL_AMOUNT: int = 18
const TRAIL_LIFETIME: float = 0.7
const TRAIL_SIZE: float = 0.05
const TRAIL_MIN_SPEED_RATIO: float = 0.7

# --- Rumble (Input.start_joy_vibration: weak = high-frequency motor, strong = low-frequency motor) ---
const RUMBLE_ENABLED: bool = true
const RUMBLE_STEP_WEAK: float = 0.22
const RUMBLE_STEP_STRONG: float = 0.0
const RUMBLE_STEP_DURATION: float = 0.045
const RUMBLE_STEP_COOLDOWN: float = 0.12
const RUMBLE_RUN_START_WEAK: float = 0.35
const RUMBLE_RUN_START_STRONG: float = 0.5
const RUMBLE_RUN_START_DURATION: float = 0.12
const RUMBLE_RUN_START_COOLDOWN: float = 0.5
const RUMBLE_IMPACT_MIN_SPEED: float = 0.9
const RUMBLE_IMPACT_WEAK_MAX: float = 0.5
const RUMBLE_IMPACT_STRONG_MAX: float = 1.0
const RUMBLE_IMPACT_DURATION_MIN: float = 0.08
const RUMBLE_IMPACT_DURATION_MAX: float = 0.22
const RUMBLE_IMPACT_COOLDOWN: float = 0.4
const RUMBLE_JUMP_WEAK: float = 0.18
const RUMBLE_JUMP_STRONG: float = 0.0
const RUMBLE_JUMP_DURATION: float = 0.04
const RUMBLE_LAND_WEAK_MAX: float = 0.45
const RUMBLE_LAND_STRONG_MAX: float = 0.85
const RUMBLE_LAND_DURATION_MIN: float = 0.05
const RUMBLE_LAND_DURATION_MAX: float = 0.2
const RUMBLE_LAND_COOLDOWN: float = 0.15
const RUMBLE_SKID_WEAK: float = 0.3
const RUMBLE_SKID_STRONG: float = 0.15
const RUMBLE_SKID_DURATION: float = 0.14
const RUMBLE_STUMBLE_WEAK: float = 0.7
const RUMBLE_STUMBLE_STRONG: float = 1.0
const RUMBLE_STUMBLE_DURATION: float = 0.35

# --- SFX (scripts/audio/sfx.gd presets; volumes in dB, pitch as scale) ---
const SFX_ENABLED: bool = true
const SFX_WALK_VOLUME_DB: float = -12.0
const SFX_RUN_VOLUME_DB: float = -6.0
const SFX_WALK_PITCH: float = 0.94
const SFX_RUN_PITCH: float = 1.06
const SFX_LR_PITCH_OFFSET: float = 0.025
const SFX_WHOOSH_VOLUME_DB: float = -9.0
const SFX_JUMP_VOLUME_DB: float = -8.0
const SFX_SKID_VOLUME_DB: float = -7.0
const SFX_LAND_VOLUME_DB_MIN: float = -12.0
const SFX_LAND_VOLUME_DB_MAX: float = -1.0
const SFX_THUD_VOLUME_DB_MAX: float = -2.0
const SFX_THUD_VOLUME_DB_MIN: float = -12.0
const SFX_WATER_STEP_VOLUME_DB: float = -8.0
const SFX_SPLASH_SMALL_DB: float = -8.0
const SFX_SPLASH_BIG_DB_MIN: float = -8.0
const SFX_SPLASH_BIG_DB_MAX: float = 0.0
const SFX_SURFACE_RAY_LENGTH: float = 0.6
const SFX_DEFAULT_SURFACE: StringName = &"grass"
const SFX_SURFACES: Array[StringName] = [&"grass", &"dirt", &"wood", &"stone"]
const SFX_LOG_STEPS: bool = false

# --- Liquid field contract (group &"liquid_field") ---
const LIQUID_GROUP: StringName = &"liquid_field"
const WATER_MIN_DEPTH: float = 0.03
const WADE_FULL_DEPTH: float = 0.5
const WADE_MIN_SPEED_MULT: float = 0.45
const WADE_ACCEL_MULT: float = 0.6
const CURRENT_PUSH: float = 2.2
const CURRENT_MAX_DRIFT: float = 3.5
const WAKE_WALK_RADIUS: float = 0.45
const WAKE_RUN_RADIUS: float = 0.7
const WAKE_VELOCITY_GAIN: float = 1.0
const WATER_LAND_DISTURB_RADIUS: float = 1.2
const WATER_LAND_DISTURB_GAIN: float = 0.6
const STUMBLE_REL_SPEED: float = 2.6
const STUMBLE_MIN_DEPTH: float = 0.08
const STUMBLE_KNOCKBACK: float = 3.2
const STUMBLE_HOP: float = 2.4
const STUMBLE_TIME: float = 0.65
const STUMBLE_COOLDOWN: float = 1.2
const CAMERA_TRAUMA_STUMBLE: float = 0.3

# --- Camera contract (group &"camera_rig") ---
const CAMERA_GROUP: StringName = &"camera_rig"
const CAMERA_TRAUMA_HARD_LAND: float = 0.22
const CAMERA_TRAUMA_IMPACT_MAX: float = 0.18

# --- Obstacle bump contract (collider.bump(impulse)) ---
const BUMP_IMPULSE_GAIN: float = 1.0

# --- Demo autopilot (--player-demo) ---
const DEMO_RADIUS: float = 3.6
const DEMO_LOOKAHEAD: float = 1.1
const DEMO_SEGMENT_TIME: float = 4.0
const DEMO_IDLE_TIME: float = 2.4

# --- Catapult ride (mount / launch / crash / dizzy) ---
const PLAYER_GROUP: StringName = &"player"
const MOUNT_HOP_TIME: float = 0.35
const MOUNT_HOP_HEIGHT: float = 0.6
const NERVOUS_RAMP_TIME: float = 3.0
const NERVOUS_TREMBLE_DEG: float = 4.0
const NERVOUS_TREMBLE_FREQ: float = 28.0
const SWEAT_AMOUNT: int = 10
const LAUNCH_GRAVITY: float = 15.0
const LAUNCH_MIN_AIR_TIME: float = 0.2
const LAUNCH_TUMBLE_SPEED: float = 2.4
const LAUNCH_ROLL_SPEED: float = 0.7
const FLAIL_ARM_SPEED: float = 13.0
const FLAIL_LEG_SPEED: float = 15.0
const CRASH_SQUASH_KICK: float = -9.0
const CRASH_DUST_RING: float = 1.6
const CRASH_DOWN_TIME: float = 1.5
const CRASH_GETUP_TIME: float = 0.6
const CRASH_LIE_HEIGHT: float = 0.14
const STARS_COUNT: int = 5
const STARS_RADIUS: float = 0.3
const STARS_SPEED: float = 4.5
const RUMBLE_CRASH_WEAK: float = 1.0
const RUMBLE_CRASH_STRONG: float = 1.0
const RUMBLE_CRASH_DURATION: float = 0.5
const RUMBLE_LAUNCH_WEAK: float = 0.6
const RUMBLE_LAUNCH_STRONG: float = 0.7
const RUMBLE_LAUNCH_DURATION: float = 0.2
const CAMERA_TRAUMA_CRASH: float = 0.5
const SFX_SCREAM_DB: float = -3.0
const SFX_IMPACT_HEAVY_DB: float = 0.0
const SFX_DIZZY_DB: float = -6.0

# --- Water landing after a launch (group &"water_body" or the liquid field) ---
const WATER_BODY_GROUP: StringName = &"water_body"
const SPLASH_IN_STRENGTH: float = 1.0
const CAMERA_TRAUMA_WATER: float = 0.35
const SWIM_SINK_TIME: float = 0.35
const SWIM_UNDER_TIME: float = 0.3
const SWIM_RISE_TIME: float = 0.45
const SWIM_SPIT_TIME: float = 0.6
const SWIM_SHAKE_TIME: float = 0.6
const SWIM_SINK_DEPTH: float = 1.0
const SWIM_FLOAT_DEPTH: float = 0.5
const SHORE_HOP_TIME: float = 0.75
const SHORE_HOP_HEIGHT: float = 1.3
const DRIP_TIME: float = 2.0
const SFX_SPIT_DB: float = -6.0

# --- Water spit (effects drawn by scripts/liquid/water_fx.gd) ---
const BIG_SPLASH_REF_FALL_SPEED: float = 14.0
const SPIT_JET_TIME: float = 0.4
