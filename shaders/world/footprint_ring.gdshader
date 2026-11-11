shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 size = vec2(3.4, 3.4);
uniform vec3 line_color : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 glow_color : source_color = vec3(1.0, 0.85, 0.35);
uniform float line_width = 0.08;
uniform float corner_radius = 0.35;
uniform float appear = 1.0;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 half_size = size * 0.5 - vec2(0.25);
	float d = rounded_box(p, half_size, corner_radius);
	float line = 1.0 - smoothstep(line_width * 0.5, line_width * 0.5 + 0.03, abs(d));
	float glow = exp(-abs(d) * 7.0) * 0.55;
	float inner = step(d, 0.0) * 0.10;
	float march = 0.5 + 0.5 * sin((p.x + p.y) * 3.0 - TIME * 4.0);
	ALBEDO = mix(glow_color, line_color, line);
	ALPHA = clamp(line * (0.85 + 0.15 * march) + glow + inner, 0.0, 1.0) * appear;
}
