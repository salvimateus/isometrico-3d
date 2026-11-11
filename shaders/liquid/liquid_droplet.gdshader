shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx, shadows_disabled;

// Particle droplet/streak: quad stretched along the particle Y axis (aligned to velocity), facing the camera.
// COLOR.a fades it; INSTANCE_CUSTOM.y is the particle age ratio.

uniform vec3 albedo : source_color = vec3(0.86, 0.95, 1.0);
uniform vec3 glow : source_color = vec3(0.35, 0.6, 0.7);
uniform float stretch = 1.0;
uniform float softness = 0.6;
uniform float day = 1.0;
uniform bool streak_mode = false;

varying float v_alpha;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 dir = length(axis) > 1e-5 ? normalize(axis) : vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = cross(dir, to_cam);
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float len = s * (1.0 + stretch);
	vec3 wp = center + side * VERTEX.x * s + dir * VERTEX.y * len;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(to_cam, 0.0)).xyz;
	v_alpha = COLOR.a;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	if (streak_mode) {
		a = (1.0 - smoothstep(0.3, 1.0, abs(c.x))) * (1.0 - smoothstep(0.5, 1.0, abs(c.y)));
		d = abs(c.x);
	}
	float core = 1.0 - smoothstep(0.0, 0.6, d);
	ALBEDO = albedo * COLOR.rgb;
	EMISSION = glow * core * (0.25 + 0.75 * day) * 0.6;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	ALPHA = a * v_alpha * (streak_mode ? 0.55 : 1.0);
}
