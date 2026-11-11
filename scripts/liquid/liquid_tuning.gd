extends RefCounted

## Cost and feel knobs for the liquid system (shallow-water sim, water render, bucket sequence).

# --- Cost ---------------------------------------------------------------------------------------
const SIM_RESOLUTION: int = 256 # cells along the longest side of the area (rounded to a multiple of 4)
const SIM_HZ: float = 120.0
const SIM_MAX_STEPS_PER_FRAME: int = 4
const CALM_SIM_HZ: float = 30.0 # once nothing moves fast and no source is active
const DRYING_FX_HZ: float = 10.0 # water gone, only the wet map keeps drying
const SURFACE_GRID: int = 256 # quads along the longest side of the water mesh
const READBACK_DIV: int = 4 # readback cell = READBACK_DIV x READBACK_DIV sim cells
const EVENT_SCAN_INTERVAL: float = 0.08
const MAX_SOURCES: int = 8
const MAX_DISTURBANCES: int = 8
const DROPLET_AMOUNT: int = 1400
const MIST_AMOUNT: int = 160
const FALL_AMOUNT: int = 2400
const JET_SEGMENTS: int = 40
const JET_SIDES: int = 10

# --- Shallow water physics ----------------------------------------------------------------------
const GRAVITY: float = 9.8
const LINEAR_DRAG: float = 0.12 # 1/s on face flux
const BED_DRAG: float = 0.018
const WALL_DRAG: float = 9.0 # 1/s on face flux within two cells of a wall # 1/s per unit of 1/depth: thin sheets slow down much more
const MAX_SPEED: float = 5.0
const DRAIN_DROP: float = 0.6 # virtual fall height that pulls water over a drain edge
const ABSORB_FILM: float = 0.006 # units/s soaked in under thin sheets (low, so sheets reach the basins first)
const ABSORB_FLAT: float = 0.0045 # units/s under flat flooding
const ABSORB_BASIN: float = 0.028 # 1/s exponential decay of puddles in depressions (~40-60 s visible)
const ABSORB_FILM_DEPTH: float = 0.05 # film -> flat blend depth
const BASIN_RADIUS: float = 1.6 # world units of the neighbourhood a depression is measured against
const BASIN_DEPTH: Vector2 = Vector2(0.01, 0.04) # depth below the neighbourhood that counts as a basin
const WET_DEPTH: float = 0.004
const SLEEP_DEPTH: float = 0.0004 # readback mean depth below this counts as dry
const CALM_SPEED: float = 0.12

# --- Wet ground and foam ------------------------------------------------------------------------
const WET_RISE_RATE: float = 6.0 # 1/s toward fully wet while covered
const DRY_TIME: float = 30.0 # seconds from fully wet to dry
const FOAM_DECAY: float = 0.9 # 1/s
const FOAM_SPEED_RANGE: Vector2 = Vector2(1.9, 4.5)
const FOAM_FROM_SPEED: float = 0.7
const FOAM_FROM_FRONT: float = 7.0
const FOAM_FROM_CONVERGE: float = 0.5
const FOAM_FROM_WALL: float = 2.4
const FOAM_FROM_DRAIN: float = 4.0

# --- Bucket --------------------------------------------------------------------------------------
const BUCKET_VOLUME: float = 26.0 # world units^3 poured per use
const FILL_DEPTH: float = 1.0 # FillSurface travel (TankPivot local Y) from full to empty
const ANTICIPATION_TIME: float = 1.05
const ANTICIPATION_SWINGS: float = 2.5
const ANTICIPATION_ANGLE_DEG: float = 7.0
const TIP_TIME: float = 0.85
const TIP_ANGLE_DEG: float = 110.0
const POUR_START_DEG: float = 38.0 # rim angle where water starts to leave
const POUR_RATE_MAX: float = 14.0 # units^3/s at full tilt and full tank
const JET_SPEED: float = 3.6 # exit speed along the tank front
const JET_RADIUS: float = 0.85 # at full flow; thins with flow^0.65 as the tank empties
const EMPTY_HOLD_TIME: float = 1.6
const RETURN_TIME: float = 1.1
const REFILL_TIME: float = 10.0
const IMPACT_RADIUS: float = 1.3
const IMPACT_PUSH: float = 0.7 # jet horizontal momentum handed to the sheet
const BUTTON_DROP: float = 0.06
const BUTTON_TRIGGER_RADIUS: float = 0.5

# --- Juice ---------------------------------------------------------------------------------------
const TRAUMA_BUTTON: float = 0.18
const TRAUMA_TIP: float = 0.25
const TRAUMA_IMPACT: float = 0.75
const TRAUMA_RETURN: float = 0.2
const RUMBLE_BUTTON: Vector3 = Vector3(0.25, 0.1, 0.08) # weak, strong, seconds
const RUMBLE_IMPACT: Vector3 = Vector3(0.7, 1.0, 0.45)
const RUMBLE_RETURN: Vector3 = Vector3(0.2, 0.35, 0.15)
const FLOW_LOOP_DB_RANGE: Vector2 = Vector2(-34.0, -6.0)
const FALL_LOOP_DB_RANGE: Vector2 = Vector2(-34.0, -8.0)
const FLOW_LOOP_FULL: float = 6.0 # sum(depth * speed) mapped to full flow volume
const FALL_LOOP_FULL: float = 3.0 # drained units^3/s mapped to full waterfall volume
const WALL_SPLASH_THRESHOLD: float = 0.35
const FALL_EMIT_THRESHOLD: float = 0.01
const FALL_PARTICLES_PER_UNIT: float = 110.0 # detail streaks per drained unit^3 (the curtain carries the volume)
const FALL_LIP_OFFSET: float = 0.5 # streaks start this far past the wet lip, clear of the rim mesh
const DISTURB_GAIN: float = 0.9

# --- Look ----------------------------------------------------------------------------------------
const SHALLOW_COLOR: Color = Color("6FD3D9")
const DEEP_COLOR: Color = Color("1C7CA6")
const SCATTER_COLOR: Color = Color("2E9FB8")
const FOAM_COLOR: Color = Color("F4FBFF")
const NIGHT_SCATTER_COLOR: Color = Color("12364A")
const NIGHT_FOAM_COLOR: Color = Color("A9C4DE")
const SKY_TOP: Color = Color(0.24, 0.55, 0.9)
const SKY_HORIZON: Color = Color(0.78, 0.9, 0.95)
const NIGHT_SKY_TOP: Color = Color(0.02, 0.05, 0.1)
const NIGHT_SKY_HORIZON: Color = Color(0.08, 0.17, 0.24)

# --- Standalone water FX (water_fx.gd) ----------------------------------------------------------
const WATER_FX_MAX_DROPS: int = 900
const WATER_FX_MIST_AMOUNT: int = 96
const WATER_FX_COLUMN_HEIGHT: float = 3.0 # at strength 1
const WATER_FX_CROWN_RADIUS: float = 1.7 # at strength 1
const WATER_FX_SQUIRT_SPEED: float = 5.0
const WATER_FX_SQUIRT_RATE: float = 90.0 # drops/s
const WATER_FX_DRIP_RATE: float = 22.0 # drops/s at the start of a trail

# --- Waterfall curtain ---------------------------------------------------------------------------
const CURTAIN_FULL_RATE: float = 0.06 # units^3/s through one lip cell for a full-width ribbon
const CURTAIN_OVERLAP: float = 1.9 # ribbon width in cells at full flow (overlaps neighbours into one sheet)
const CURTAIN_SPREAD: float = 0.12 # widening per unit of fall
const CURTAIN_EXIT_SPEED: float = 0.9 # outward speed leaving the lip
const CURTAIN_COLLISION_LAYER: int = 1 << 19 # private layer mirroring big rendered meshes (cliffs) for the curtain path
const CURTAIN_COLLIDER_MIN_SIZE: float = 6.0

# --- Mobile profile (liquid_profile.gd) ---------------------------------------------------------
const MOBILE_SIM_RESOLUTION: int = 128
const MOBILE_SURFACE_GRID: int = 128
const MOBILE_SIM_HZ: float = 60.0
const MOBILE_CALM_SIM_HZ: float = 30.0
const MOBILE_SIM_MAX_STEPS_PER_FRAME: int = 2
const MOBILE_DROPLET_AMOUNT: int = 500
const MOBILE_FALL_AMOUNT: int = 500
const MOBILE_MIST_AMOUNT: int = 60
const MOBILE_FALL_PARTICLES_PER_UNIT: float = 45.0
const MOBILE_JET_SEGMENTS: int = 22
const MOBILE_JET_SIDES: int = 8
const MOBILE_WATER_FX_MAX_DROPS: int = 300
const MOBILE_WATER_FX_MIST_AMOUNT: int = 40
const MOBILE_SPLASH_SCALE: float = 0.5 # particle counts of splashes and spray
