extends Node

## Dev: `--touch-demo=<scenario>` injects synthetic touches through Input.parse_input_event() so screenshots
## show each control state. Scenarios: rest, spawn, drag, run, interact, multi, pinch, shoulder, tap, joy (`--joy-demo`).
## Positions are authored in canvas units relative to the viewport and converted to window pixels on injection.

const START_FRAME: int = 80

var _controls: Node = null


func run(controls: Node, scenario: String) -> void:
	_controls = controls
	await _frames(START_FRAME)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var r: float = float(_controls.get(&"_stick").get(&"radius"))
	match scenario:
		"spawn":
			_touch(0, Vector2(vp.x * 0.27, vp.y * 0.5), true)
		"drag":
			var from := Vector2(vp.x * 0.14, vp.y * 0.74)
			_touch(0, from, true)
			await _slide(0, from, from + Vector2(r * 2.6, -r * 1.5), 24)
		"run":
			var from := Vector2(vp.x * 0.2, vp.y * 0.66)
			_touch(0, from, true)
			await _slide(0, from, from + Vector2(0.62, -0.72).normalized() * r * 0.96, 12)
		"multi":
			var from := Vector2(vp.x * 0.16, vp.y * 0.7)
			_touch(0, from, true)
			await _slide(0, from, from + Vector2(r * 0.62, -r * 0.2), 10)
			await _frames(20)
			var jump: Vector2 = _controls.get(&"_jump").get(&"center")
			_touch(1, jump + Vector2(8, 6), true)
		"pinch":
			var a := Vector2(vp.x * 0.64, vp.y * 0.46)
			var b := Vector2(vp.x * 0.74, vp.y * 0.56)
			_touch(0, a, true)
			_touch(1, b, true)
			for i: int in 24:
				await get_tree().process_frame
				var t: float = float(i + 1) / 24.0
				_drag(0, a.lerp(a + Vector2(-vp.x * 0.06, -vp.y * 0.08), t), Vector2(-vp.x * 0.06, -vp.y * 0.08) / 24.0)
				_drag(1, b.lerp(b + Vector2(vp.x * 0.06, vp.y * 0.08), t), Vector2(vp.x * 0.06, vp.y * 0.08) / 24.0)
		"shoulder":
			var cam: Vector2 = _controls.get(&"_camera_btn").get(&"center")
			_touch(0, cam, true)
			await _frames(3)
			_touch(0, cam, false)
			await _frames(30)
			var from := Vector2(vp.x * 0.7, vp.y * 0.5)
			_touch(1, from, true)
			await _slide(1, from, from + Vector2(-vp.x * 0.12, 0.0), 20)
		"joy":
			_controls.call(&"on_joy_connection", 0, true, "Gamepad (demo)")
			await _frames(10)
			for pressed: bool in [true, false]:
				var jb := InputEventJoypadButton.new()
				jb.device = 0
				jb.button_index = JOY_BUTTON_Y
				jb.pressed = pressed
				Input.parse_input_event(jb)
				await _frames(2)
			var jm := InputEventJoypadMotion.new()
			jm.device = 0
			jm.axis = JOY_AXIS_RIGHT_X
			jm.axis_value = 0.0
			Input.parse_input_event(jm)
			await _frames(60)
			var p := Vector2(vp.x * 0.7, vp.y * 0.45)
			_touch(0, p, true)
			await _frames(3)
			_touch(0, p, false)
		"tap":
			var p := Vector2(vp.x * 0.7, vp.y * 0.45)
			_touch(0, p, true)
			await _frames(3)
			_touch(0, p, false)
		_:
			pass


func _slide(index: int, from: Vector2, to: Vector2, steps: int) -> void:
	var last: Vector2 = from
	for i: int in steps:
		await get_tree().process_frame
		var p: Vector2 = from.lerp(to, float(i + 1) / float(steps))
		_drag(index, p, p - last)
		last = p


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(canvas_pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, canvas_pos: Vector2, canvas_rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _to_window(canvas_pos)
	var k: Vector2 = get_viewport().get_final_transform().get_scale()
	ev.relative = canvas_rel * k
	ev.screen_relative = canvas_rel * k
	Input.parse_input_event(ev)
