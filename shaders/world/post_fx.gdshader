shader_type canvas_item;

// Single fullscreen pass: radial chromatic aberration + animated monochrome film grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float ca_strength = 0.0042;
uniform float ca_start = 0.35;
uniform float grain_strength = 0.036;
uniform float grain_size = 1.0;
uniform float grain_fps = 24.0;
uniform float grain_highlight_keep = 0.35;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = vec2(centered.x * aspect, centered.y);
	float r = length(d) / length(vec2(0.5 * aspect, 0.5));
	float k = smoothstep(ca_start, 1.0, r);
	vec2 offset = centered * ca_strength * k * k;

	vec3 col;
	col.r = texture(screen_tex, uv + offset).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - offset).b;

	vec2 cell = floor(FRAGCOORD.xy / max(grain_size, 1.0));
	float frame = floor(TIME * grain_fps);
	float n = (hash13(vec3(cell, frame)) + hash13(vec3(cell + 17.0, frame + 3.0))) - 1.0;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float weight = mix(1.0, grain_highlight_keep, smoothstep(0.35, 0.95, lum));
	col += n * grain_strength * weight;

	COLOR = vec4(col, 1.0);
}
