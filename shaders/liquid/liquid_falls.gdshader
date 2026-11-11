shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

// Waterfall curtain. UV.x = across the strip (0..1), UV.y = fall distance from the lip (world units),
// UV2.x = world coordinate along the edge (keeps noise continuous between strips). COLOR.a = local flow 0..1.

#ifndef LITE
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 body_color : source_color = vec3(0.42, 0.78, 0.88);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform float fall_rate = 1.1;
uniform float day = 1.0;
uniform vec3 moon_color : source_color = vec3(0.62, 0.71, 1.0);

varying float v_flow;

void vertex() {
	v_flow = COLOR.a;
}

void fragment() {
	float d = UV.y;
	float across = UV.x;
	float edge_u = UV2.x;
	// Fall time from distance (d = g t^2 / 2): texture phase in time units accelerates down the face.
	float t_fall = sqrt(2.0 * max(d, 0.0) / 9.8);
	float phase = t_fall * fall_rate * 3.0 - TIME * fall_rate;
	float n1 = texture(noise_tex, vec2(edge_u * 1.6, phase * 0.9)).r;
	float n2 = texture(noise_tex, vec2(edge_u * 4.5 + 0.37, phase * 1.7 + 0.21)).r;
	float n3 = texture(noise_tex, vec2(edge_u * 9.0 + 0.71, phase * 3.1)).r;
	float stretch = 1.0 + d * 0.6;

	// Rolling foam bands, whiter as the water accelerates and aerates.
	float aer = clamp(0.3 + d * 0.3, 0.0, 1.0);
	float bands = smoothstep(0.62 - aer * 0.35, 0.82 - aer * 0.35, n1 * 0.6 + n2 * 0.4);
	float streaks = smoothstep(0.55, 0.8, texture(noise_tex, vec2(edge_u * 12.0 / stretch, phase * 0.6)).r);
	float foam = clamp(bands + streaks * 0.5 * aer, 0.0, 1.0);

	// Ragged sides and thin flow tearing into filaments.
	float side = 1.0 - abs(across * 2.0 - 1.0);
	float rag = smoothstep(0.0, 0.35 + n3 * 0.4, side);
	float fil = smoothstep(1.0 - v_flow - 0.05, 1.15 - v_flow, n2 * 0.55 + n3 * 0.45 + v_flow * 0.35);
	float lip_fade = smoothstep(0.0, 0.12, d);

	vec3 vdir = normalize(VERTEX);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, -vdir)), 0.0, 1.0), 3.0);
	vec2 ruv = SCREEN_UV + vec2(n2 - 0.5, n1 - 0.5) * 0.03;
#ifdef LITE
	vec3 refr = vec3(0.75) * (0.3 + 0.7 * day);
#else
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
#endif
	float light = 0.3 + 0.7 * day;
	vec3 body = mix(refr * body_color, body_color * light, 0.35 + fres * 0.3);
	body += moon_color * (1.0 - day) * (0.12 + fres * 0.3);

	// Soft contact with the rock behind.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float soft = clamp((VERTEX.z - up.z / up.w) / 0.25, 0.0, 1.0);

	ALBEDO = foam_color * foam * light;
	EMISSION = body * (1.0 - foam) * 0.9 + foam_color * foam * 0.15 * light;
	ROUGHNESS = mix(0.08, 0.5, foam);
	SPECULAR = 0.5;
	ALPHA = clamp((0.68 + foam * 0.32 + aer * 0.1) * rag * fil * lip_fade * soft, 0.0, 1.0);
}
