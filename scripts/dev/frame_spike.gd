extends Node

## Dev check (`-- --frame-spikes`): prints frames whose real duration exceeds 25 ms, plus the worst one.

var _frame: int = 0
var _last_us: int = 0
var _worst_ms: float = 0.0
var _worst_frame: int = 0


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_frame += 1
	if _last_us > 0 and _frame > 30:
		var ms: float = (now - _last_us) / 1000.0
		if ms > 25.0:
			print("[frame-spike] frame %d: %.1f ms" % [_frame, ms])
		if ms > _worst_ms:
			_worst_ms = ms
			_worst_frame = _frame
	_last_us = now


func _exit_tree() -> void:
	print("[frame-spike] worst frame %d: %.1f ms" % [_worst_frame, _worst_ms])
