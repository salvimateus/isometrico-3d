extends RefCounted

## Character detail level: low on mobile (via the shared res://scripts/quality.gd when present, the
## "mobile" feature, or `--quality=mobile`). Mesh segment and particle counts scale by these factors.

const QUALITY_PATH: String = "res://scripts/quality.gd"
const LOW_MESH_DETAIL: float = 0.55
const LOW_PARTICLES: float = 0.5

static var _resolved: bool = false
static var _low: bool = false


static func is_low() -> bool:
	if not _resolved:
		_resolved = true
		_low = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--quality=mobile")
		if not _low and ResourceLoader.exists(QUALITY_PATH):
			var q: Script = load(QUALITY_PATH)
			if q != null and q.has_method(&"is_mobile"):
				_low = bool(q.call(&"is_mobile"))
	return _low


static func mesh_detail() -> float:
	return LOW_MESH_DETAIL if is_low() else 1.0


static func particles(count: int) -> int:
	return maxi(2, int(round(count * (LOW_PARTICLES if is_low() else 1.0))))
