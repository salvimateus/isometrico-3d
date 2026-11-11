shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/world/noise.gdshaderinc"

global uniform float night_amount;
global uniform sampler2D cloud_shadow_map : filter_linear, repeat_disable;
global uniform vec4 cloud_shadow_rect;
uniform float cloud_strength = 0.2;


varying vec3 world_pos;
varying vec3 vcol;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR.rgb;
}

void fragment() {
	vec2 p = world_pos.xz;
	float along = p.x * 0.7 + p.y * 0.7;
	float grain = vnoise(vec2(along * 1.4, world_pos.y * 3.0));
	float speck = vnoise(vec2(along * 6.0, world_pos.y * 9.0));
	float strata = smoothstep(0.35, 0.65, vnoise(vec2(along * 0.25, world_pos.y * 1.6 + 4.0)));
	vec3 col = vcol * (0.92 + 0.12 * grain) * (0.96 + 0.06 * speck);
	float rock = step(world_pos.y, -1.25);
	col *= mix(1.0, 0.94 + 0.10 * strata, rock);
	float top_light = clamp(NORMAL.y, 0.0, 1.0);
	float cloud = clamp(texture(cloud_shadow_map, (world_pos.xz - cloud_shadow_rect.xy) / cloud_shadow_rect.zw).r, 0.0, 1.0);
	col *= 1.0 - cloud * cloud_strength * mix(1.0, 0.5, night_amount);
	col *= mix(vec3(1.0), vec3(0.62, 0.74, 0.98), night_amount);
	ALBEDO = col * (1.0 + 0.06 * top_light);
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
}
