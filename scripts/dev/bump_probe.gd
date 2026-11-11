extends Node

## Dev check (`-- --bump-probe`): bumps every layer-2 body near the camera focus a few frames before the shot.

var _frames: int = 0


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 100:
		return
	var rig: Node3D = get_tree().get_first_node_in_group(&"camera_rig")
	var center: Vector3 = rig.global_position if rig != null else Vector3.ZERO
	var count: int = 0
	for node: Node in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.has_method(&"bump") and body.global_position.distance_to(center) < 7.0:
			body.call(&"bump", Vector3(6, 0, 3))
			count += 1
	print("[bump-probe] bumped ", count, " bodies")
