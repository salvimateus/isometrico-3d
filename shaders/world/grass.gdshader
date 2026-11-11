shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world/noise.gdshaderinc"

global uniform float night_amount;
global uniform sampler2D cloud_shadow_map : filter_linear, repeat_disable;
global uniform vec4 cloud_shadow_rect;
global uniform sampler2D liquid_wetness_map : filter_linear, repeat_disable;
global uniform vec4 liquid_area;


uniform sampler2D ground_data : filter_linear, repeat_disable;
uniform vec4 data_rect = vec4(-20.0, -20.0, 40.0, 40.0);
uniform vec3 grass_color : source_color = vec3(0.486, 0.761, 0.263);
uniform vec3 grass_light : source_color = vec3(0.592, 0.839, 0.353);
uniform vec3 grass_dark : source_color = vec3(0.373, 0.659, 0.204);
uniform vec3 worn_color : source_color = vec3(0.70, 0.72, 0.36);
uniform vec3 dirt_light : source_color = vec3(0.851, 0.698, 0.486);
uniform vec3 dirt_dark : source_color = vec3(0.725, 0.541, 0.322);
uniform vec3 pond_bed : source_color = vec3(0.55, 0.62, 0.42);
uniform vec3 damp_grass : source_color = vec3(0.27, 0.55, 0.20);
uniform float play_half = 11.0;
uniform float checker_strength = 0.045;
uniform float cloud_strength = 0.28;

varying vec3 world_pos;

vec4 texture_bicubic(sampler2D tex, vec2 uv, vec2 res) {
	vec2 st = uv * res - 0.5;
	vec2 i = floor(st);
	vec2 f = fract(st);
	vec2 w0 = (1.0 / 6.0) * (-f * f * f + 3.0 * f * f - 3.0 * f + 1.0);
	vec2 w1 = (1.0 / 6.0) * (3.0 * f * f * f - 6.0 * f * f + 4.0);
	vec2 w2 = (1.0 / 6.0) * (-3.0 * f * f * f + 3.0 * f * f + 3.0 * f + 1.0);
	vec2 w3 = (1.0 / 6.0) * (f * f * f);
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (w1 / g0) - 0.5 + i;
	vec2 h1 = (w3 / g1) + 1.5 + i;
	vec4 t00 = texture(tex, (vec2(h0.x, h0.y) + 0.5) / res);
	vec4 t10 = texture(tex, (vec2(h1.x, h0.y) + 0.5) / res);
	vec4 t01 = texture(tex, (vec2(h0.x, h1.y) + 0.5) / res);
	vec4 t11 = texture(tex, (vec2(h1.x, h1.y) + 0.5) / res);
	return mix(mix(t00, t10, g1.x / (g0.x + g1.x)), mix(t01, t11, g1.x / (g0.x + g1.x)), g1.y / (g0.y + g1.y));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n_large = fbm3(p * 0.11);
	float n_mid = vnoise(p * 0.65 + 3.1);
	vec2 pr = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * p;
	float n_fine = 0.5 * (vnoise(pr * 3.7) + vnoise(pr.yx * 2.9 + 5.1));

	vec3 col = mix(grass_dark, grass_color, smoothstep(0.18, 0.5, n_large));
	col = mix(col, grass_light, smoothstep(0.6, 0.88, n_large) * 0.7);
	col *= 0.9 + 0.16 * n_fine;
	col *= 0.93 + 0.1 * smoothstep(0.3, 0.7, n_mid);
	col = mix(col, grass_light, smoothstep(0.72, 0.95, n_mid) * 0.25);

	vec2 q = abs(p) - vec2(play_half);
	float in_play = 1.0 - smoothstep(-0.2, 0.6, max(q.x, q.y));
	float checker = mod(floor(p.x) + floor(p.y), 2.0) * 2.0 - 1.0;
	col *= 1.0 + checker * checker_strength * in_play;

	vec2 uv = (p - data_rect.xy) / data_rect.zw;
	vec4 data = texture_bicubic(ground_data, uv, data_rect.zw);
	float edge_noise = (n_mid - 0.5) * 0.22 + (n_fine - 0.5) * 0.08;

	float worn = smoothstep(0.2, 0.34, data.r + edge_noise);
	float worn_core = smoothstep(0.5, 0.85, data.r + edge_noise);
	vec3 worn_col = mix(worn_color * (0.92 + 0.12 * n_fine), dirt_light * (0.9 + 0.15 * n_fine), worn_core * 0.55);
	col = mix(col, worn_col, worn * 0.9);

	float path_v = data.g + edge_noise;
	float path = smoothstep(0.32, 0.42, path_v);
	float path_rim = path * (1.0 - smoothstep(0.42, 0.56, path_v));
	vec3 path_col = mix(dirt_light, dirt_dark, smoothstep(0.45, 0.8, n_fine) * 0.35 + path_rim * 0.5);
	path_col *= 0.96 + 0.08 * n_mid;
	col = mix(col, path_col, path);

	float low = smoothstep(-0.01, -0.22, world_pos.y);
	float pond_area = smoothstep(0.3, 0.7, data.b);
	col = mix(col, damp_grass * (0.92 + 0.16 * n_fine), low * (1.0 - pond_area) * 0.55);
	float wet = smoothstep(-0.05, -0.32, world_pos.y) * pond_area;
	col = mix(col, pond_bed * (0.9 + 0.2 * n_fine), wet);

	float cloud = clamp(texture(cloud_shadow_map, (world_pos.xz - cloud_shadow_rect.xy) / cloud_shadow_rect.zw).r, 0.0, 1.0);
	col *= 1.0 - cloud * cloud_strength * mix(1.0, 0.5, night_amount);

	col *= mix(vec3(1.0), vec3(0.62, 0.74, 0.98), night_amount);
	vec2 luv = (world_pos.xz - liquid_area.xy) / liquid_area.zw;
	float liquid_wet = (all(greaterThanEqual(luv, vec2(0.0))) && all(lessThanEqual(luv, vec2(1.0)))) ? smoothstep(0.0, 0.6, texture(liquid_wetness_map, luv).r) : 0.0;
	col *= mix(1.0, 0.55, liquid_wet);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.85, path), 0.28, liquid_wet);
	SPECULAR = 0.25;
}
