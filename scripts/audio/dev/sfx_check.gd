extends Node

## Dev check: times synthesis, prints clip stats, exports samples, plays a burst and quits mid-sound.

const Sfx := preload("res://scripts/audio/sfx.gd")
const EXPORT_DIR: String = "C:\\dev\\isometrico-3d\\_shots\\character\\sfx"

var _frame: int = 0
var _loop2d: Node
var _loop3d: Node
var _loop_keep: Node
var _checked_free: bool = false
var _rope: Node


func _ready() -> void:
	var total_ms: float = 0.0
	for p: StringName in Sfx.PRESETS:
		var t0: int = Time.get_ticks_usec()
		Sfx.warm([p])
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		print("%-15s %6.1f ms  %s" % [p, ms, _stats(p)])
	print("TOTAL synth: %.1f ms" % total_ms)
	var t1: int = Time.get_ticks_usec()
	var written: int = Sfx.export_samples(EXPORT_DIR)
	print("exported %d files in %.1f ms" % [written, (Time.get_ticks_usec() - t1) / 1000.0])
	Sfx.play(get_tree(), &"step_grass", -12.0, 0.95)
	Sfx.play(get_tree(), &"ui_select")
	Sfx.play(get_tree(), &"does_not_exist")
	Sfx.play(get_tree(), &"does_not_exist")
	print("misuse -> ", Sfx.play_loop(get_tree(), &"ui_tick"), " / unknown loop -> ", Sfx.play_loop(get_tree(), &"nope_loop"))
	Sfx.play(get_tree(), &"water_flow")
	_loop2d = Sfx.play_loop(get_tree(), &"water_flow", -6.0)
	_loop3d = Sfx.play_loop(get_tree(), &"waterfall", -3.0, Vector3(10.0, 0.0, 5.0))
	_loop_keep = Sfx.play_loop(get_tree(), &"waterfall", -12.0)
	_loop_keep.stop(0.0)
	_loop_keep.stop(0.5)
	_loop_keep = Sfx.play_loop(get_tree(), &"water_flow", -10.0)
	_rope = Sfx.play_loop(get_tree(), &"rope_creak", -6.0, Vector3(0.0, 2.0, 0.0))
	Sfx.play(get_tree(), &"viking_scream", -6.0)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % 6 == 0:
		var names: Array = Sfx.PRESETS.keys()
		Sfx.play(get_tree(), names[(_frame / 6) % names.size()], -6.0)
	if _frame == 3:
		Sfx.play(get_tree(), &"building_thud")
	if _frame == 10:
		print("loops in tree: ", _loop2d.is_inside_tree(), " ", _loop3d.is_inside_tree(), " 3d player: ", _loop3d.get_child(0).get_class(), " playing ", _loop3d.get_child(0).playing)
		_loop2d.set_volume_db(-24.0)
	if _frame == 25:
		_loop2d.stop(0.3)
		_loop2d.stop(0.6)
		_loop3d.set_volume_db(-20.0)
		_rope.stop(0.4)
	if _frame > 25 and not _checked_free and Time.get_ticks_msec() > _start_ms() + 900:
		_checked_free = true
		print("rope loop freed after fade: ", not is_instance_valid(_rope), " 2d loop freed after fade: ", not is_instance_valid(_loop2d), " keep playing: ", _loop_keep.get_child(0).playing)
	if Time.get_ticks_msec() > 1000 + _start_ms():
		Sfx.play(get_tree(), &"collect_whoosh")
		get_tree().quit()
		set_process(false)


var _t0: int = -1
func _start_ms() -> int:
	if _t0 < 0:
		_t0 = Time.get_ticks_msec()
	return _t0


func _stats(p: StringName) -> String:
	var parts: PackedStringArray = []
	for wav: AudioStreamWAV in Sfx._bank(p):
		var d: PackedByteArray = wav.data
		var n: int = d.size() / 2
		var peak: float = 0.0
		var sum: float = 0.0
		for i: int in n:
			var v: float = d.decode_s16(i * 2) / 32767.0
			peak = maxf(peak, absf(v))
			sum += v * v
		parts.append("%.2f/%.3f" % [peak, sqrt(sum / maxf(1.0, n))])
	var extra: String = ""
	var w0: AudioStreamWAV = Sfx._bank(p)[0]
	if w0.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var d0: PackedByteArray = w0.data
		var n0: int = d0.size() / 2
		var jump: float = absf(d0.decode_s16(0) - d0.decode_s16((n0 - 1) * 2)) / 32767.0
		var larger: int = 0
		for i: int in range(1, n0):
			if absf(d0.decode_s16(i * 2) - d0.decode_s16((i - 1) * 2)) / 32767.0 > jump:
				larger += 1
		extra = " loop[%d..%d] seam step %.4f, %.1f%% of inner steps are larger" % [w0.loop_begin, w0.loop_end, jump, 100.0 * larger / (n0 - 1)]
	return "dur %.3fs peak/rms %s%s" % [wav_len(w0), " ".join(parts), extra]


func wav_len(w: AudioStreamWAV) -> float:
	return w.data.size() / 2.0 / w.mix_rate
