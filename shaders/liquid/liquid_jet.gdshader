shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Pouring jet: refractive glassy core that aerates into white water along its fall. UV.y = flight time.

#ifndef LITE
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.55, 0.86, 0.9);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 scatter_color : source_color = vec3(0.18, 0.62, 0.72);
uniform float scroll = 2.4;
uniform float aeration = 1.4;
uniform float flow = 1.0;
uniform float day = 1.0;

varying float v_t;

void vertex() {
	v_t = UV.y;
}

void fragment() {
	float u = UV.x;
	float along = UV.y;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec2 sp = vec2(u * 3.0, along * 3.2 - TIME * scroll);
	float streak = texture(foam_tex, sp * vec2(1.0, 0.35)).r;
	float streak2 = texture(foam_tex, sp * vec2(2.0, 0.8) + vec2(0.3, TIME * 0.7)).r;
	float air = clamp(along * aeration + 0.15, 0.0, 1.0);
	float white = smoothstep(0.9 - air * 0.6, 1.1 - air * 0.6, streak * 0.75 + streak2 * 0.45 + fres * 0.3);
	white = max(white, smoothstep(0.55, 1.0, fres) * 0.35);

	vec2 ruv = SCREEN_UV + NORMAL.xy * 0.035;
#ifdef LITE
	vec3 refr = tint * mix(0.3, 0.8, day);
#else
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb * tint;
#endif
	vec3 body = mix(refr, scatter_color * (0.35 + 0.65 * day), 0.25 + fres * 0.25);

	float edge_break = smoothstep(0.0, 0.25, 1.0 - abs(u * 2.0 - 1.0) * 0.0);
	ALBEDO = foam_color * white;
	EMISSION = body * (1.0 - white);
	ROUGHNESS = mix(0.04, 0.55, white);
	SPECULAR = 0.5;
	float tail = smoothstep(0.0, 0.08, along);
	// Silhouette tears into ragged sheets, more so as the stream falls.
	float tear_n = texture(foam_tex, vec2(u * 4.0 + along * 0.7, along * 2.0 - TIME * scroll * 0.6)).r;
	float tear = smoothstep(0.35 + along * 0.25, 0.5 + along * 0.25, tear_n + (1.0 - fres) * 0.6);
	ALPHA = clamp((0.86 + fres * 0.14) * flow * edge_break * tail * tear + white * 0.25 * tear, 0.0, 1.0);
}
