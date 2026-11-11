shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// mode 0: speech bubble (pill with border, drop shadow and a tail at the bottom).
// mode 1: radial burst (expanding ring plus rays) driven by progress 0..1.
uniform int mode = 0;
uniform vec2 size = vec2(1.5, 0.78);
uniform vec4 fill_color : source_color = vec4(0.08, 0.1, 0.18, 0.78);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform vec4 accent_color : source_color = vec4(1.0, 0.79, 0.24, 1.0);
uniform float progress = 0.0;
uniform float opacity = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sd_tail(vec2 p, float w, float h) {
	// Downward triangle under the pill, apex at y = -h.
	vec2 q = vec2(abs(p.x), p.y);
	float edge = dot(q - vec2(0.0, -h), normalize(vec2(h, w)));
	return max(edge, q.y - 0.02);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(size.x, -size.y);
	float aa = fwidth(p.y) * 1.2;
	if (mode == 0) {
		float tail_h = size.y * 0.22;
		vec2 c = p - vec2(0.0, tail_h * 0.5);
		vec2 half_box = vec2(size.x * 0.5, (size.y - tail_h) * 0.5) - vec2(0.05);
		float r = half_box.y;
		float body = sd_round_box(c, half_box, r);
		float tail = sd_tail(c + vec2(0.0, half_box.y - 0.02), size.y * 0.13, tail_h);
		float d = min(body, tail);
		float shadow = sd_round_box(c + vec2(0.0, 0.045), half_box, r);
		float shadow_a = (1.0 - smoothstep(-0.02, 0.06, shadow)) * 0.35;
		float inside = 1.0 - smoothstep(-aa, aa, d);
		float border_w = 0.045;
		float border = smoothstep(-border_w - aa, -border_w + aa, d);
		// Soft top highlight, like the HUD glass.
		float gloss = smoothstep(0.0, half_box.y, c.y) * 0.12;
		vec3 col = mix(fill_color.rgb + gloss, border_color.rgb, border);
		float a = mix(fill_color.a, border_color.a, border) * inside;
		float out_a = a + shadow_a * (1.0 - a);
		ALBEDO = col * a / max(out_a, 1e-4);
		ALPHA = out_a * opacity;
	} else {
		float r = length(p) / (size.x * 0.5);
		float t = clamp(progress, 0.0, 1.0);
		float ring_r = mix(0.25, 1.0, 1.0 - pow(1.0 - t, 3.0));
		float ring_w = mix(0.16, 0.02, t);
		float ring = 1.0 - smoothstep(ring_w * 0.6, ring_w, abs(r - ring_r));
		float ang = atan(p.y, p.x);
		float rays = smoothstep(0.55, 1.0, abs(sin(ang * 6.0)));
		float ray_band = smoothstep(ring_r * 0.35, ring_r * 0.6, r) * (1.0 - smoothstep(ring_r * 0.75, ring_r * 0.95, r));
		float glow = (1.0 - smoothstep(0.0, ring_r * 0.7, r)) * (1.0 - t) * 0.35;
		float a = max(ring, rays * ray_band * (1.0 - t) * 0.8) + glow;
		ALBEDO = mix(accent_color.rgb, vec3(1.0), glow);
		ALPHA = clamp(a, 0.0, 1.0) * accent_color.a * (1.0 - t * t) * opacity;
	}
}
