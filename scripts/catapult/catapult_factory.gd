extends RefCounted

## Entry point for the world: turns a catapult model (ArmPivot, ArmPivot/Seat, Winch, CountdownAnchor)
## into a rideable catapult.

const Controller := preload("res://scripts/catapult/catapult_controller.gd")


## Creates the ride controller as a child of `catapult` and returns it. Controller API:
## `try_mount() -> bool`, `is_ready() -> bool`, signal `fired(target: Vector3)`,
## vars `launch_distance_min` / `launch_distance_max`.
static func attach(catapult: Node3D) -> Node:
	var controller: Node3D = Controller.new()
	controller.call(&"setup", catapult)
	catapult.add_child(controller)
	return controller
