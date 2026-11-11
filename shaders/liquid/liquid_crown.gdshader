shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Splash crown: open tapered tube that rises and tears into fingers. UV.x around, UV.y up; progress 0..1.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float progress = 0.0;
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 body_color : source_color = vec3(0.55, 0.85, 0.92);
uniform float seed = 0.0;

void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 3.0 + seed, UV.y * 0.6 + progress * 0.4)).r;
	float fingers = texture(noise_tex, vec2(UV.x * 19.0 + seed * 2.0, 0.3)).r;
	float top = 1.0 - UV.y;
	float tear = smoothstep(progress * 1.25 - 0.1, progress * 1.25 + 0.15, n * 0.8 + top * 0.5);
	float finger_cut = 1.0 - smoothstep(0.25 + fingers * 0.75, 0.32 + fingers * 0.75, UV.y);
	float a = tear * finger_cut * (1.0 - smoothstep(0.65, 1.0, progress));
	float white = smoothstep(0.35, 0.9, n + UV.y * 0.4);
	ALBEDO = mix(body_color, foam_color, white);
	ROUGHNESS = 0.3;
	ALPHA = clamp(a * mix(0.35, 0.8, white), 0.0, 1.0);
}
