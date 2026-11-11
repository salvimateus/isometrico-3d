shader_type spatial;
render_mode cull_back, diffuse_burley;

// Reference consumer of the cloud shadow globals published by the cloud field.
global uniform sampler2D cloud_shadow_map : filter_linear, repeat_disable;
global uniform vec4 cloud_shadow_rect;

uniform vec3 grass_color : source_color = vec3(0.486, 0.761, 0.263);
uniform vec3 grass_dark : source_color = vec3(0.39, 0.66, 0.21);
uniform float shadow_strength = 0.28;
uniform float tile = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / tile);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(grass_color, grass_dark, checker * 0.35);
	vec2 uv = (world_pos.xz - cloud_shadow_rect.xy) / cloud_shadow_rect.zw;
	float cover = clamp(texture(cloud_shadow_map, uv).r, 0.0, 1.0);
	col *= 1.0 - cover * shadow_strength;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
