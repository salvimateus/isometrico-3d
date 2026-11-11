extends StaticBody3D

## Obstacle collider for one tree, big bush or big rock. `bump()` shakes the MultiMesh instance and drops leaves.

const Tuning := preload("res://scripts/tuning.gd")
const Sfx := preload("res://scripts/world/sfx_bridge.gd")

var multimesh: MultiMesh = null
var index: int = -1
var base_custom := Color(1, 0, -100, 0)
var top_height: float = 2.0
var leafy: bool = true

var _last_bump: float = -100.0


func bump(impulse: Vector3) -> void:
	var fx: Node = get_tree().get_first_node_in_group(&"world_fx")
	if fx == null:
		return
	var now: float = fx.get(&"time")
	if now - _last_bump < Tuning.BUMP_COOLDOWN:
		return
	_last_bump = now
	var strength: float = clampf(impulse.length() / Tuning.BUMP_REFERENCE_IMPULSE, 0.35, 1.5)
	var dir := Vector2(impulse.x, impulse.z)
	if dir.length_squared() < 1e-6:
		dir = Vector2(1, 0)
	if multimesh != null and index >= 0:
		var c: Color = base_custom
		c.b = now
		c.a = fposmod(dir.angle(), TAU)
		multimesh.set_instance_custom_data(index, c)
	if leafy:
		fx.call(&"leaves", global_position + Vector3(0, top_height, 0), strength)
		Sfx.play(get_tree(), &"tree_rustle", lerpf(-8.0, 0.0, clampf(strength, 0.0, 1.0)), randf_range(0.9, 1.1))
	else:
		fx.call(&"dust", global_position, 0.3, strength * 0.6)
