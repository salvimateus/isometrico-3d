shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Billboard "ready to collect" badge: white round bubble with a tail, fill ring and coin or drop icon.

uniform int kind = 0;
uniform vec3 accent : source_color = vec3(1.0, 0.79, 0.24);
uniform vec3 accent_dark : source_color = vec3(0.83, 0.54, 0.07);
uniform vec3 body_color : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 outline_color : source_color = vec3(0.16, 0.11, 0.24);
uniform float aspect = 1.2;

instance uniform float fill = 1.0;
instance uniform float fade = 1.0;
instance uniform float glow = 0.0;

// 1 = respect scene depth (shoulder camera): occluded parts fade to occluded_alpha.
uniform float occlude = 0.0;
uniform float occluded_alpha = 0.15;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Wedge with apex at origin opening towards +y, `h` tall, `w` half width at the top.
float wedge(vec2 q, float w, float h) {
	vec2 n = normalize(vec2(h, -w));
	return max(dot(vec2(abs(q.x), q.y), n), q.y - h);
}

float shape(vec2 p) {
	float circle = length(p - vec2(0.0, 0.09)) - 0.39;
	float tail = wedge(p - vec2(0.0, -0.5), 0.13, 0.32) - 0.015;
	return smin(circle, tail, 0.06);
}

float drop(vec2 p) {
	float body = length(p - vec2(0.0, -0.04)) - 0.15;
	float tip = wedge(vec2(p.x, 0.27 - p.y), 0.125, 0.25);
	return smin(body, tip, 0.03);
}

vec4 over(vec4 dst, vec3 c, float a) {
	return vec4(mix(dst.rgb, c, a), dst.a + a * (1.0 - dst.a));
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, (0.5 - UV.y) * aspect);
	float aa = fwidth(p.x) * 1.2;
	vec4 col = vec4(0.0);

	float d = shape(p);
	float shadow = 1.0 - smoothstep(-0.02, 0.05, shape(p + vec2(0.0, 0.035)));
	col = over(col, vec3(0.0), shadow * 0.3);
	col = over(col, outline_color, 1.0 - smoothstep(0.03 - aa, 0.03 + aa, d));
	float body = 1.0 - smoothstep(-aa, aa, d);
	vec3 body_shaded = mix(body_color * vec3(0.86, 0.84, 0.9), body_color, smoothstep(-0.35, 0.3, p.y));
	col = over(col, body_shaded, body);

	vec2 c = p - vec2(0.0, 0.09);
	float r = length(c);
	// Fill ring, clockwise from the top.
	float ang = fract(atan(c.x, c.y) / TAU + 1.0);
	float ring = (1.0 - smoothstep(0.03 - aa, 0.03 + aa, abs(r - 0.33)));
	float ring_on = 1.0 - smoothstep(fill - 0.004, fill + 0.004, ang);
	col = over(col, mix(vec3(0.85, 0.84, 0.9), accent * (1.0 + glow * 0.35 * (0.5 + 0.5 * sin(TIME * 6.0))), ring_on), ring * body);

	// Inner disc tinted with the accent.
	float disc = 1.0 - smoothstep(0.27 - aa, 0.27 + aa, r);
	float tint = kind == 0 ? 0.72 : 0.55;
	vec3 disc_col = mix(mix(accent, body_color, tint), mix(accent, body_color, min(tint + 0.25, 0.95)), smoothstep(-0.25, 0.25, c.y));
	col = over(col, disc_col, disc);

	if (kind == 0) {
		vec2 q = c * vec2(1.0, 1.08);
		float rq = length(q);
		col = over(col, accent_dark * 0.45, 1.0 - smoothstep(0.205 - aa, 0.205 + aa, length(q + vec2(0.0, 0.025))));
		col = over(col, accent_dark, 1.0 - smoothstep(0.19 - aa, 0.19 + aa, rq));
		col = over(col, accent, 1.0 - smoothstep(0.165 - aa, 0.165 + aa, length(q - vec2(0.0, 0.01))));
		col = over(col, mix(accent_dark, accent, 0.45), 1.0 - smoothstep(0.115 - aa, 0.115 + aa, length(q - vec2(0.0, 0.01))));
		col = over(col, mix(accent, vec3(1.0, 0.92, 0.55), 0.3), 1.0 - smoothstep(0.095 - aa, 0.095 + aa, length(q - vec2(0.0, 0.02))));
		col = over(col, vec3(1.0), 0.9 * (1.0 - smoothstep(0.028 - aa, 0.028 + aa, length(q - vec2(-0.07, 0.085)))));
	} else {
		vec2 q = c + vec2(0.0, 0.02);
		float dd = drop(q);
		col = over(col, accent_dark * 0.75, 1.0 - smoothstep(0.018 - aa, 0.018 + aa, dd + 0.0) * 1.0);
		vec3 drop_col = mix(accent_dark, mix(accent, vec3(1.0, 0.8, 1.0), 0.25), smoothstep(-0.2, 0.15, q.y + q.x * 0.6));
		col = over(col, drop_col, 1.0 - smoothstep(-aa, aa, dd + 0.012));
		col = over(col, vec3(1.0, 0.92, 1.0), 0.85 * (1.0 - smoothstep(0.03 - aa, 0.03 + aa, length(q - vec2(-0.055, -0.03)))));
	}

	// Gloss crescent on the upper left of the bubble.
	float gloss = (1.0 - smoothstep(-aa, aa, length(c - vec2(-0.13, 0.17)) - 0.12)) * smoothstep(-aa, aa, length(c - vec2(-0.09, 0.13)) - 0.12);
	col = over(col, vec3(1.0), gloss * 0.55 * body);

	ALBEDO = col.rgb;
	float scene_z = texture(depth_tex, SCREEN_UV).r;
	float hidden = step(FRAGCOORD.z + 0.00002, scene_z);
	ALPHA = clamp(col.a, 0.0, 1.0) * fade * mix(1.0, occluded_alpha, hidden * occlude);
}
