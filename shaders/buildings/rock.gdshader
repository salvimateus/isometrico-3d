shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/buildings/common.gdshaderinc"
#include "res://shaders/buildings/patterns.gdshaderinc"

uniform vec3 color_light : source_color = vec3(0.62, 0.58, 0.52);
uniform vec3 color_dark : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 color_strata : source_color = vec3(0.66, 0.52, 0.38);
uniform float strata_scale = 3.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = bld_rock(world_pos, world_nrm, color_light, color_dark, color_strata, strata_scale);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
}
