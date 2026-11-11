extends Node

## Dev check (`-- --flood-probe`): prints an ASCII depth map of the liquid field at a few frames after the trigger.

const FRAMES: Array[int] = [300, 420, 700, 1300]
var _frame: int = 0


func _process(_delta: float) -> void:
	_frame += 1
	if not FRAMES.has(_frame):
		return
	var field: Node = get_tree().get_first_node_in_group(&"liquid_field")
	if field == null:
		return
	var out: String = "[flood-probe] frame %d (x -12..12 left->right, z -12..16 top->bottom; . <0.03 : <0.1 o <0.25 O >=0.25)\n" % _frame
	for zi: int in range(-12, 17):
		var row: String = "%4d " % zi
		for xi: int in range(-12, 13):
			var d: float = float(field.call(&"depth_at", Vector3(xi + 0.5, 0.0, zi + 0.5)))
			row += "." if d < 0.03 else (":" if d < 0.1 else ("o" if d < 0.25 else "O"))
		out += row + "\n"
	print(out)
