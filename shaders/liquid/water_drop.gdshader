shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, world_vertex_coords, shadows_disabled, diffuse_lambert, specular_schlick_ggx;

// MultiMesh water drop: camera-facing quad stretched along the instance Y axis (velocity).
// Instance X length = radius, Y length = half length. COLOR.a = fade, INSTANCE_CUSTOM.x = foam core.

uniform vec3 rim_color : source_color = vec3(0.42, 0.74, 0.96);
uniform vec3 body_color : source_color = vec3(0.62, 0.86, 0.97);
uniform vec3 core_color : source_color = vec3(0.97, 0.99, 1.0);
uniform float day = 1.0;

varying float v_alpha;
varying float v_foam;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	vec3 dir = len > 1e-5 ? axis / len : vec3(0.0, 1.0, 0.0);
	float w = length(MODEL_MATRIX[0].xyz);
	float cam_d = length(CAMERA_POSITION_WORLD - center);
	vec3 to_cam = (CAMERA_POSITION_WORLD - center) / max(cam_d, 1e-4);
	// Near the lens: fade out and cap the on-screen size so drops stay fine spray, not soap bubbles.
	w = min(w, cam_d * 0.006);
	len = min(len, cam_d * 0.035);
	vec3 side = cross(dir, to_cam);
	float sl = length(side);
	// Seen along its motion a drop is round, not a needle.
	float along = clamp(sl * 1.4, 0.0, 1.0);
	side = sl > 1e-4 ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 up = normalize(cross(to_cam, side));
	vec3 ax = normalize(mix(up, dir * sign(dot(dir, up) + 1e-4), along));
	float l = mix(w, max(len, w), along);
	vec2 q = (UV - 0.5) * vec2(2.0, -2.0);
	VERTEX = center + side * q.x * w + ax * q.y * l;
	NORMAL = to_cam;
	v_alpha = COLOR.a * smoothstep(0.6, 1.6, cam_d);
	v_foam = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float z = sqrt(max(1.0 - r * r, 0.0));
	NORMAL = normalize(vec3(c.x, -c.y, z));
	float fres = 1.0 - z;
	float mask = 1.0 - smoothstep(0.78, 1.0, r);
	float core = (1.0 - smoothstep(0.0, 0.6, r)) * v_foam;
	float light = 0.35 + 0.65 * day;
	ALBEDO = mix(body_color * 0.35, core_color, core);
	EMISSION = (rim_color * fres * 0.7 + body_color * 0.08 + core_color * core * 0.3) * light;
	ROUGHNESS = mix(0.05, 0.4, core);
	SPECULAR = 0.9;
	ALPHA = mask * clamp(0.3 + fres * 0.7 + core * 0.9, 0.0, 1.0) * v_alpha;
}
