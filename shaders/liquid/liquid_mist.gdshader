shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Soft spray mist billboard with depth fade. COLOR.a carries the fade over life.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.93, 0.97, 1.0);
uniform float density = 0.4;
uniform float light = 1.0;

varying float v_alpha;
varying float v_seed;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = center + (right * VERTEX.x + up * VERTEX.y) * s;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	v_alpha = COLOR.a;
	v_seed = fract(dot(center, vec3(12.9898, 78.233, 37.719)));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 0.6 + vec2(v_seed, TIME * 0.05)).r;
	float a = (1.0 - smoothstep(0.2, 1.0, r)) * (0.55 + 0.6 * n);
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene_z = up.z / up.w;
	float soft = clamp((VERTEX.z - scene_z) / 0.6, 0.0, 1.0);
	ALBEDO = tint * light * COLOR.rgb;
	ALPHA = clamp(a * soft * density * v_alpha, 0.0, 1.0);
}
