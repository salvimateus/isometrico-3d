extends RefCounted

## Landing-point validation (island ground under it, no obstacle around it) and the launch velocity
## that hits it with a high apex under a given gravity.

const T := preload("res://scripts/catapult/catapult_tuning.gd")


## Ground hit (layer 1) under `p`, or Vector3.INF when there is none (ocean, void).
static func ground_under(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var from := Vector3(p.x, T.LANDING_RAY_HEIGHT, p.z)
	var to := Vector3(p.x, -T.LANDING_RAY_DEPTH, p.z)
	var q := PhysicsRayQueryParameters3D.create(from, to, T.GROUND_LAYER)
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var pos: Vector3 = hit["position"]
	if pos.y < T.LANDING_MIN_GROUND_Y:
		return Vector3.INF
	return pos


static func is_clear(space: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = T.LANDING_CLEAR_RADIUS
	shape.height = 2.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 1.3)
	q.collision_mask = T.OBSTACLE_LAYER
	q.collide_with_areas = false
	return space.intersect_shape(q, 1).is_empty()


## Valid ground point (snapped to the hit) closest to `desired`, at least LANDING_MIN_DISTANCE from
## `origin`. Returns Vector3.INF when nothing within the search radius qualifies.
static func find_landing(space: PhysicsDirectSpaceState3D, desired: Vector3, origin: Vector3) -> Vector3:
	var best := _try(space, desired, origin)
	if best.is_finite():
		return best
	var r: float = T.LANDING_SEARCH_STEP
	while r <= T.LANDING_SEARCH_RADIUS:
		var count: int = maxi(8, int(TAU * r / T.LANDING_SEARCH_STEP))
		var best_d: float = INF
		for i: int in count:
			var a: float = TAU * float(i) / float(count)
			var c: Vector3 = _try(space, desired + Vector3(cos(a), 0.0, sin(a)) * r, origin)
			if c.is_finite():
				var d: float = Vector2(c.x - desired.x, c.z - desired.z).length()
				if d < best_d:
					best_d = d
					best = c
		if best.is_finite():
			return best
		r += T.LANDING_SEARCH_STEP
	return Vector3.INF


static func _try(space: PhysicsDirectSpaceState3D, p: Vector3, origin: Vector3) -> Vector3:
	if Vector2(p.x - origin.x, p.z - origin.z).length() < T.LANDING_MIN_DISTANCE:
		return Vector3.INF
	var g: Vector3 = ground_under(space, p)
	if not g.is_finite() or not is_clear(space, g):
		return Vector3.INF
	# Keep a margin from the island edge so the body does not slide off into the sea.
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		if not ground_under(space, g + Vector3(cos(a), 0.0, sin(a)) * T.LANDING_EDGE_MARGIN).is_finite():
			return Vector3.INF
	return g


## Total flight time from `from_y` up to `apex` and down to `to_y` under gravity `g`.
static func flight_time(from_y: float, to_y: float, apex: float, g: float) -> float:
	return sqrt(2.0 * maxf(apex - from_y, 0.0) / g) + sqrt(2.0 * maxf(apex - to_y, 0.0) / g)


## Apex whose flight time is closest to FLIGHT_TIME_TARGET within [APEX_MIN, APEX_MAX]; when that range
## cannot keep the time inside [FLIGHT_TIME_MIN, FLIGHT_TIME_MAX] (unusual gravity or launch height),
## the time window wins over the apex range. Horizontal distance never changes the time, only the speed.
static func pick_apex(from_y: float, to_y: float, g: float) -> float:
	var floor_y: float = maxf(from_y, to_y) + 0.5
	var apex: float = clampf(_apex_for_time(from_y, to_y, g, T.FLIGHT_TIME_TARGET), maxf(T.APEX_MIN, floor_y), maxf(T.APEX_MAX, floor_y))
	var t: float = flight_time(from_y, to_y, apex, g)
	if t < T.FLIGHT_TIME_MIN or t > T.FLIGHT_TIME_MAX:
		apex = _apex_for_time(from_y, to_y, g, clampf(t, T.FLIGHT_TIME_MIN, T.FLIGHT_TIME_MAX))
	return apex


static func _apex_for_time(from_y: float, to_y: float, g: float, time: float) -> float:
	var lo: float = maxf(from_y, to_y) + 0.05
	var hi: float = T.APEX_SEARCH_MAX
	for i: int in 40:
		var mid: float = (lo + hi) * 0.5
		if flight_time(from_y, to_y, mid, g) < time:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Initial velocity from `from` that peaks at world height `apex` and lands on `to`.
static func launch_velocity(from: Vector3, to: Vector3, apex: float, g: float) -> Vector3:
	var vy: float = sqrt(2.0 * g * maxf(apex - from.y, 0.01))
	var t: float = flight_time(from.y, to.y, apex, g)
	var h := Vector3(to.x - from.x, 0.0, to.z - from.z) / maxf(t, 0.01)
	return Vector3(h.x, vy, h.z)
