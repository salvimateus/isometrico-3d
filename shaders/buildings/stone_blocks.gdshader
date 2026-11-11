shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/buildings/common.gdshaderinc"
#include "res://shaders/buildings/patterns.gdshaderinc"

uniform vec3 color_light : source_color = vec3(0.76, 0.73, 0.68);
uniform vec3 color_dark : source_color = vec3(0.56, 0.53, 0.49);
uniform vec3 mortar_color : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 moss_color : source_color = vec3(0.33, 0.42, 0.22);
uniform vec2 block_size = vec2(0.46, 0.24);
uniform float mortar_width = 0.028;
uniform float bevel_width = 0.07;
uniform float moss_height = 0.45;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 tilt;
	ALBEDO = bld_stone(world_pos, world_nrm, color_light, color_dark, mortar_color, moss_color, block_size,
		mortar_width, bevel_width, moss_height, tilt);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
