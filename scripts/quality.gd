extends RefCounted

## Quality tier shared by every module: &"mobile" on mobile platforms or with `-- --quality=mobile`, else &"high".

static var _cached: StringName = &""


static func is_mobile() -> bool:
	return tier() == &"mobile"


static func tier() -> StringName:
	if _cached == &"":
		_cached = &"high"
		if OS.has_feature("mobile"):
			_cached = &"mobile"
		for a: String in OS.get_cmdline_user_args():
			if a == "--quality=mobile":
				_cached = &"mobile"
			elif a == "--quality=high":
				_cached = &"high"
	return _cached
