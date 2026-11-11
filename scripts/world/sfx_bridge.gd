extends RefCounted

## Optional bridge to the CHARACTER audio module. Silent when `res://scripts/audio/sfx.gd` is missing or broken.

const SFX_PATH: String = "res://scripts/audio/sfx.gd"

static var _sfx: Script = null
static var _checked: bool = false


## Pre-synthesizes the given presets so their first play does not hitch.
static func warm(presets: Array[StringName]) -> void:
	_resolve()
	if _sfx == null:
		return
	for m: Dictionary in _sfx.get_script_method_list():
		if m["name"] == "warm":
			_sfx.call(&"warm", presets)
			return


static func play(tree: SceneTree, preset: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_resolve()
	if _sfx != null:
		_sfx.call(&"play", tree, preset, volume_db, pitch)


static func _resolve() -> void:
	if not _checked:
		_checked = true
		if ResourceLoader.exists(SFX_PATH):
			var s: Resource = load(SFX_PATH)
			if s is GDScript and (s as GDScript).can_instantiate():
				for m: Dictionary in (s as GDScript).get_script_method_list():
					if m["name"] == "play":
						_sfx = s
						break
