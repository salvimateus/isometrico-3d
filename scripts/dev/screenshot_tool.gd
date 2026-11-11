extends Node

## Dev autoload. With `-- --shot=<abs .png path> [--frames=N]` saves the viewport after N frames and quits.

var _shot_path: String = ""
var _frames_left: int = 120


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=").trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
		elif arg.begins_with("--frames="):
			_frames_left = maxi(1, arg.trim_prefix("--frames=").to_int())
	set_process(not _shot_path.is_empty())


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left > 0:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var dir: String = _shot_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var err: Error = image.save_png(_shot_path)
	for retry: int in 5:
		if err == OK:
			break
		await get_tree().create_timer(0.3).timeout
		err = image.save_png(_shot_path)
	if err == OK:
		print("[ScreenshotTool] saved ", _shot_path)
	else:
		push_error("[ScreenshotTool] failed to save %s (error %d)" % [_shot_path, err])
	get_tree().quit()
