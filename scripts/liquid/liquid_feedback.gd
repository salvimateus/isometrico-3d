extends RefCounted

## Optional juice hooks used by the liquid system: SFX (CHARACTER's sfx.gd), camera trauma
## (group &"camera_rig") and rumble (CHARACTER's haptics.gd, joypads as fallback). Every hook is silent when its provider is missing.

const SFX_PATH: String = "res://scripts/audio/sfx.gd"
const HAPTICS_PATH: String = "res://scripts/input/haptics.gd"

static var _sfx: Script
static var _checked: bool = false
static var _methods: Dictionary = {}
static var _haptics: Script
static var _haptics_checked: bool = false


static func play(tree: SceneTree, preset: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var sfx: Script = _get_sfx()
	if sfx == null or not _has_preset(sfx, preset):
		return
	sfx.call(&"play", tree, preset, volume_db, pitch)


## Returns the loop handle (has set_volume_db / stop) or null.
static func play_loop(tree: SceneTree, preset: StringName, volume_db: float, pos: Vector3) -> Node:
	var sfx: Script = _get_sfx()
	if sfx == null or not _methods.has(&"play_loop"):
		return null
	if _methods.has(&"has_preset") and not bool(sfx.call(&"has_preset", preset)):
		return null
	var handle: Variant = sfx.call(&"play_loop", tree, preset, volume_db, pos)
	return handle as Node


static func set_loop_volume(handle: Node, db: float) -> void:
	if handle != null and is_instance_valid(handle) and handle.has_method(&"set_volume_db"):
		handle.call(&"set_volume_db", db)


## The loop handle is a plain Node owning the player; move its AudioStreamPlayer3D child (2D loops ignore it).
static func set_loop_position(handle: Node, pos: Vector3) -> void:
	if handle == null or not is_instance_valid(handle) or not handle.is_inside_tree():
		return
	for c: Node in handle.get_children():
		var p3 := c as AudioStreamPlayer3D
		if p3 != null:
			p3.global_position = pos
			return


static func stop_loop(handle: Node, fade: float) -> void:
	if handle != null and is_instance_valid(handle) and handle.has_method(&"stop"):
		handle.call(&"stop", fade)


## Pre-synthesizes the given presets (call while loading; the first play otherwise stalls a frame).
static func warm(presets: Array[StringName]) -> void:
	var sfx: Script = _get_sfx()
	if sfx == null or not _methods.has(&"warm"):
		return
	var known: Array[StringName] = []
	for p: StringName in presets:
		if _has_preset(sfx, p):
			known.append(p)
	sfx.call(&"warm", known)


static func trauma(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	var rig: Node = tree.get_first_node_in_group(&"camera_rig")
	if rig != null and rig.has_method(&"add_trauma"):
		rig.call(&"add_trauma", amount)


## weak, strong, duration.
static func rumble(cfg: Vector3) -> void:
	if not _haptics_checked:
		_haptics_checked = true
		if ResourceLoader.exists(HAPTICS_PATH):
			_haptics = load(HAPTICS_PATH) as Script
	if _haptics != null:
		_haptics.call(&"rumble", cfg.x, cfg.y, cfg.z)
		return
	for id: int in Input.get_connected_joypads():
		Input.start_joy_vibration(id, cfg.x, cfg.y, cfg.z)


static func _get_sfx() -> Script:
	if not _checked:
		_checked = true
		if ResourceLoader.exists(SFX_PATH):
			_sfx = load(SFX_PATH) as Script
			if _sfx != null:
				for m: Dictionary in _sfx.get_script_method_list():
					_methods[StringName(m["name"])] = true
	return _sfx


static func _has_preset(sfx: Script, preset: StringName) -> bool:
	if _methods.has(&"has_preset"):
		return bool(sfx.call(&"has_preset", preset))
	return true
