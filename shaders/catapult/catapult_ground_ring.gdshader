shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Flat ground marker on a unit quad (UV 0..1 spans 2 * extent).
// mode 0: landing target (blinking ring, inner dot, rotating tick marks).
// mode 1: impact shockwave (thin expanding ring fading out).
uniform int mode = 0;
uniform float extent = 2.6;
uniform float radius = 2.4;
uniform float thickness = 0.16;
uniform float blink = 0.0;
uniform float spin = 0.0;
uniform float opacity = 1.0;
uniform vec4 color : source_color = vec4(1.0, 0.82, 0.24, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float d = length(p);
	float aa = fwidth(d) * 1.5;
	if (mode == 0) {
		float ring = 1.0 - smoothstep(thickness * 0.5 - aa, thickness * 0.5 + aa, abs(d - radius));
		float outline = 1.0 - smoothstep(thickness * 0.5 + 0.05 - aa, thickness * 0.5 + 0.05 + aa, abs(d - radius));
		float dot_r = 0.16 + radius * 0.05;
		float center = 1.0 - smoothstep(dot_r - aa, dot_r + aa, d);
		float ang = atan(p.y, p.x) + spin;
		float ticks = step(0.7, abs(sin(ang * 4.0))) * (1.0 - smoothstep(0.05 - aa, 0.05 + aa, abs(d - radius * 0.62)));
		float fill = (1.0 - smoothstep(radius - 0.2, radius, d)) * 0.16;
		float pulse = 0.65 + 0.35 * blink;
		vec3 dark = vec3(0.08, 0.06, 0.12);
		float core = max(max(ring, center), ticks);
		vec3 col = mix(dark, mix(color.rgb, vec3(1.0), 0.35 * blink), core);
		float a = max(max(core, outline * 0.6), fill);
		ALBEDO = col;
		ALPHA = clamp(a * pulse, 0.0, 1.0) * opacity;
	} else {
		float ring = 1.0 - smoothstep(thickness * 0.5 - aa, thickness * 0.5 + aa, abs(d - radius));
		float inner = (1.0 - smoothstep(0.0, radius, d)) * smoothstep(radius * 0.4, radius, d) * 0.3;
		ALBEDO = color.rgb;
		ALPHA = clamp(ring + inner, 0.0, 1.0) * color.a * opacity;
	}
}
