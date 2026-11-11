shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world/noise.gdshaderinc"

global uniform float night_amount;
global uniform float world_time;
global uniform vec4 pond_splash;
global uniform sampler2D cloud_shadow_map : filter_linear, repeat_disable;
global uniform vec4 cloud_shadow_rect;
uniform float cloud_strength = 0.22;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.247, 0.776, 0.847);
uniform vec3 deep_color : source_color = vec3(0.09, 0.47, 0.68);
uniform vec3 far_color : source_color = vec3(0.10, 0.42, 0.64);
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);
uniform float depth_range = 2.6;
uniform float foam_width = 0.32;
uniform float ring_reach = 0.85;
uniform float far_start = 26.0;
uniform float far_end = 75.0;
uniform float wave_scale = 0.22;
uniform float wave_speed = 0.35;
uniform float shallow_alpha = 0.55;
uniform float caustic_strength = 0.55;
uniform float ring_strength = 0.75;
uniform float night = 0.0;
uniform float splash_enabled = 0.0;
uniform vec3 night_tint : source_color = vec3(0.30, 0.45, 0.62);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;

	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec3 scene_view = upos.xyz / upos.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float depth = max(world_pos.y - scene_world.y, 0.0);

	vec2 wp = p * wave_scale;
	float w1 = vnoise(wp + vec2(t, t * 0.6));
	float w2 = vnoise(wp * 1.9 - vec2(t * 0.7, -t * 0.9) + 11.0);
	float waves = w1 * 0.6 + w2 * 0.4;
	float e = 0.08;
	float wx = vnoise(wp + vec2(t + e, t * 0.6)) * 0.6 + vnoise((wp + vec2(e, 0.0)) * 1.9 - vec2(t * 0.7, -t * 0.9) + 11.0) * 0.4;
	float wz = vnoise(wp + vec2(t, t * 0.6 + e)) * 0.6 + vnoise((wp + vec2(0.0, e)) * 1.9 - vec2(t * 0.7, -t * 0.9) + 11.0) * 0.4;
	vec3 n_world = normalize(vec3((waves - wx) * 1.4, 1.0, (waves - wz) * 1.4));
	float splash_foam = 0.0;
	float splash_age = world_time - pond_splash.z;
	if (splash_enabled > 0.5 && splash_age >= 0.0 && splash_age < 4.0) {
		vec2 sd = p - pond_splash.xy;
		float sr = length(sd);
		float env = exp(-splash_age * 1.1) * pond_splash.w;
		for (int i = 0; i < 4; i++) {
			float ring_r = splash_age * 1.5 - float(i) * 0.38;
			if (ring_r > 0.0) {
				float k = (sr - ring_r) * 9.0;
				float line = exp(-k * k);
				splash_foam += line * env * (1.0 - float(i) * 0.2) * 0.9;
				n_world.xz += (sd / max(sr, 0.001)) * cos(k) * line * env * 0.6;
			}
		}
		splash_foam += (1.0 - smoothstep(0.0, 0.55, sr)) * exp(-splash_age * 3.0) * pond_splash.w;
		n_world = normalize(n_world);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float d01 = smoothstep(0.0, depth_range, depth);
	vec3 col = mix(shallow_color * 1.08, deep_color, d01);
	col = mix(col, col * 1.12, smoothstep(0.55, 0.85, waves));
	vec2 pc = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	float cells = abs(vnoise(pc * 0.8 + vec2(t * 0.6, -t * 0.4)) - vnoise(pc.yx * 0.7 + vec2(-t * 0.5, t * 0.7) + 7.3));
	float caustic = (1.0 - smoothstep(0.0, 0.06, cells)) * (1.0 - smoothstep(0.4, depth_range * 0.7, depth));
	col += vec3(0.35, 0.45, 0.45) * caustic * caustic_strength;

	float foam_noise = vnoise(p * 1.6 + vec2(t * 1.3, -t));
	float edge_foam = 1.0 - smoothstep(foam_width * (0.55 + 0.9 * foam_noise), foam_width * (0.55 + 0.9 * foam_noise) + 0.06, depth);
	float ring_phase = fract(depth / ring_reach * 1.4 - TIME * 0.22);
	float ring = smoothstep(0.0, 0.06, ring_phase) * (1.0 - smoothstep(0.1, 0.2, ring_phase));
	ring *= 1.0 - smoothstep(min(0.3, ring_reach * 0.5), ring_reach, depth);
	ring *= step(0.45, foam_noise + 0.25);
	float foam = clamp(edge_foam + ring * ring_strength + splash_foam, 0.0, 1.0);

	float dist = length(p);
	float far = smoothstep(far_start, far_end, dist);


	col = mix(col, far_color, far);
	col = mix(col, foam_color, foam);
	col *= mix(vec3(1.0), night_tint * (1.0 + foam * 1.5), night);
	float cloud = clamp(texture(cloud_shadow_map, (world_pos.xz - cloud_shadow_rect.xy) / cloud_shadow_rect.zw).r, 0.0, 1.0);
	col *= 1.0 - cloud * cloud_strength * mix(1.0, 0.5, night_amount);
	ALBEDO = col;
	EMISSION = foam_color * foam * mix(0.08, 0.02, night);
	ROUGHNESS = mix(mix(0.08, 0.16, night), 0.6, foam);
	SPECULAR = 0.35;
	ALPHA = clamp(mix(shallow_alpha, 1.0, smoothstep(0.0, depth_range * 0.8, depth)) + foam + far, 0.0, 1.0);
}
