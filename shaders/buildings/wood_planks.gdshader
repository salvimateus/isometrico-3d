shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/buildings/common.gdshaderinc"
#include "res://shaders/buildings/patterns.gdshaderinc"

uniform vec3 color_light : source_color = vec3(0.66, 0.41, 0.23);
uniform vec3 color_dark : source_color = vec3(0.48, 0.29, 0.16);
uniform vec3 seam_color : source_color = vec3(0.28, 0.16, 0.08);
uniform float plank_width = 0.2;
uniform float plank_length = 2.4;
uniform bool horizontal = true;
// Mesh UV instead of world projection: keeps planks right on tilted parts.
uniform bool use_uv = false;
uniform float seam_width = 0.014;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = bld_planks(world_pos, world_nrm, UV, use_uv, horizontal, color_light, color_dark, seam_color,
		plank_width, plank_length, seam_width);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
