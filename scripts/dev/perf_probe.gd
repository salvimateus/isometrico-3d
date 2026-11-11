extends Node

## Dev check (`-- --perf-probe`): averages GPU/CPU render time, draw calls and primitives over frames 120-299.

var _frame: int = 0
var _gpu: float = 0.0
var _cpu: float = 0.0
var _draws: float = 0.0
var _prims: float = 0.0
var _n: int = 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--perf-hide="):
			_hide.call_deferred(a.trim_prefix("--perf-hide=").split(","))
		if a == "--perf-noshadow":
			_noshadow.call_deferred()
		if a == "--perf-building-noshadow":
			_building_noshadow.call_deferred()


func _hide(names: PackedStringArray) -> void:
	var main: Node = get_parent()
	for n: String in names:
		var node: Node = main.find_child(n, true, false)
		if node is Node3D:
			(node as Node3D).visible = false
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = false
		else:
			print("[perf] not found: ", n)


func _noshadow() -> void:
	for l: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = false


func _process(_d: float) -> void:
	_frame += 1
	if _frame < 120 or _frame >= 300:
		if _frame == 300 and _n > 0:
			print("[perf] gpu=%.2fms cpu=%.2fms draws=%d prims=%d" % [_gpu / _n, _cpu / _n, int(_draws / _n), int(_prims / _n)])
		return
	var rid: RID = get_viewport().get_viewport_rid()
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	_draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_n += 1


func _building_noshadow() -> void:
	var b: Node = get_parent().find_child("Buildings", true, false)
	for g: Node in b.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
