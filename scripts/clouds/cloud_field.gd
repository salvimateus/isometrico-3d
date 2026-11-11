extends Node3D

## Drifting raymarched cumulus over `area` (world XZ). Three populations: a "ring" of low diorama clouds
## on fixed lanes around the island (always a few in the iso frame), "sky" clouds filling the horizon
## for the shoulder camera, and one "crosser" that periodically drifts through the iso line of sight.
## Clouds recycle at their rect edge with a density fade. A coverage map is published for ground
## shadows. Group &"cloud_field". Keep at the identity transform.
## API: set_night(amount), set_light_direction(dir), spawn_crosser(lead, instant), set_suppressed(on), set_enabled(on),
## get_shadow_texture(), get_shadow_rect().

const CT := preload("res://scripts/clouds/cloud_tuning.gd")
const CloudShape := preload("res://scripts/clouds/cloud_shape.gd")
const CloudNoise := preload("res://scripts/clouds/cloud_noise.gd")
const ShadowMap := preload("res://scripts/clouds/cloud_shadow_map.gd")
const SHADER := preload("res://shaders/clouds/cloud_volume.gdshader")
const SHADER_MOBILE := preload("res://shaders/clouds/cloud_volume_mobile.gdshader")

const SHADOW_MAP_PARAM: StringName = &"cloud_shadow_map"
const SHADOW_RECT_PARAM: StringName = &"cloud_shadow_rect"

enum Kind { CROSSER, RING, SKY }

var area := Rect2(-110.0, -110.0, 220.0, 220.0)

var _clouds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _wind := CT.WIND_DIRECTION.normalized()
var _time: float = 0.0
var _night: float = 0.0
var _light_dir := Vector3(-0.85, 1.05, 0.38).normalized()
var _light_target := _light_dir
var _manual_light: bool = false
var _lights: Array[DirectionalLight3D] = []
var _crosser_wait: float = 6.0
var _shadow: ShadowMap
var _publish_shadow: bool = false
var _look_dirty: bool = true
var _ring_rect := Rect2()
var _suppressed: bool = false
var _mobile: bool = false
var _enabled: bool = true
var _enabled_amount: float = 1.0
var _empty_shadow: ImageTexture
## Publish the shadow globals even when project.godot does not declare them (set before adding to the tree).
var publish_shadow_global: bool = false


## `mobile` selects the cheaper profile (fewer steps, envelope-only light, fewer clouds, 128 px shadows).
func configure(cloud_area: Rect2, seed_value: int = 1337, mobile: bool = false) -> void:
	_mobile = mobile
	area = cloud_area
	_rng.seed = seed_value


func _ready() -> void:
	add_to_group(&"cloud_field")
	_shadow = ShadowMap.new()
	var map_size: int = CT.MOBILE_SHADOW_MAP_SIZE if _mobile else CT.SHADOW_MAP_SIZE
	_shadow.size = Vector2i(map_size, map_size)
	_shadow.refresh_interval = CT.MOBILE_SHADOW_REFRESH if _mobile else CT.SHADOW_REFRESH
	_shadow.name = "CloudShadowMap"
	_shadow.world_rect = area
	add_child(_shadow)
	_publish_shadow = publish_shadow_global or ProjectSettings.has_setting("shader_globals/" + SHADOW_MAP_PARAM)
	var black := Image.create(1, 1, false, Image.FORMAT_L8)
	_empty_shadow = ImageTexture.create_from_image(black)
	_publish_shadow_texture(true)

	var noise: ImageTexture3D = CloudNoise.get_texture()
	_ring_rect = _make_ring_rect()
	_clouds.append(_make_cloud(noise, Kind.CROSSER))
	_clouds[0]["parked"] = true
	var lanes: PackedFloat32Array = _ring_lanes()
	for i: int in lanes.size():
		var cloud: Dictionary = _make_cloud(noise, Kind.RING)
		cloud["lane_index"] = i
		cloud["lane"] = lanes[i] + _rng.randf_range(-CT.RING_LANE_JITTER, CT.RING_LANE_JITTER)
		var along: float = (fposmod(i * 0.618 + 0.31, 1.0) - 0.5) * _ring_rect.size.x
		cloud["position"] = _lane_point(cloud, along)
		cloud["age"] = CT.SPAWN_FADE_TIME
		_clouds.append(cloud)
	for i: int in (CT.MOBILE_SKY_COUNT if _mobile else CT.SKY_COUNT):
		var cloud: Dictionary = _make_cloud(noise, Kind.SKY)
		cloud["lane"] = _pick_sky_lane(float(cloud["radius"]))
		cloud["position"] = _lane_point(cloud, _rng.randf_range(-0.5, 0.5) * minf(area.size.x, area.size.y))
		cloud["age"] = CT.SPAWN_FADE_TIME
		_clouds.append(cloud)

	for node: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_lights.append(node as DirectionalLight3D)
	get_tree().node_added.connect(_on_node_added)
	_update_clouds(0.0)


## 0 = day, 1 = night. Cheap enough to call every frame.
func set_night(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if is_equal_approx(amount, _night):
		return
	_night = amount
	_look_dirty = true


## Direction toward the key light (scene to light). Disables the automatic DirectionalLight3D tracking.
func set_light_direction(dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	_manual_light = true
	_light_target = dir.normalized()


## Sends the crosser cloud through the active camera's line of sight to its focus, starting `lead`
## units upwind. `instant` skips the fade in (used for validation shots).
func spawn_crosser(lead: float = CT.CROSSER_LEAD_DISTANCE, instant: bool = false) -> void:
	if _mobile and not CT.MOBILE_CROSSER_ENABLED:
		return
	var cloud: Dictionary = _clouds[0]
	var cam_height: float = CT.ISO_REFERENCE_HEIGHT
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and -cam.global_basis.z.y < -0.4:
		cam_height = cam.global_position.y
	var altitude: float = clampf(cam_height * CT.CROSSER_HEIGHT_FRACTION, CT.CROSSER_ALTITUDE_MIN, CT.CROSSER_ALTITUDE_MAX)
	var center_y: float = altitude + float(cloud["lift"])
	var target: Vector2 = _sightline_point(center_y)
	target += Vector2(-_wind.y, _wind.x) * _rng.randf_range(-CT.CROSSER_LATERAL_JITTER, CT.CROSSER_LATERAL_JITTER)
	var start: Vector2 = target - _wind * lead
	cloud["position"] = Vector3(start.x, center_y, start.y)
	cloud["parked"] = false
	cloud["age"] = CT.SPAWN_FADE_TIME if instant else 0.0
	cloud["travel"] = 0.0
	cloud["travel_limit"] = lead + CT.CROSSER_LEAD_DISTANCE
	_crosser_wait = CT.CROSSER_INTERVAL + _rng.randf_range(-CT.CROSSER_INTERVAL_JITTER, CT.CROSSER_INTERVAL_JITTER)


## Off fades every cloud out, then stops processing, rendering and the shadow map (global set to an
## empty texture). On resumes and fades them back in.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if on and _shadow != null:
		set_process(true)
		_shadow.render_target_update_mode = SubViewport.UPDATE_ONCE
		_publish_shadow_texture(true)


## While on, the crosser and ring clouds over the island fade out and no new crossing starts;
## ocean clouds are untouched. Turning it off fades them back in.
func set_suppressed(on: bool) -> void:
	_suppressed = on


func get_shadow_texture() -> Texture2D:
	return _shadow.get_texture()


## (min x, min z, width, depth) of the area the shadow texture covers.
func get_shadow_rect() -> Vector4:
	return _shadow.get_rect_vector()


func _process(delta: float) -> void:
	_enabled_amount = move_toward(_enabled_amount, 1.0 if _enabled else 0.0, delta / CT.ENABLE_FADE_TIME)
	if not _enabled and _enabled_amount <= 0.0:
		for cloud: Dictionary in _clouds:
			(cloud["mesh"] as MeshInstance3D).visible = false
		_shadow.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_publish_shadow_texture(false)
		set_process(false)
		return
	_time += delta
	_track_light(delta)
	_update_crosser(delta)
	_update_clouds(delta)


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		_lights.append(node as DirectionalLight3D)


func _track_light(delta: float) -> void:
	if not _manual_light:
		var best: DirectionalLight3D = null
		var best_energy: float = 0.0
		for i: int in range(_lights.size() - 1, -1, -1):
			var light: DirectionalLight3D = _lights[i]
			if not is_instance_valid(light):
				_lights.remove_at(i)
				continue
			if light.is_visible_in_tree() and light.light_energy > best_energy:
				best_energy = light.light_energy
				best = light
		if best != null:
			_light_target = best.global_basis.z.normalized()
	var target := _light_target
	if target.y < 0.15:
		target = Vector3(target.x, 0.15, target.z).normalized()
	var k: float = 1.0 - exp(-CT.LIGHT_DIR_SMOOTHING * delta) if delta > 0.0 else 1.0
	var next: Vector3 = _light_dir.slerp(target, k).normalized()
	if not next.is_equal_approx(_light_dir):
		_light_dir = next
		_look_dirty = true


func _update_crosser(delta: float) -> void:
	var cloud: Dictionary = _clouds[0]
	if not bool(cloud["parked"]) or _suppressed or (_mobile and not CT.MOBILE_CROSSER_ENABLED):
		return
	_crosser_wait -= delta
	if _crosser_wait <= 0.0:
		spawn_crosser()


func _update_clouds(delta: float) -> void:
	var look: Dictionary = _look_params() if _look_dirty else {}
	var shadow_items: Array[Dictionary] = []
	for cloud: Dictionary in _clouds:
		var mesh: MeshInstance3D = cloud["mesh"]
		var mat: ShaderMaterial = cloud["material"]
		if bool(cloud["parked"]):
			mesh.visible = false
			continue
		var step: Vector2 = _wind * float(cloud["speed"]) * delta
		var pos: Vector3 = cloud["position"]
		pos += Vector3(step.x, 0.0, step.y)
		cloud["position"] = pos
		cloud["age"] = float(cloud["age"]) + delta
		cloud["travel"] = float(cloud["travel"]) + step.length()

		var kind: int = cloud["kind"]
		var rect: Rect2 = _ring_rect if kind == Kind.RING else area
		var inside: float = _inside_distance(rect, Vector2(pos.x, pos.z))
		if inside < 0.0:
			if kind == Kind.CROSSER:
				cloud["parked"] = true
				mesh.visible = false
				continue
			_respawn_upwind(cloud)
			pos = cloud["position"]
			inside = 0.0
		var edge_fade: float = CT.RING_EDGE_FADE_DISTANCE if kind == Kind.RING else CT.EDGE_FADE_DISTANCE
		var fade: float = smoothstep(0.0, edge_fade, inside) * smoothstep(0.0, CT.SPAWN_FADE_TIME, float(cloud["age"]))
		if kind == Kind.CROSSER:
			var limit: float = cloud["travel_limit"]
			fade *= 1.0 - smoothstep(limit - CT.SPAWN_FADE_TIME * float(cloud["speed"]), limit, float(cloud["travel"]))
			if float(cloud["travel"]) >= limit:
				cloud["parked"] = true
				mesh.visible = false
				continue

		var hide: bool = _suppressed and (kind == Kind.CROSSER or (kind == Kind.RING and _over_island(pos)))
		var presence: float = move_toward(float(cloud["presence"]), 0.0 if hide else 1.0, delta / CT.SUPPRESS_FADE_TIME)
		cloud["presence"] = presence
		fade *= smoothstep(0.0, 1.0, presence) * smoothstep(0.0, 1.0, _enabled_amount)

		mesh.visible = fade > 0.002
		mesh.global_position = pos
		var blobs: PackedVector4Array = _breathe(cloud)
		mat.set_shader_parameter(&"fade", fade)
		mat.set_shader_parameter(&"blobs", blobs)
		var drift: Vector3 = cloud["noise_seed"]
		mat.set_shader_parameter(&"noise_offset", drift + Vector3(0.6, 0.35, -0.45) * _time * CT.EVOLVE_SPEED)
		if not look.is_empty():
			for key: StringName in look:
				mat.set_shader_parameter(key, look[key])
		shadow_items.append({"position": pos, "blobs": blobs, "fade": fade})
	_look_dirty = false
	_shadow.update_from(shadow_items, _light_dir, delta)


func _look_params() -> Dictionary:
	var n: float = _night
	return {
		&"light_dir": _light_dir,
		&"sun_color": CT.SUN_COLOR.lerp(CT.NIGHT_SUN_COLOR, n),
		&"sun_intensity": lerpf(CT.SUN_INTENSITY, CT.NIGHT_SUN_INTENSITY, n),
		&"top_color": CT.TOP_COLOR.lerp(CT.NIGHT_TOP_COLOR, n),
		&"base_color": CT.BASE_COLOR.lerp(CT.NIGHT_BASE_COLOR, n),
		&"rim_color": CT.RIM_COLOR.lerp(CT.NIGHT_RIM_COLOR, n),
		&"rim_strength": lerpf(CT.RIM_STRENGTH, CT.NIGHT_RIM_STRENGTH, n),
		&"lobe_shadow_tint": CT.LOBE_SHADOW_TINT.lerp(CT.NIGHT_LOBE_SHADOW_TINT, n),
	}


func _make_cloud(noise: ImageTexture3D, kind: Kind) -> Dictionary:
	var width: float = _rng.randf_range(CT.SKY_SIZE_MIN, CT.SKY_SIZE_MAX)
	var height_ratio: float = _rng.randf_range(CT.SKY_HEIGHT_RATIO_MIN, CT.SKY_HEIGHT_RATIO_MAX)
	if kind == Kind.RING:
		width = _rng.randf_range(CT.RING_SIZE_MIN, CT.RING_SIZE_MAX)
		height_ratio = _rng.randf_range(CT.RING_HEIGHT_RATIO_MIN, CT.RING_HEIGHT_RATIO_MAX)
	elif kind == Kind.CROSSER:
		width = CT.CROSSER_SIZE
		height_ratio = CT.RING_HEIGHT_RATIO_MAX
	var shape: Dictionary = CloudShape.generate(_rng, width, height_ratio)
	var half: Vector3 = shape["half_extents"]
	var box := BoxMesh.new()
	box.size = half * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_MOBILE if _mobile else SHADER
	mat.set_shader_parameter(&"noise_tex", noise)
	mat.set_shader_parameter(&"half_extents", half)
	mat.set_shader_parameter(&"base_y", shape["base_y"])
	mat.set_shader_parameter(&"top_y", shape["top_y"])
	mat.set_shader_parameter(&"blob_count", (shape["blobs"] as PackedVector4Array).size())
	mat.set_shader_parameter(&"max_steps", CT.MOBILE_MAX_STEPS if _mobile else CT.MAX_STEPS)
	mat.set_shader_parameter(&"step_length", CT.MOBILE_STEP_LENGTH if _mobile else CT.STEP_LENGTH)
	mat.set_shader_parameter(&"light_steps", CT.MOBILE_LIGHT_STEPS if _mobile else CT.LIGHT_STEPS)
	mat.set_shader_parameter(&"light_noise", CT.MOBILE_LIGHT_NOISE if _mobile else CT.LIGHT_NOISE)
	mat.set_shader_parameter(&"lobe_noise", CT.MOBILE_LOBE_NOISE if _mobile else CT.LOBE_NOISE)
	mat.set_shader_parameter(&"density", CT.DENSITY)
	mat.set_shader_parameter(&"absorption", CT.ABSORPTION)
	mat.set_shader_parameter(&"softness", CT.SOFTNESS)
	mat.set_shader_parameter(&"erosion", CT.EROSION)
	mat.set_shader_parameter(&"detail_erosion", CT.DETAIL_EROSION)
	mat.set_shader_parameter(&"noise_scale", CT.NOISE_SCALE)
	mat.set_shader_parameter(&"detail_scale", CT.DETAIL_SCALE)
	mat.set_shader_parameter(&"light_absorption", CT.LIGHT_ABSORPTION)
	mat.set_shader_parameter(&"powder_strength", CT.POWDER_STRENGTH)
	mat.set_shader_parameter(&"phase_forward_g", CT.PHASE_FORWARD_G)
	mat.set_shader_parameter(&"phase_back_g", CT.PHASE_BACK_G)
	mat.set_shader_parameter(&"lobe_shading", CT.LOBE_SHADING)
	mat.set_shader_parameter(&"near_fade_start", CT.NEAR_FADE_START)
	mat.set_shader_parameter(&"near_fade_end", CT.NEAR_FADE_END)
	var r: Rect2 = CT.CONTENT_RECT
	mat.set_shader_parameter(&"content_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	mat.set_shader_parameter(&"content_soft", CT.CONTENT_SOFT_EDGE)
	mat.set_shader_parameter(&"veil_ground_depth", CT.VEIL_GROUND_DEPTH)
	mat.set_shader_parameter(&"veil_content_depth", CT.VEIL_CONTENT_DEPTH)
	mat.set_shader_parameter(&"veil_content_cap", CT.VEIL_CONTENT_CAP)
	mat.set_shader_parameter(&"veil_edge_noise", CT.VEIL_EDGE_NOISE)
	mat.set_shader_parameter(&"veil_center", CT.VEIL_CENTER)
	mat.set_shader_parameter(&"veil_center_radius", CT.VEIL_CENTER_RADIUS)
	mat.set_shader_parameter(&"veil_player", CT.VEIL_PLAYER)
	mat.set_shader_parameter(&"veil_player_radius", CT.VEIL_PLAYER_RADIUS)

	var mesh := MeshInstance3D.new()
	mesh.name = "Cloud%d" % _clouds.size()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mesh)

	var phases := PackedFloat32Array()
	for i: int in (shape["blobs"] as PackedVector4Array).size():
		phases.append(_rng.randf_range(0.0, TAU))
	return {
		"mesh": mesh,
		"material": mat,
		"blobs": shape["blobs"],
		"phases": phases,
		"lift": shape["lift"],
		"radius": maxf(half.x, half.z),
		"position": Vector3.ZERO,
		"speed": CT.WIND_SPEED * (1.0 + _rng.randf_range(-CT.WIND_SPEED_JITTER, CT.WIND_SPEED_JITTER)),
		"noise_seed": Vector3(_rng.randf_range(0.0, 50.0), _rng.randf_range(0.0, 50.0), _rng.randf_range(0.0, 50.0)),
		"age": 0.0,
		"travel": 0.0,
		"travel_limit": INF,
		"kind": kind,
		"lane": 0.0,
		"lane_index": -1,
		"parked": false,
		"presence": 1.0,
	}


func _breathe(cloud: Dictionary) -> PackedVector4Array:
	var src: PackedVector4Array = cloud["blobs"]
	var phases: PackedFloat32Array = cloud["phases"]
	var out := PackedVector4Array()
	out.resize(src.size())
	var w: float = _time * CT.BREATHE_SPEED * TAU
	for i: int in src.size():
		var b: Vector4 = src[i]
		out[i] = Vector4(b.x, b.y, b.z, b.w * (1.0 + CT.BREATHE_AMOUNT * sin(w + phases[i])))
	return out


func _publish_shadow_texture(live: bool) -> void:
	if not _publish_shadow:
		return
	RenderingServer.global_shader_parameter_set(SHADOW_MAP_PARAM, _shadow.get_texture() if live else _empty_shadow)
	RenderingServer.global_shader_parameter_set(SHADOW_RECT_PARAM, _shadow.get_rect_vector())


func _ring_lanes() -> PackedFloat32Array:
	return CT.MOBILE_RING_LANES if _mobile else CT.RING_LANES


func _altitude_for(cloud: Dictionary) -> float:
	if int(cloud["kind"]) == Kind.RING:
		return _rng.randf_range(CT.RING_ALTITUDE_MIN, CT.RING_ALTITUDE_MAX) + float(cloud["lift"])
	return _rng.randf_range(CT.SKY_ALTITUDE_MIN, CT.SKY_ALTITUDE_MAX) + float(cloud["lift"])


## Square around the island, shifted toward the iso camera so ring clouds frame the island on screen.
func _make_ring_rect() -> Rect2:
	var dir: Vector3 = CT.ISO_VIEW_DIR.normalized()
	var mid: float = (CT.RING_ALTITUDE_MIN + CT.RING_ALTITUDE_MAX) * 0.5
	var pivot := Vector2(dir.x, dir.z) / dir.y * mid
	var half: float = CT.RING_HALF_SIZE
	return Rect2(pivot - Vector2(half, half), Vector2(half, half) * 2.0)


## World position on the cloud's lane (`lane` = offset across the wind from its rect center), `along` the wind.
func _lane_point(cloud: Dictionary, along: float) -> Vector3:
	var rect: Rect2 = _ring_rect if int(cloud["kind"]) == Kind.RING else area
	var normal := Vector2(-_wind.y, _wind.x)
	var p: Vector2 = rect.get_center() + normal * float(cloud["lane"]) + _wind * along
	p = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	return Vector3(p.x, _altitude_for(cloud), p.y)


## Sky clouds stay out of the iso frame around the island and fill the horizon instead.
func _pick_sky_lane(radius: float) -> float:
	var limit: float = minf(area.size.x, area.size.y) * 0.45
	var clear: float = CT.SKY_CLEAR_RADIUS + radius * 0.5
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	return side * _rng.randf_range(minf(clear, limit - 1.0), limit)


func _respawn_upwind(cloud: Dictionary) -> void:
	var kind: int = cloud["kind"]
	var rect: Rect2 = _ring_rect if kind == Kind.RING else area
	if kind == Kind.RING:
		var base: float = _ring_lanes()[int(cloud["lane_index"])]
		cloud["lane"] = base + _rng.randf_range(-CT.RING_LANE_JITTER, CT.RING_LANE_JITTER)
	else:
		cloud["lane"] = _pick_sky_lane(float(cloud["radius"]))
	var normal := Vector2(-_wind.y, _wind.x)
	var p0: Vector2 = rect.get_center() + normal * float(cloud["lane"])
	p0 = Vector2(clampf(p0.x, rect.position.x, rect.end.x), clampf(p0.y, rect.position.y, rect.end.y))
	var p: Vector2 = p0 - _wind * _exit_distance(rect, p0, -_wind)
	cloud["position"] = Vector3(p.x, _altitude_for(cloud), p.y)
	cloud["age"] = CT.SPAWN_FADE_TIME


## True when the cloud's center, where the iso camera sees it over the ground, lies inside the island superellipse.
func _over_island(pos: Vector3) -> bool:
	var dir: Vector3 = CT.ISO_VIEW_DIR.normalized()
	var seen := Vector2(pos.x, pos.z) - Vector2(dir.x, dir.z) / dir.y * pos.y
	var half: float = CT.ISLAND_HALF_SIZE
	var n: float = CT.ISLAND_SUPERELLIPSE_N
	return pow(absf(seen.x) / half, n) + pow(absf(seen.y) / half, n) <= 1.0


func _exit_distance(rect: Rect2, p: Vector2, dir: Vector2) -> float:
	var t: float = INF
	if absf(dir.x) > 1e-5:
		t = minf(t, ((rect.end.x if dir.x > 0.0 else rect.position.x) - p.x) / dir.x)
	if absf(dir.y) > 1e-5:
		t = minf(t, ((rect.end.y if dir.y > 0.0 else rect.position.y) - p.y) / dir.y)
	return maxf(t - 0.01, 0.0)


func _inside_distance(rect: Rect2, p: Vector2) -> float:
	return minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y))


## XZ point at `height` on the segment from the camera's ground focus back to the camera.
func _sightline_point(height: float) -> Vector2:
	var focus := Vector3.ZERO
	var back: Vector3 = CT.ISO_VIEW_DIR.normalized()
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var fwd: Vector3 = -cam.global_basis.z
		if fwd.y < -0.4:
			var origin: Vector3 = cam.global_position
			focus = origin + fwd * (-origin.y / fwd.y)
			back = -fwd
	var p: Vector3 = focus + back * (height / maxf(back.y, 0.1))
	return Vector2(p.x, p.z)
