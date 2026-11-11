shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/buildings/common.gdshaderinc"
#include "res://shaders/buildings/patterns.gdshaderinc"

uniform vec3 color_base : source_color = vec3(0.85, 0.27, 0.18);
uniform vec3 color_shadow : source_color = vec3(0.66, 0.2, 0.12);
uniform vec2 tile_size = vec2(0.26, 0.19);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	ALBEDO = bld_roof(UV, color_base, color_shadow, tile_size);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.45;
}
