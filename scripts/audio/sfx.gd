extends RefCounted

## Shared procedural SFX: every preset is synthesized at runtime into cached 16-bit mono
## AudioStreamWAV banks and played on a non-positional pool under the SceneTree root.

const Pool := preload("res://scripts/audio/sfx_pool.gd")

const MIX_RATE: int = 32000
const POOL_SIZE: int = 10
const BUS: StringName = &"Master"
const PEAK: float = 0.9
const ATTACK_RAMP_SEC: float = 0.001
const FADE_OUT_SEC: float = 0.01

## gain: linear peak scale after normalization. pitch_jitter: +- fraction. db_jitter: +- dB.
## variations: clips per bank. duration: seconds.
const PRESETS: Dictionary = {
	&"step_grass": {"gain": 0.72, "pitch_jitter": 0.06, "db_jitter": 2.0, "variations": 6, "duration": 0.2},
	&"step_dirt": {"gain": 0.8, "pitch_jitter": 0.06, "db_jitter": 2.0, "variations": 6, "duration": 0.17},
	&"step_wood": {"gain": 0.95, "pitch_jitter": 0.05, "db_jitter": 2.0, "variations": 6, "duration": 0.24},
	&"step_stone": {"gain": 0.85, "pitch_jitter": 0.06, "db_jitter": 2.0, "variations": 6, "duration": 0.15},
	&"land_grass": {"gain": 0.85, "pitch_jitter": 0.05, "db_jitter": 1.5, "variations": 4, "duration": 0.34},
	&"land_dirt": {"gain": 0.9, "pitch_jitter": 0.05, "db_jitter": 1.5, "variations": 4, "duration": 0.32},
	&"land_wood": {"gain": 1.0, "pitch_jitter": 0.04, "db_jitter": 1.5, "variations": 4, "duration": 0.4},
	&"land_stone": {"gain": 0.92, "pitch_jitter": 0.05, "db_jitter": 1.5, "variations": 4, "duration": 0.3},
	&"skid": {"gain": 0.7, "pitch_jitter": 0.06, "db_jitter": 1.5, "variations": 3, "duration": 0.3},
	&"run_whoosh": {"gain": 0.8, "pitch_jitter": 0.07, "db_jitter": 1.5, "variations": 3, "duration": 0.3},
	&"jump": {"gain": 0.7, "pitch_jitter": 0.06, "db_jitter": 1.5, "variations": 3, "duration": 0.22},
	&"thud": {"gain": 0.95, "pitch_jitter": 0.06, "db_jitter": 1.5, "variations": 3, "duration": 0.32},
	&"ui_pop": {"gain": 0.6, "pitch_jitter": 0.04, "db_jitter": 1.0, "variations": 3, "duration": 0.11},
	&"ui_select": {"gain": 0.55, "pitch_jitter": 0.0, "db_jitter": 0.5, "variations": 1, "duration": 0.5},
	&"coin_clink": {"gain": 0.6, "pitch_jitter": 0.03, "db_jitter": 1.0, "variations": 4, "duration": 0.4},
	&"mana_bloop": {"gain": 0.65, "pitch_jitter": 0.05, "db_jitter": 1.0, "variations": 3, "duration": 0.38},
	&"collect_whoosh": {"gain": 0.6, "pitch_jitter": 0.04, "db_jitter": 1.0, "variations": 2, "duration": 0.55},
	&"tree_rustle": {"gain": 0.6, "pitch_jitter": 0.08, "db_jitter": 1.5, "variations": 4, "duration": 0.5},
	&"building_thud": {"gain": 0.95, "pitch_jitter": 0.05, "db_jitter": 1.0, "variations": 3, "duration": 0.6},
	&"ui_tick": {"gain": 0.4, "pitch_jitter": 0.03, "db_jitter": 0.8, "variations": 3, "duration": 0.035},
	&"button_click": {"gain": 0.55, "pitch_jitter": 0.04, "db_jitter": 1.0, "variations": 3, "duration": 0.06},
	&"bell_ding": {"gain": 0.55, "pitch_jitter": 0.02, "db_jitter": 0.8, "variations": 2, "duration": 1.1, "fade": 0.15},
	&"wood_creak": {"gain": 0.6, "pitch_jitter": 0.06, "db_jitter": 1.5, "variations": 3, "duration": 0.55},
	&"water_gush": {"gain": 0.75, "pitch_jitter": 0.04, "db_jitter": 1.0, "variations": 2, "duration": 1.0, "fade": 0.05},
	&"splash_big": {"gain": 0.9, "pitch_jitter": 0.05, "db_jitter": 1.0, "variations": 3, "duration": 0.8, "fade": 0.05},
	&"splash_small": {"gain": 0.7, "pitch_jitter": 0.06, "db_jitter": 1.5, "variations": 4, "duration": 0.35},
	&"water_drip": {"gain": 0.5, "pitch_jitter": 0.08, "db_jitter": 1.5, "variations": 4, "duration": 0.16},
	&"chime_ready": {"gain": 0.55, "pitch_jitter": 0.0, "db_jitter": 0.5, "variations": 1, "duration": 0.9, "fade": 0.12},
	&"footstep_water": {"gain": 0.8, "pitch_jitter": 0.06, "db_jitter": 2.0, "variations": 6, "duration": 0.3},
	&"countdown_tick": {"gain": 0.55, "pitch_jitter": 0.0, "db_jitter": 0.5, "variations": 2, "duration": 0.12},
	&"countdown_go": {"gain": 0.6, "pitch_jitter": 0.0, "db_jitter": 0.5, "variations": 1, "duration": 0.65, "fade": 0.1},
	&"catapult_fire": {"gain": 0.85, "pitch_jitter": 0.05, "db_jitter": 1.0, "variations": 3, "duration": 0.8, "fade": 0.08},
	&"viking_scream": {"gain": 0.8, "pitch_jitter": 0.04, "db_jitter": 1.0, "variations": 2, "duration": 2.8, "fade": 0.15},
	&"impact_heavy": {"gain": 1.0, "pitch_jitter": 0.05, "db_jitter": 1.0, "variations": 3, "duration": 0.6, "fade": 0.05},
	&"dizzy_tweet": {"gain": 0.5, "pitch_jitter": 0.03, "db_jitter": 1.0, "variations": 2, "duration": 1.5, "fade": 0.1},
	# Loops: duration is one cycle; xfade is extra synthesized tail blended into the head.
	&"water_flow": {"gain": 0.6, "pitch_jitter": 0.0, "db_jitter": 0.0, "variations": 1, "duration": 2.5, "loop": true, "xfade": 0.3},
	&"waterfall": {"gain": 0.75, "pitch_jitter": 0.0, "db_jitter": 0.0, "variations": 1, "duration": 3.0, "loop": true, "xfade": 0.3},
	&"rope_creak": {"gain": 0.6, "pitch_jitter": 0.0, "db_jitter": 0.0, "variations": 1, "duration": 2.5, "loop": true, "xfade": 0.3},
}

## AudioStreamPlayer3D for positional loops: inverse distance gives +2.5 dB at 30 m and -8 dB at
## 100 m with unit_size 40; max_db caps the near boost; the distance high-shelf is disabled so the
## sound is not muffled at isometric camera distance; 0 max_distance means no cutoff.
const LOOP_3D_UNIT_SIZE: float = 40.0
const LOOP_3D_MAX_DB: float = 0.0
const LOOP_3D_MAX_DISTANCE: float = 0.0
const LOOP_3D_PANNING: float = 0.6

const SURFACES: Array[StringName] = [&"grass", &"dirt", &"wood", &"stone"]
const WALK_SEQ := {"count": 8, "interval": 0.2, "db": -12.0, "pitch": 0.94}
const RUN_SEQ := {"count": 10, "interval": 0.135, "db": -6.0, "pitch": 1.06, "whoosh_db": -9.0}
const SEQ_LR_PITCH: float = 0.025

# Grain probabilities below were authored per sample at 22050 Hz.
const DENSITY: float = 22050.0 / float(MIX_RATE)

static var _banks: Dictionary = {}
static var _last: Dictionary = {}
static var _warned: Dictionary = {}
static var _pool: Pool
const Loop := preload("res://scripts/audio/sfx_loop.gd")
static var _rng: RandomNumberGenerator


static func play(tree: SceneTree, preset: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if tree == null or tree.root == null:
		return
	var bank: Array[AudioStreamWAV] = _bank(preset)
	if bank.is_empty():
		return
	var cfg: Dictionary = PRESETS[preset]
	if cfg.get("loop", false):
		_warn_once(preset, "Sfx.play: '%s' is a loop preset, use play_loop" % preset)
		return
	var rng: RandomNumberGenerator = _get_rng()
	var idx: int = 0
	if bank.size() > 1:
		idx = rng.randi_range(0, bank.size() - 1)
		if idx == _last.get(preset, -1):
			idx = (idx + 1 + rng.randi_range(0, bank.size() - 2)) % bank.size()
	_last[preset] = idx
	var pj: float = cfg["pitch_jitter"]
	var dj: float = cfg["db_jitter"]
	_get_pool(tree).play_stream(bank[idx], volume_db + rng.randf_range(-dj, dj), pitch * (1.0 + rng.randf_range(-pj, pj)))


static func has_preset(preset: StringName) -> bool:
	return PRESETS.has(preset)


static func is_loop(preset: StringName) -> bool:
	return PRESETS.has(preset) and bool(PRESETS[preset].get("loop", false))


## Starts a looping preset. Finite position: AudioStreamPlayer3D at that global position; otherwise
## non-positional. Returns the handle (sfx_loop.gd: set_volume_db, stop), or null with one warning
## for an unknown or one-shot preset.
static func play_loop(tree: SceneTree, preset: StringName, volume_db: float = 0.0, position: Vector3 = Vector3.INF) -> Node:
	if tree == null or tree.root == null:
		return null
	if PRESETS.has(preset) and not is_loop(preset):
		_warn_once(preset, "Sfx.play_loop: '%s' is a one-shot preset, use play" % preset)
		return null
	var bank: Array[AudioStreamWAV] = _bank(preset)
	if bank.is_empty():
		return null
	var pool: Pool = _get_pool(tree)
	var handle: Loop = Loop.new()
	var player: Node
	if position.is_finite():
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = LOOP_3D_UNIT_SIZE
		p3.max_db = LOOP_3D_MAX_DB
		p3.max_distance = LOOP_3D_MAX_DISTANCE
		p3.attenuation_filter_db = 0.0
		p3.panning_strength = LOOP_3D_PANNING
		p3.position = position
		player = p3
	else:
		player = AudioStreamPlayer.new()
	player.set(&"bus", BUS)
	player.set(&"stream", bank[_get_rng().randi_range(0, bank.size() - 1)])
	handle.setup(player, volume_db, pool.note_playing)
	pool.add_child(handle)
	return handle


## Empty array warms every preset.
static func warm(presets: Array[StringName] = []) -> void:
	if presets.is_empty():
		for p: StringName in PRESETS:
			_bank(p)
		return
	for p: StringName in presets:
		_bank(p)


## Dev helper: one wav per preset (first variation) plus walk/run step rhythms per surface.
static func export_samples(dir: String) -> int:
	var err: Error = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		push_warning("Sfx.export_samples: cannot create %s (%s)" % [dir, error_string(err)])
		return 0
	var written: int = 0
	for p: StringName in PRESETS:
		written += _save(_bank(p)[0], dir.path_join(String(p) + ".wav"))
		if is_loop(p):
			var cycle: PackedFloat32Array = _render(p, 0)
			var twice := PackedFloat32Array(cycle)
			twice.append_array(cycle)
			written += _save(_to_wav(twice), dir.path_join(String(p) + "_x2.wav"))
	for s: StringName in SURFACES:
		written += _save(_render_sequence(s, false), dir.path_join("step_%s_walk.wav" % s))
		written += _save(_render_sequence(s, true), dir.path_join("step_%s_run.wav" % s))
	return written


# --- Internals ---

static func _get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


static func _get_pool(tree: SceneTree) -> Pool:
	if _pool != null and is_instance_valid(_pool) and not _pool.is_queued_for_deletion():
		return _pool
	_pool = Pool.new()
	_pool.setup(POOL_SIZE, BUS)
	# Deferred so it works while the root is busy setting up children (e.g. from another _ready).
	tree.root.add_child.call_deferred(_pool)
	return _pool


static func _warn_once(preset: StringName, msg: String) -> void:
	if not _warned.has(preset):
		_warned[preset] = true
		push_warning(msg)


static func _bank(preset: StringName) -> Array[AudioStreamWAV]:
	if _banks.has(preset):
		return _banks[preset]
	var bank: Array[AudioStreamWAV] = []
	if not PRESETS.has(preset):
		_warn_once(preset, "Sfx: unknown preset '%s'" % preset)
		return bank
	var loop: bool = is_loop(preset)
	for i: int in int(PRESETS[preset]["variations"]):
		bank.append(_to_wav(_render(preset, i), loop))
	_banks[preset] = bank
	return bank


## Normalized float clip (peak = PEAK * gain) with attack ramp and fade-out applied.
static func _render(preset: StringName, variation: int) -> PackedFloat32Array:
	var cfg: Dictionary = PRESETS[preset]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(preset)) + variation * 7919
	var dur: float = cfg["duration"]
	var xfade: float = cfg.get("xfade", 0.0)
	var s: PackedFloat32Array
	var name: String = String(preset)
	if name.begins_with("step_"):
		s = _synth_foot(StringName(name.trim_prefix("step_")), rng, dur, false)
	elif name.begins_with("land_"):
		s = _synth_foot(StringName(name.trim_prefix("land_")), rng, dur, true)
	else:
		match preset:
			&"skid":
				s = _synth_skid(rng, dur)
			&"run_whoosh":
				s = _synth_whoosh(rng, dur)
			&"jump":
				s = _synth_jump(rng, dur)
			&"thud":
				s = _synth_thud(rng, dur)
			&"ui_pop":
				s = _synth_pop(rng, dur)
			&"ui_select":
				s = _synth_select(rng, dur)
			&"coin_clink":
				s = _synth_coin(rng, dur)
			&"mana_bloop":
				s = _synth_bloop(rng, dur)
			&"collect_whoosh":
				s = _synth_collect(rng, dur)
			&"tree_rustle":
				s = _synth_rustle(rng, dur)
			&"building_thud":
				s = _synth_building(rng, dur)
			&"button_click":
				s = _synth_click(rng, dur)
			&"bell_ding":
				s = _synth_bell(rng, dur)
			&"wood_creak":
				s = _synth_creak(rng, dur)
			&"water_gush":
				s = _synth_gush(rng, dur)
			&"splash_big":
				s = _synth_splash(rng, dur, true)
			&"splash_small":
				s = _synth_splash(rng, dur, false)
			&"water_drip":
				s = _synth_drip(rng, dur)
			&"chime_ready":
				s = _synth_chime(rng, dur)
			&"footstep_water":
				s = _synth_wade(rng, dur)
			&"water_flow":
				s = _synth_stream(rng, dur + xfade, false)
			&"waterfall":
				s = _synth_stream(rng, dur + xfade, true)
			&"rope_creak":
				s = _synth_rope(rng, dur + xfade)
			&"countdown_tick":
				s = _synth_count_tick(rng, dur)
			&"countdown_go":
				s = _synth_count_go(rng, dur)
			&"catapult_fire":
				s = _synth_catapult(rng, dur)
			&"viking_scream":
				s = _synth_scream(rng, dur)
			&"impact_heavy":
				s = _synth_impact(rng, dur)
			&"dizzy_tweet":
				s = _synth_dizzy(rng, dur)
			_:
				s = _synth_tick(rng, dur)
	if cfg.get("loop", false):
		s = _crossfade_loop(s, int(dur * MIX_RATE))
		_finish(s, PEAK * float(cfg["gain"]), 0.0, true)
	else:
		_finish(s, PEAK * float(cfg["gain"]), float(cfg.get("fade", FADE_OUT_SEC)), false)
	return s


## Blends the extra tail (past `n`) into the head with an equal-power fade and keeps `n` samples,
## so sample n-1 flows into sample 0 exactly as it did into sample n.
static func _crossfade_loop(s: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var xf: int = s.size() - n
	for i: int in xf:
		var w: float = float(i) / float(xf) * PI * 0.5
		s[i] = s[i] * sin(w) + s[n + i] * cos(w)
	s.resize(n)
	return s


static func _finish(s: PackedFloat32Array, target_peak: float, fade_sec: float, loop: bool) -> void:
	var n: int = s.size()
	var mean: float = 0.0
	for v: float in s:
		mean += v
	mean /= maxf(1.0, float(n))
	var peak: float = 0.000001
	for i: int in n:
		var v: float = s[i] - mean
		s[i] = v
		peak = maxf(peak, absf(v))
	var k: float = target_peak / peak
	if loop:
		for i: int in n:
			s[i] *= k
		return
	var ramp: int = maxi(1, int(ATTACK_RAMP_SEC * MIX_RATE))
	var fade: int = mini(n, maxi(1, int(fade_sec * MIX_RATE)))
	for i: int in n:
		var g: float = k
		if i < ramp:
			g *= float(i) / float(ramp)
		if i >= n - fade:
			g *= float(n - 1 - i) / float(fade)
		s[i] *= g


static func _to_wav(s: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var n: int = s.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


static func _save(wav: AudioStreamWAV, path: String) -> int:
	var err: Error = wav.save_to_wav(path)
	if err != OK:
		push_warning("Sfx: failed to write %s (%s)" % [path, error_string(err)])
		return 0
	return 1


static func _render_sequence(surface: StringName, running: bool) -> AudioStreamWAV:
	var seq: Dictionary = RUN_SEQ if running else WALK_SEQ
	var preset := StringName("step_" + String(surface))
	var cfg: Dictionary = PRESETS[preset]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(preset)) + (99 if running else 7)
	var count: int = seq["count"]
	var interval: float = seq["interval"]
	var total := PackedFloat32Array()
	total.resize(int((0.05 + interval * count + 0.4) * MIX_RATE))
	var variations: int = cfg["variations"]
	var pj: float = cfg["pitch_jitter"]
	var dj: float = cfg["db_jitter"]
	if running:
		_mix_into(total, _render(&"run_whoosh", 0), 0, 1.0, db_to_linear(float(seq["whoosh_db"])))
	var clips: Array[PackedFloat32Array] = []
	for v: int in variations:
		clips.append(_render(preset, v))
	var last: int = -1
	for k: int in count:
		var idx: int = rng.randi_range(0, variations - 1)
		if idx == last:
			idx = (idx + 1) % variations
		last = idx
		var pitch: float = float(seq["pitch"]) * (1.0 + rng.randf_range(-pj, pj)) + (SEQ_LR_PITCH if k % 2 == 0 else -SEQ_LR_PITCH)
		var gain: float = db_to_linear(float(seq["db"]) + rng.randf_range(-dj, dj))
		_mix_into(total, clips[idx], int((0.05 + interval * k) * MIX_RATE), pitch, gain)
	return _to_wav(total)


static func _mix_into(dst: PackedFloat32Array, clip: PackedFloat32Array, offset: int, pitch: float, gain: float) -> void:
	var len_out: int = int(clip.size() / pitch)
	for i: int in len_out:
		var src: float = i * pitch
		var i0: int = int(src)
		if i0 + 1 >= clip.size() or offset + i >= dst.size():
			break
		dst[offset + i] += lerpf(clip[i0], clip[i0 + 1], src - i0) * gain


## One-pole lowpass coefficient.
static func _a(cutoff: float) -> float:
	return 1.0 - exp(-TAU * minf(cutoff, MIX_RATE * 0.45) / MIX_RATE)


## Per-sample multiplier for an exponential decay with time constant tau.
static func _d(tau: float) -> float:
	return exp(-1.0 / (maxf(tau, 0.00001) * MIX_RATE))


static func _new(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * MIX_RATE))
	return out


## Adds a decaying sine whose frequency glides from f0 to f1 (exponential, time constant glide_tau).
static func _add_ping(out: PackedFloat32Array, start: float, f0: float, f1: float, glide_tau: float, tau: float, amp: float, attack: float = 0.0015) -> void:
	var fs: float = float(MIX_RATE)
	var i0: int = int(start * fs)
	var n: int = mini(out.size() - i0, int(tau * 7.0 * fs))
	var env: float = amp
	var dk: float = _d(tau)
	var gk: float = _d(glide_tau)
	var g: float = 1.0
	var phase: float = 0.0
	var atk_n: float = maxf(1.0, attack * fs)
	var nyq: float = fs * 0.45
	for i: int in n:
		var f: float = f1 + (f0 - f1) * g
		if f >= nyq:
			break
		phase += TAU * f / fs
		out[i0 + i] += sin(phase) * env * minf(1.0, float(i) / atk_n)
		env *= dk
		g *= gk


# --- Synthesis ---

static func _synth_foot(surface: StringName, rng: RandomNumberGenerator, dur: float, heavy: bool) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.88, 1.12)
	var dk: float = rng.randf_range(0.85, 1.2) * (1.7 if heavy else 1.0)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var lp3: float = 0.0
	var grain: float = 0.0
	var grain_k: float = _d(0.003 * rng.randf_range(0.7, 1.4))
	var attack_n: float = rng.randf_range(0.002, 0.005) * fs
	var f0: float = float({&"grass": 85.0, &"dirt": 105.0, &"wood": 120.0, &"stone": 140.0}[surface]) * j * (0.62 if heavy else 1.0)
	var thump_amp: float = (0.85 if heavy else 0.4) * rng.randf_range(0.8, 1.2)
	var thump_phase: float = 0.0
	var thump_env: float = thump_amp
	var thump_k: float = _d((0.034 if heavy else 0.024) * dk)
	var glide: float = 0.7 if not heavy else 0.9
	var glide_k: float = _d(0.012 if not heavy else 0.02)
	var body_env: float = 1.0
	var tail_env: float = 1.0
	var a_body_hi: float
	var a_body_lo: float
	var body_k: float
	var tail_k: float
	var a_hp: float
	var grain_p: float
	match surface:
		&"grass":
			a_body_hi = _a(850.0 * j * rng.randf_range(0.85, 1.15))
			a_body_lo = _a(320.0)
			body_k = _d(0.035 * dk)
			tail_k = _d(0.07 * dk)
			a_hp = _a(2600.0 * rng.randf_range(0.85, 1.2))
			grain_p = (0.02 if heavy else 0.012) * DENSITY
		&"dirt":
			a_body_hi = _a(1900.0 * j * rng.randf_range(0.85, 1.15))
			a_body_lo = _a(700.0)
			body_k = _d(0.022 * dk)
			tail_k = _d(0.05 * dk)
			a_hp = _a(2400.0 * rng.randf_range(0.85, 1.2))
			grain_p = (0.12 if heavy else 0.09) * DENSITY
		&"wood":
			a_body_hi = _a(3000.0)
			a_body_lo = _a(600.0 * rng.randf_range(0.85, 1.15))
			body_k = _d(0.004)
			tail_k = _d(0.015 * dk)
			a_hp = 0.0
			grain_p = 0.0
		_:
			a_body_hi = _a(2200.0 * rng.randf_range(0.9, 1.1))
			a_body_lo = 0.0
			body_k = _d(0.0035)
			tail_k = _d(0.03 * dk)
			a_hp = 0.0
			grain_p = (0.07 if heavy else 0.05) * DENSITY
	var tone_f := PackedFloat32Array()
	var tone_k := PackedFloat32Array()
	var tone_a := PackedFloat32Array()
	var tone_ph := PackedFloat32Array()
	if surface == &"wood":
		var wf: float = 0.8 if heavy else 1.0
		tone_f = PackedFloat32Array([190.0 * j * wf, 430.0 * j * wf * rng.randf_range(0.93, 1.07), 1050.0 * j * wf * rng.randf_range(0.95, 1.05)])
		tone_k = PackedFloat32Array([_d(0.075 * dk), _d(0.045 * dk), _d(0.018 * dk)])
		tone_a = PackedFloat32Array([0.7, 0.45 * rng.randf_range(0.7, 1.3), 0.2 * rng.randf_range(0.6, 1.4)])
	elif surface == &"stone":
		tone_f = PackedFloat32Array([1650.0 * j, 2550.0 * j * rng.randf_range(0.96, 1.04), 3400.0 * j * rng.randf_range(0.96, 1.04)])
		tone_k = PackedFloat32Array([_d(0.014), _d(0.011), _d(0.008)])
		tone_a = PackedFloat32Array([0.32, 0.24, 0.16])
	for r: int in tone_f.size():
		tone_ph.append(rng.randf() * TAU)
	var tones: int = tone_f.size()
	var tone_w := PackedFloat32Array()
	for r: int in tones:
		tone_w.append(TAU * tone_f[r] / fs)
	var g: float = 1.0
	for i: int in n:
		var t: float = float(i) / fs
		var noise: float = rng.randf_range(-1.0, 1.0)
		thump_phase += TAU * f0 * (1.0 + glide * g) / fs
		g *= glide_k
		var v: float = sin(thump_phase) * thump_env
		thump_env *= thump_k
		match surface:
			&"grass":
				lp1 += a_body_hi * (noise - lp1)
				lp2 += a_body_lo * (lp1 - lp2)
				v += (lp1 - lp2) * body_env * 1.6
				if rng.randf() < grain_p * tail_env:
					grain = rng.randf_range(0.4, 1.0)
				grain *= grain_k
				lp3 += a_hp * (noise - lp3)
				v += (noise - lp3) * grain * 0.5 * minf(1.0, t / 0.015)
			&"dirt":
				lp1 += a_body_hi * (noise - lp1)
				lp2 += a_body_lo * (lp1 - lp2)
				v += (lp1 - lp2) * body_env * 1.4
				var grit: float = rng.randf_range(-1.0, 1.0) if rng.randf() < grain_p * tail_env else 0.0
				lp3 += a_hp * (grit - lp3)
				v += (grit - lp3) * 0.9 * minf(1.0, t / 0.006)
			&"wood":
				var excite: float = noise * body_env
				lp1 += a_body_hi * (excite - lp1)
				v += (excite - lp1) * 0.55
				lp2 += a_body_lo * (noise - lp2)
				v += lp2 * tail_env * 0.9
				for r: int in tones:
					v += sin(tone_ph[r] + tone_w[r] * i) * tone_a[r]
					tone_a[r] *= tone_k[r]
			_:
				var excite: float = noise * body_env
				lp1 += a_body_hi * (excite - lp1)
				v += (excite - lp1) * 1.1
				for r: int in tones:
					v += sin(tone_ph[r] + tone_w[r] * i) * tone_a[r]
					tone_a[r] *= tone_k[r]
				if rng.randf() < grain_p * tail_env:
					v += rng.randf_range(-0.35, 0.35)
		body_env *= body_k
		tail_env *= tail_k
		out[i] = v * minf(1.0, float(i) / attack_n)
	return out


static func _synth_skid(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var lp_r: float = 0.0
	var lp_g: float = 0.0
	var burst: float = 0.0
	var burst_k: float = _d(0.004)
	var a_r: float = _a(260.0)
	var a_g: float = _a(3200.0)
	var p_burst: float = 0.012 * DENSITY
	var p_grit: float = 0.035 * DENSITY
	for i: int in n:
		var x: float = float(i) / float(n)
		var t: float = float(i) / fs
		var center: float = (2600.0 - 1500.0 * x) * j
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_a += _a(center * 1.3) * (noise - lp_a)
		lp_b += _a(center * 0.5) * (lp_a - lp_b)
		if rng.randf() < p_burst:
			burst = rng.randf_range(0.3, 1.0)
		burst *= burst_k
		var scrape: float = (lp_a - lp_b) * (0.45 + burst) * 1.6
		lp_r += a_r * (noise - lp_r)
		var grit: float = rng.randf_range(-1.0, 1.0) if rng.randf() < p_grit else 0.0
		lp_g += a_g * (grit - lp_g)
		var env: float = minf(1.0, t / 0.015) * pow(1.0 - x, 1.4)
		out[i] = (scrape + lp_r * 1.4 + (grit - lp_g) * 0.6) * env
	return out


static func _synth_whoosh(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var flutter_hz: float = rng.randf_range(30.0, 45.0)
	var flutter_depth: float = rng.randf_range(0.2, 0.4)
	var lp: float = 0.0
	var lp_low: float = 0.0
	for i: int in n:
		var t: float = float(i) / fs
		var x: float = float(i) / float(n)
		var center: float = (500.0 + 1700.0 * sin(PI * pow(x, 0.7))) * j
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp += _a(center * 1.4) * (noise - lp)
		lp_low += _a(center * 0.6) * (lp - lp_low)
		var env: float = sqrt(x) * pow(1.0 - x, 1.6)
		out[i] = (lp - lp_low) * env * (1.0 + flutter_depth * sin(TAU * flutter_hz * t))
	return out


static func _synth_jump(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var lp: float = 0.0
	var lp_low: float = 0.0
	var lp_flap: float = 0.0
	var a_flap: float = _a(1400.0 * j)
	var flap2: float = rng.randf_range(0.038, 0.05)
	for i: int in n:
		var t: float = float(i) / fs
		var x: float = float(i) / float(n)
		var center: float = 500.0 * j * pow(5.2, x)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp += _a(center * 1.4) * (noise - lp)
		lp_low += _a(center * 0.55) * (lp - lp_low)
		var env: float = pow(x, 0.35) * pow(1.0 - x, 2.2)
		lp_flap += a_flap * (noise - lp_flap)
		var u1: float = (t - 0.012) / 0.006
		var u2: float = (t - flap2) / 0.007
		var flap_env: float = exp(-u1 * u1) + 0.7 * exp(-u2 * u2) if t < 0.08 else 0.0
		out[i] = (lp - lp_low) * env * 2.2 + lp_flap * flap_env * 0.5
	return out


static func _synth_thud(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var phase: float = 0.0
	var lp: float = 0.0
	var a_lp: float = _a(420.0 * j)
	var g: float = 1.0
	var g_k: float = _d(0.02)
	var body: float = 1.0
	var body_k: float = _d(0.075 * rng.randf_range(0.85, 1.15))
	var knock: float = 0.35
	var knock_k: float = _d(0.04)
	var dust: float = 1.6
	var dust_k: float = _d(0.045)
	var knock_w: float = TAU * 175.0 * j * rng.randf_range(0.93, 1.07) / fs
	for i: int in n:
		phase += TAU * 58.0 * j * (1.0 + g) / fs
		g *= g_k
		lp += a_lp * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] = sin(phase) * body + sin(knock_w * i) * knock + lp * dust
		body *= body_k
		knock *= knock_k
		dust *= dust_k
	return out


static func _synth_pop(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var f0: float = 380.0 * rng.randf_range(0.92, 1.08)
	var rise: float = rng.randf_range(1.4, 1.8)
	var g: float = 1.0
	var g_k: float = _d(0.025)
	var env: float = 1.0
	var env_k: float = _d(0.032)
	var phase: float = 0.0
	var lp: float = 0.0
	var a_lp: float = _a(1800.0)
	var click: float = 0.25
	var click_k: float = _d(0.0012)
	for i: int in n:
		phase += TAU * f0 * (1.0 + rise * (1.0 - g)) / fs
		g *= g_k
		lp += a_lp * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] = (sin(phase) + 0.18 * sin(2.0 * phase)) * env * minf(1.0, float(i) / (0.002 * fs)) + lp * click
		env *= env_k
		click *= click_k
	return out


static func _synth_select(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var notes: Array[Vector3] = [Vector3(0.0, 1046.5, 1.0), Vector3(0.075, 1568.0, 0.85)]
	for k: int in notes.size():
		var start: float = notes[k].x
		var f: float = notes[k].y
		var amp: float = notes[k].z
		var tau: float = 0.16 if k == 0 else 0.22
		_add_ping(out, start, f, f, 1.0, tau, amp, 0.003)
		_add_ping(out, start, f * 2.0, f * 2.0, 1.0, tau * 0.5, amp * 0.3, 0.003)
		_add_ping(out, start, f * 3.0, f * 3.0, 1.0, tau * 0.3, amp * 0.1, 0.003)
		_add_ping(out, start, f * 4.2, f * 4.2, 1.0, 0.02, amp * 0.05, 0.002)
		_add_ping(out, start, f * 1.003, f * 1.003, 1.0, tau, amp * 0.2, 0.003)
	return out


static func _synth_coin(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var f0: float = 1700.0 * rng.randf_range(0.94, 1.06)
	var ratios := PackedFloat32Array([1.0, 2.32, 4.25, 6.63])
	var amps := PackedFloat32Array([1.0, 0.6, 0.35, 0.2])
	var taus := PackedFloat32Array([0.18, 0.09, 0.05, 0.03])
	var hits: Array[Vector3] = [Vector3(0.0, 1.0, 1.0), Vector3(rng.randf_range(0.05, 0.075), rng.randf_range(1.04, 1.08), rng.randf_range(0.5, 0.7))]
	for h: Vector3 in hits:
		var f: float = f0 * h.y
		for r: int in ratios.size():
			var fr: float = f * ratios[r] * rng.randf_range(0.995, 1.005)
			_add_ping(out, h.x, fr, fr, 1.0, taus[r], amps[r] * h.z, 0.0008)
		_add_ping(out, h.x, f * 1.004, f * 1.004, 1.0, taus[0], 0.3 * h.z, 0.0008)
		var i0: int = int(h.x * MIX_RATE)
		var lp: float = 0.0
		var a_lp: float = _a(4000.0)
		var env: float = 0.5 * h.z
		var env_k: float = _d(0.001)
		for i: int in mini(int(0.008 * MIX_RATE), out.size() - i0):
			var noise: float = rng.randf_range(-1.0, 1.0)
			lp += a_lp * (noise - lp)
			out[i0 + i] += (noise - lp) * env
			env *= env_k
	return out


static func _synth_bloop(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var f0: float = 260.0 * rng.randf_range(0.92, 1.08)
	var wob_hz: float = rng.randf_range(7.5, 10.5)
	var phase: float = 0.0
	var lp: float = 0.0
	var a_lp: float = _a(2500.0)
	for i: int in n:
		var t: float = float(i) / fs
		var x: float = float(i) / float(n)
		var rise: float = smoothstep(0.0, 0.12, t)
		var wob: float = 1.0 + (0.04 + 0.06 * x) * sin(TAU * wob_hz * t)
		phase += TAU * f0 * (1.0 + 1.4 * rise) * wob / fs
		var tone: float = sin(phase) + 0.25 * sin(2.0 * phase)
		lp += a_lp * (tone - lp)
		out[i] = lp * minf(1.0, t / 0.008) * pow(1.0 - x, 1.8)
	for b: int in 3:
		var bf: float = rng.randf_range(850.0, 1100.0)
		_add_ping(out, rng.randf_range(0.05, dur * 0.8), bf, bf * 2.0, 0.015, 0.015, 0.25, 0.002)
	return out


static func _synth_collect(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.92, 1.08)
	var lp: float = 0.0
	var lp_low: float = 0.0
	for i: int in n:
		var x: float = float(i) / float(n)
		var center: float = 350.0 * j * pow(10.0, x)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp += _a(center * 1.4) * (noise - lp)
		lp_low += _a(center * 0.55) * (lp - lp_low)
		out[i] = (lp - lp_low) * pow(x, 1.2) * pow(1.0 - x, 0.8) * 2.5
	for k: int in 6:
		var f: float = rng.randf_range(2800.0, 6000.0)
		_add_ping(out, rng.randf_range(0.25, dur * 0.88), f, f, 1.0, 0.035, rng.randf_range(0.3, 0.5), 0.001)
	return out


static func _synth_rustle(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var lp_hp: float = 0.0
	var lp_soft: float = 0.0
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var a_hp: float = _a(1800.0 * rng.randf_range(0.85, 1.15))
	var a_soft: float = _a(6000.0)
	var a_sw_hi: float = _a(1500.0)
	var a_sw_lo: float = _a(500.0)
	var grain: float = 0.0
	var grain_k: float = _d(0.004)
	var p: float = 0.02 * DENSITY
	var peak_at: float = rng.randf_range(0.35, 0.55)
	for i: int in n:
		var x: float = float(i) / float(n)
		var dens: float = pow(sin(PI * pow(x, log(0.5) / log(peak_at))), 1.5)
		var noise: float = rng.randf_range(-1.0, 1.0)
		if rng.randf() < p * dens:
			grain = rng.randf_range(0.3, 1.0)
			grain_k = _d(rng.randf_range(0.002, 0.006))
		grain *= grain_k
		lp_hp += a_hp * (noise - lp_hp)
		var hi: float = noise - lp_hp
		lp_soft += a_soft * (hi - lp_soft)
		lp_a += a_sw_hi * (noise - lp_a)
		lp_b += a_sw_lo * (lp_a - lp_b)
		out[i] = lp_soft * grain + (lp_a - lp_b) * dens * 0.35
	return out


static func _synth_building(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var phase: float = 0.0
	var g: float = 1.0
	var g_k: float = _d(0.025)
	var body: float = 1.0
	var body_k: float = _d(0.11)
	var lp: float = 0.0
	var a_lp: float = _a(380.0)
	var dust: float = 1.4
	var dust_k: float = _d(0.06)
	for i: int in n:
		phase += TAU * 48.0 * j * (1.0 + 1.2 * g) / fs
		g *= g_k
		lp += a_lp * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] = sin(phase) * body * minf(1.0, float(i) / (0.002 * fs)) + lp * dust
		body *= body_k
		dust *= dust_k
	var knock_f := PackedFloat32Array([115.0, 260.0, 590.0])
	var knock_t := PackedFloat32Array([0.09, 0.06, 0.03])
	var knock_a := PackedFloat32Array([0.45, 0.3, 0.15])
	for r: int in 3:
		var f: float = knock_f[r] * j * rng.randf_range(0.95, 1.05)
		_add_ping(out, 0.0, f, f, 1.0, knock_t[r], knock_a[r], 0.002)
	var cs: float = rng.randf_range(0.1, 0.14)
	_add_creak(out, rng, cs, minf(0.3, dur - cs - 0.02), 820.0 * j, 1450.0 * j, 70.0, 45.0, 0.0, 0.3)
	return out


static func _synth_tick(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var f: float = 1900.0 * rng.randf_range(0.97, 1.03)
	_add_ping(out, 0.0, f, f, 1.0, 0.007, 1.0, 0.0006)
	_add_ping(out, 0.0, f * 2.7, f * 2.7, 1.0, 0.003, 0.15, 0.0006)
	return out


## Stick-slip impulse train through two resonators; pulse rate goes rate_a -> rate_b with a bump.
static func _add_creak(out: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, f1: float, f2: float, rate_a: float, rate_b: float, rate_bump: float, amp: float) -> void:
	var fs: float = float(MIX_RATE)
	var n: int = out.size()
	var i0: int = int(start * fs)
	var cn: int = int(length * fs)
	var w1: float = TAU * f1 * rng.randf_range(0.9, 1.1) / fs
	var w2: float = TAU * f2 * rng.randf_range(0.9, 1.1) / fs
	var r1: float = 0.993
	var r2: float = 0.99
	var c1: float = 2.0 * r1 * cos(w1)
	var c2: float = 2.0 * r2 * cos(w2)
	var s1: float = sin(w1)
	var s2: float = sin(w2)
	var y1a: float = 0.0
	var y1b: float = 0.0
	var y2a: float = 0.0
	var y2b: float = 0.0
	var next_pulse: float = 0.0
	for i: int in cn:
		if i0 + i >= n:
			break
		var u: float = float(i) / float(cn)
		var imp: float = 0.0
		if float(i) >= next_pulse:
			imp = rng.randf_range(0.5, 1.0)
			var rate: float = (lerpf(rate_a, rate_b, u) + rate_bump * sin(PI * u)) * rng.randf_range(0.85, 1.15)
			next_pulse = float(i) + fs / rate
		var ya: float = imp * s1 + c1 * y1a - r1 * r1 * y1b
		y1b = y1a
		y1a = ya
		var yb: float = imp * s2 + c2 * y2a - r2 * r2 * y2b
		y2b = y2a
		y2a = yb
		out[i0 + i] += (ya + 0.6 * yb) * sin(PI * u) * amp


## Rising-pitch bubble pings scattered over [t0, t1].
static func _add_bubbles(out: PackedFloat32Array, rng: RandomNumberGenerator, count: int, t0: float, t1: float, f_lo: float, f_hi: float, rise: float, tau_lo: float, tau_hi: float, amp_lo: float, amp_hi: float) -> void:
	for k: int in count:
		var f: float = rng.randf_range(f_lo, f_hi)
		var tau: float = rng.randf_range(tau_lo, tau_hi)
		_add_ping(out, rng.randf_range(t0, t1), f, f * rise, tau * 0.8, tau, rng.randf_range(amp_lo, amp_hi), 0.001)


static func _synth_click(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var j: float = rng.randf_range(0.94, 1.06)
	for h: int in 2:
		var start: float = 0.0 if h == 0 else rng.randf_range(0.024, 0.03)
		var a: float = 1.0 if h == 0 else 0.45
		var fm: float = 1.0 if h == 0 else 1.18
		_add_ping(out, start, 1500.0 * j * fm, 1500.0 * j * fm, 1.0, 0.004, 0.5 * a, 0.0004)
		_add_ping(out, start, 320.0 * j * fm, 320.0 * j * fm, 1.0, 0.006, 0.4 * a, 0.0006)
		var i0: int = int(start * MIX_RATE)
		var lp: float = 0.0
		var a_lp: float = _a(2000.0)
		var env: float = 0.6 * a
		var env_k: float = _d(0.0006)
		for i: int in mini(int(0.005 * MIX_RATE), out.size() - i0):
			var noise: float = rng.randf_range(-1.0, 1.0)
			lp += a_lp * (noise - lp)
			out[i0 + i] += (noise - lp) * env
			env *= env_k
	return out


static func _synth_bell(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var f0: float = 1320.0 * rng.randf_range(0.97, 1.03)
	var ratios := PackedFloat32Array([1.0, 2.0, 2.76, 4.07, 5.4])
	var amps := PackedFloat32Array([1.0, 0.45, 0.3, 0.15, 0.08])
	var taus := PackedFloat32Array([0.4, 0.25, 0.14, 0.07, 0.045])
	for r: int in ratios.size():
		var f: float = f0 * ratios[r]
		_add_ping(out, 0.0, f, f, 1.0, taus[r], amps[r], 0.001)
	_add_ping(out, 0.0, f0 * 1.002, f0 * 1.002, 1.0, taus[0], 0.4, 0.001)
	return out


static func _synth_creak(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var j: float = rng.randf_range(0.88, 1.12)
	_add_creak(out, rng, 0.0, dur - 0.01, 600.0 * j, 1100.0 * j, rng.randf_range(32.0, 40.0), rng.randf_range(45.0, 55.0), rng.randf_range(30.0, 45.0), 1.0)
	return out


## Smoothed random LFO in [-1, 1]: a new target every `hold` seconds, one-pole glide at `rate` Hz.
static func _lfo(rng: RandomNumberGenerator, n: int, hold: float, rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var a: float = _a(rate)
	var v: float = 0.0
	var target: float = rng.randf_range(-1.0, 1.0)
	var next: int = 0
	for i: int in n:
		if i >= next:
			target = rng.randf_range(-1.0, 1.0)
			next = i + int(hold * rng.randf_range(0.6, 1.4) * MIX_RATE)
		v += a * (target - v)
		out[i] = v
	return out


static func _synth_gush(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var lfo: PackedFloat32Array = _lfo(rng, n, 0.09, 12.0)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var lp_h: float = 0.0
	var a_hi: float = _a(1600.0 * rng.randf_range(0.9, 1.1))
	var a_lo: float = _a(120.0)
	var a_h: float = _a(3000.0)
	for i: int in n:
		var x: float = float(i) / float(n)
		var t: float = float(i) / MIX_RATE
		var env: float = minf(1.0, t / 0.03) * (1.0 if x < 0.6 else pow((1.0 - x) / 0.4, 1.5))
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		lp_h += a_h * (noise - lp_h)
		out[i] = ((lp_a - lp_b) * 1.2 * (1.0 + 0.25 * lfo[i]) + (noise - lp_h) * 0.35) * env
	_add_bubbles(out, rng, 45, 0.02, dur * 0.65, 200.0, 1000.0, 1.8, 0.01, 0.03, 0.1, 0.25)
	_add_bubbles(out, rng, 10, dur * 0.6, dur * 0.9, 300.0, 900.0, 1.6, 0.01, 0.025, 0.05, 0.12)
	return out


static func _synth_splash(rng: RandomNumberGenerator, dur: float, big: bool) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var lp_h: float = 0.0
	var a_hi: float = _a((1800.0 if big else 3500.0) * j)
	var a_lo: float = _a(150.0 if big else 400.0)
	var a_h: float = _a(2500.0)
	var body_tau: float = 0.14 if big else 0.06
	var spray_tau: float = 0.22 if big else 0.09
	var phase: float = 0.0
	var thump_f: float = 65.0 * j
	var thump: float = 0.9 if big else 0.0
	var thump_k: float = _d(0.06)
	var g: float = 1.0
	var g_k: float = _d(0.03)
	for i: int in n:
		var t: float = float(i) / fs
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		lp_h += a_h * (noise - lp_h)
		var body: float = (lp_a - lp_b) * minf(1.0, t / 0.006) * exp(-t / body_tau) * 1.4
		var spray: float = (noise - lp_h) * (1.0 - exp(-t / 0.02)) * exp(-t / spray_tau) * (0.6 if big else 0.5)
		phase += TAU * thump_f * (1.0 + 0.8 * g) / fs
		g *= g_k
		out[i] = body + spray + sin(phase) * thump
		thump *= thump_k
	if big:
		_add_bubbles(out, rng, 25, 0.04, dur * 0.75, 250.0, 1100.0, 1.7, 0.015, 0.04, 0.1, 0.3)
		_add_bubbles(out, rng, 8, 0.3, dur * 0.85, 1500.0, 3000.0, 1.4, 0.008, 0.015, 0.05, 0.12)
	else:
		_add_bubbles(out, rng, 8, 0.04, dur * 0.85, 1200.0, 2800.0, 1.5, 0.008, 0.012, 0.12, 0.25)
	return out


static func _synth_drip(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var f: float = rng.randf_range(1000.0, 1600.0)
	_add_ping(out, 0.0, f, f * rng.randf_range(2.0, 2.4), 0.012, 0.025, 1.0, 0.0008)
	var lp: float = 0.0
	var a_lp: float = _a(900.0)
	var env: float = 0.15
	var env_k: float = _d(0.002)
	for i: int in mini(int(0.012 * MIX_RATE), out.size()):
		lp += a_lp * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] += lp * env
		env *= env_k
	return out


static func _synth_chime(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var notes := PackedFloat32Array([1046.5, 1318.5, 1568.0, 2093.0])
	var amps := PackedFloat32Array([0.8, 0.8, 0.85, 0.6])
	for k: int in notes.size():
		var start: float = 0.07 * k
		var f: float = notes[k]
		var tau: float = 0.35 if k == notes.size() - 1 else 0.25
		_add_ping(out, start, f, f, 1.0, tau, amps[k], 0.003)
		_add_ping(out, start, f * 2.0, f * 2.0, 1.0, tau * 0.45, amps[k] * 0.25, 0.003)
		_add_ping(out, start, f * 3.0, f * 3.0, 1.0, tau * 0.25, amps[k] * 0.08, 0.003)
		_add_ping(out, start, f * 1.003, f * 1.003, 1.0, tau, amps[k] * 0.2, 0.003)
	return out


static func _synth_wade(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.88, 1.12)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var lp_h: float = 0.0
	var a_hi: float = _a(1400.0 * j)
	var a_lo: float = _a(250.0)
	var a_h: float = _a(3000.0)
	var hump2_t: float = rng.randf_range(0.11, 0.15)
	var hump2_a: float = rng.randf_range(0.45, 0.75)
	var phase: float = 0.0
	var thump: float = 0.35
	var thump_k: float = _d(0.03)
	for i: int in n:
		var t: float = float(i) / fs
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		lp_h += a_h * (noise - lp_h)
		var u: float = (t - hump2_t) / 0.04
		var slosh_env: float = minf(1.0, t / 0.005) * exp(-t / 0.05) + hump2_a * exp(-u * u)
		phase += TAU * 90.0 * j / fs
		out[i] = (lp_a - lp_b) * slosh_env * 1.5 + (noise - lp_h) * exp(-t / 0.04) * 0.4 + sin(phase) * thump
		thump *= thump_k
	_add_bubbles(out, rng, rng.randi_range(4, 6), 0.02, dur * 0.7, 500.0, 1300.0, 1.6, 0.012, 0.025, 0.15, 0.3)
	return out


static func _synth_stream(rng: RandomNumberGenerator, dur: float, heavy: bool) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var lfo1: PackedFloat32Array = _lfo(rng, n, 0.25 if heavy else 0.18, 3.0 if heavy else 5.0)
	var lfo2: PackedFloat32Array = _lfo(rng, n, 0.07, 14.0)
	var lp_r: float = 0.0
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var lp_h: float = 0.0
	var a_r: float = _a(500.0)
	var a_hi: float = _a(2200.0 if heavy else 900.0)
	var a_lo: float = _a(300.0 if heavy else 120.0)
	var a_h: float = _a(4000.0 if heavy else 2500.0)
	var roar: float = 1.4 if heavy else 0.0
	var band: float = 1.0
	var hiss: float = 0.3 if heavy else 0.25
	var am1: float = 0.12 if heavy else 0.3
	for i: int in n:
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_r += a_r * (noise - lp_r)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		lp_h += a_h * (noise - lp_h)
		out[i] = lp_r * roar * (1.0 + 0.1 * lfo2[i]) + (lp_a - lp_b) * band * (1.0 + am1 * lfo1[i]) + (noise - lp_h) * hiss * (1.0 + 0.3 * lfo2[i])
	if heavy:
		_add_bubbles(out, rng, int(15.0 * dur), 0.0, dur - 0.05, 250.0, 800.0, 1.5, 0.015, 0.03, 0.05, 0.12)
	else:
		_add_bubbles(out, rng, int(18.0 * dur), 0.0, dur - 0.05, 350.0, 1400.0, 1.5, 0.01, 0.03, 0.15, 0.35)
	return out


static func _synth_count_tick(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var f: float = 880.0 * (1.0 if rng.randf() < 0.5 else 1.02)
	_add_ping(out, 0.0, f * 1.04, f, 0.004, 0.03, 1.0, 0.0006)
	_add_ping(out, 0.0, f * 2.4, f * 2.4, 1.0, 0.01, 0.35, 0.0006)
	_add_ping(out, 0.0, f * 0.5, f * 0.5, 1.0, 0.015, 0.3, 0.0008)
	var lp: float = 0.0
	var a_lp: float = _a(2500.0)
	var env: float = 0.5
	var env_k: float = _d(0.0008)
	for i: int in mini(int(0.006 * MIX_RATE), out.size()):
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp += a_lp * (noise - lp)
		out[i] += (noise - lp) * env
		env *= env_k
	return out


static func _synth_count_go(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var notes := PackedFloat32Array([1318.5, 1975.5, 2637.0])
	var amps := PackedFloat32Array([1.0, 0.75, 0.45])
	for k: int in notes.size():
		var f: float = notes[k]
		_add_ping(out, 0.0, f * 0.92, f, 0.02, 0.28, amps[k], 0.002)
		_add_ping(out, 0.0, f * 2.0 * 0.92, f * 2.0, 0.02, 0.12, amps[k] * 0.2, 0.002)
		_add_ping(out, 0.0, f * 1.004, f * 1.004, 1.0, 0.28, amps[k] * 0.25, 0.002)
	for k: int in 4:
		var f: float = rng.randf_range(3500.0, 6500.0)
		_add_ping(out, rng.randf_range(0.04, 0.3), f, f, 1.0, 0.03, rng.randf_range(0.15, 0.3), 0.001)
	return out


static func _synth_rope(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var t: float = rng.randf_range(0.0, 0.15)
	while t < dur - 0.15:
		var length: float = rng.randf_range(0.18, 0.6)
		var f1: float = rng.randf_range(380.0, 700.0)
		_add_creak(out, rng, t, minf(length, dur - t), f1, f1 * rng.randf_range(1.7, 2.1), rng.randf_range(25.0, 45.0), rng.randf_range(35.0, 70.0), rng.randf_range(0.0, 40.0), rng.randf_range(0.5, 1.0))
		t += length * rng.randf_range(0.6, 1.3) + rng.randf_range(0.05, 0.35)
	# Faint fiber rustle under the creaks.
	var lfo: PackedFloat32Array = _lfo(rng, n, 0.2, 4.0)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var a_hi: float = _a(1800.0)
	var a_lo: float = _a(400.0)
	for i: int in n:
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		out[i] += (lp_a - lp_b) * 0.06 * (1.0 + 0.6 * lfo[i])
	return out


static func _synth_catapult(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var lp_c: float = 0.0
	var a_c: float = _a(1800.0)
	var crack: float = 1.4
	var crack_k: float = _d(0.0015)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var phase: float = 0.0
	var thump: float = 0.8
	var thump_k: float = _d(0.04)
	var g: float = 1.0
	var g_k: float = _d(0.015)
	for i: int in n:
		var t: float = float(i) / fs
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_c += a_c * (noise - lp_c)
		var v: float = (noise - lp_c) * crack
		crack *= crack_k
		phase += TAU * 80.0 * j * (1.0 + g) / fs
		g *= g_k
		v += sin(phase) * thump
		thump *= thump_k
		if t > 0.02:
			var x: float = (t - 0.02) / (dur - 0.02)
			var center: float = (2500.0 - 2000.0 * sqrt(x)) * j
			lp_a += _a(center * 1.4) * (noise - lp_a)
			lp_b += _a(center * 0.55) * (lp_a - lp_b)
			v += (lp_a - lp_b) * minf(1.0, (t - 0.02) / 0.05) * pow(1.0 - x, 1.6) * 1.8
		out[i] = v
	_add_ping(out, 0.0, 620.0 * j, 600.0 * j, 0.01, 0.025, 0.5, 0.0005)
	_add_ping(out, 0.0, 1400.0 * j, 1400.0 * j, 1.0, 0.012, 0.3, 0.0005)
	_add_ping(out, 0.005, 165.0 * j, 160.0 * j, 0.05, 0.12, 0.25, 0.002)
	return out


## Peak magnitude normalizer for a two-pole resonator at angular frequency w with pole radius r.
static func _reso_norm(w: float, r: float) -> float:
	var c1: float = 2.0 * r * cos(w)
	var re: float = 1.0 - c1 * cos(w) + r * r * cos(2.0 * w)
	var im: float = c1 * sin(w) - r * r * sin(2.0 * w)
	return sqrt(re * re + im * im)


static func _synth_scream(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var f_start: float = rng.randf_range(215.0, 255.0)
	var f_end: float = rng.randf_range(115.0, 130.0)
	var vib_hz: float = rng.randf_range(5.0, 7.0)
	var form_a := PackedFloat32Array([800.0, 1200.0, 2550.0, 3500.0])
	var form_o := PackedFloat32Array([700.0, 1080.0, 2500.0, 3400.0])
	var bws := PackedFloat32Array([90.0, 100.0, 130.0, 170.0])
	var gains := PackedFloat32Array([1.0, 0.6, 0.35, 0.15])
	var fj: float = rng.randf_range(0.97, 1.04)
	var c1 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var c2 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var b := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var y1 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var y2 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var phase: float = 0.0
	var lp_br: float = 0.0
	var a_br: float = _a(3000.0)
	var lp_src: float = 0.0
	var a_src: float = _a(4000.0)
	var jitter: float = 0.0
	for i: int in n:
		var t: float = float(i) / fs
		var x: float = float(i) / float(n)
		if i % 64 == 0:
			var vowel: float = smoothstep(0.55, 1.0, x)
			for k: int in 4:
				var f: float = lerpf(form_a[k], form_o[k], vowel) * fj
				var r: float = exp(-PI * bws[k] / fs)
				var w: float = TAU * f / fs
				c1[k] = 2.0 * r * cos(w)
				c2[k] = -r * r
				b[k] = _reso_norm(w, r) * gains[k]
			jitter += 0.3 * (rng.randf_range(-1.0, 1.0) - jitter)
		var lift: float = 1.0 + 0.06 * sin(PI * minf(1.0, t / 0.35))
		var f0: float = lerpf(f_start, f_end, smoothstep(0.2, dur, t)) * lift
		var vib: float = 1.0 + (0.025 + 0.06 * x) * sin(TAU * vib_hz * t) + 0.004 * jitter
		phase += f0 * vib / fs
		phase -= floorf(phase)
		lp_src += a_src * ((2.0 * phase - 1.0) - lp_src)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp_br += a_br * (noise - lp_br)
		var env: float = minf(1.0, t / 0.04) * (1.0 if x < 0.55 else pow((1.0 - x) / 0.45, 1.3))
		var src: float = lp_src + lp_br * (0.15 + 0.2 * x)
		var v: float = 0.0
		for k: int in 4:
			var y: float = b[k] * src + c1[k] * y1[k] + c2[k] * y2[k]
			y2[k] = y1[k]
			y1[k] = y
			v += y
		out[i] = v * env * (1.0 + 0.12 * sin(TAU * vib_hz * t))
	return out


static func _synth_impact(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var n: int = out.size()
	var j: float = rng.randf_range(0.9, 1.1)
	var phase: float = 0.0
	var g: float = 1.0
	var g_k: float = _d(0.03)
	var body: float = 1.2
	var body_k: float = _d(0.14 * rng.randf_range(0.9, 1.1))
	var lp_s: float = 0.0
	var a_s: float = _a(300.0)
	var sub: float = 1.5
	var sub_k: float = _d(0.08)
	var lp_a: float = 0.0
	var lp_b: float = 0.0
	var a_hi: float = _a(2200.0 * j)
	var a_lo: float = _a(600.0)
	var crunch: float = 1.0
	var crunch_k: float = _d(0.05)
	var lp_g: float = 0.0
	var a_g: float = _a(1800.0)
	var grit_tail: float = 1.0
	var grit_k: float = _d(0.12)
	var p_grit: float = 0.25 * DENSITY
	for i: int in n:
		var noise: float = rng.randf_range(-1.0, 1.0)
		phase += TAU * 42.0 * j * (1.0 + 1.5 * g) / fs
		g *= g_k
		lp_s += a_s * (noise - lp_s)
		lp_a += a_hi * (noise - lp_a)
		lp_b += a_lo * (lp_a - lp_b)
		var grit: float = rng.randf_range(-1.0, 1.0) if rng.randf() < p_grit * grit_tail else 0.0
		lp_g += a_g * (grit - lp_g)
		out[i] = sin(phase) * body + lp_s * sub + (lp_a - lp_b) * crunch * 1.3 + (grit - lp_g) * grit_tail * 0.5
		body *= body_k
		sub *= sub_k
		crunch *= crunch_k
		grit_tail *= grit_k
	_add_ping(out, 0.0, 130.0 * j, 120.0 * j, 0.02, 0.05, 0.4, 0.002)
	return out


static func _synth_dizzy(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var fs: float = float(MIX_RATE)
	var out: PackedFloat32Array = _new(dur)
	var t: float = 0.02
	var k: int = 0
	var orbit_hz: float = rng.randf_range(1.1, 1.5)
	while t < dur - 0.1:
		var length: float = rng.randf_range(0.06, 0.09)
		var bird: int = k % 2
		var f_a: float = (2600.0 if bird == 0 else 3100.0) * rng.randf_range(0.95, 1.05)
		var f_b: float = f_a * (1.35 if (k / 2) % 2 == 0 else 0.78)
		var trill_hz: float = rng.randf_range(35.0, 45.0)
		var i0: int = int(t * fs)
		var cn: int = mini(int(length * fs), out.size() - i0)
		var orbit: float = 0.55 + 0.45 * sin(TAU * orbit_hz * t + (0.0 if bird == 0 else PI))
		var phase: float = 0.0
		for i: int in cn:
			var u: float = float(i) / float(cn)
			var f: float = lerpf(f_a, f_b, u) * (1.0 + 0.06 * sin(TAU * trill_hz * i / fs))
			phase += TAU * f / fs
			var e: float = sin(PI * u)
			out[i0 + i] += (sin(phase) + 0.15 * sin(2.0 * phase)) * e * e * orbit
		t += length + rng.randf_range(0.03, 0.08)
		k += 1
	for s: int in 4:
		var f: float = rng.randf_range(4500.0, 7000.0)
		_add_ping(out, rng.randf_range(0.05, dur * 0.8), f, f, 1.0, 0.04, 0.2, 0.001)
	return out
