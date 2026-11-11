shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, shadows_disabled;

// Expanding foam patch and ripple ring lying on a water surface. progress 0..1 over its life.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float progress = 0.0;
uniform float seed = 0.0;
uniform float ring_only = 0.0;
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform float day = 1.0;
uniform float ring_strength = 1.0;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float n = texture(noise_tex, UV * 1.7 + vec2(seed, seed * 0.7)).r;
	float n2 = texture(noise_tex, UV * 4.3 - vec2(seed * 0.3, progress * 0.2)).r;
	float ring_r = 0.35 + 0.6 * sqrt(progress);
	float ring = 1.0 - smoothstep(0.0, 0.07 + n * 0.05, abs(r - ring_r + (n - 0.5) * 0.08));
	float patch = (1.0 - smoothstep(0.25 + progress * 0.5, 0.55 + progress * 0.45, r + (n - 0.5) * 0.3)) * (1.0 - ring_only);
	float lace = smoothstep(0.45 + progress * 0.35, 0.6 + progress * 0.35, n2 * 0.7 + n * 0.5);
	float fade = 1.0 - smoothstep(0.35, 1.0, progress);
	float a = max(ring * mix(0.8, 0.45, ring_only) * ring_strength, patch * lace) * fade * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = foam_color * (0.4 + 0.6 * day);
	ROUGHNESS = 0.55;
	ALPHA = clamp(a, 0.0, 1.0);
}
