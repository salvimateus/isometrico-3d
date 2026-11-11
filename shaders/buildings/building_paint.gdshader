shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Single opaque material for baked buildings. Each vertex carries its source material's palette
// index in UV2.x; the palette texture (one column per material) holds everything else:
//   row 0: albedo rgb, pattern (0 plain, 1 stone, 2 planks, 3 roof, 4 rock)
//   row 1: secondary rgb (pattern dark / emission color), emission energy
//   row 2: roughness, metallic, specular, flags (1 horizontal planks, 2 mesh-UV planks)
//   row 3: pattern params (stone block size or plank width), emission kind (0 const, 1 window, 2 lantern, 3 mana)
//   row 4: tertiary rgb (stone mortar / plank seam)

#include "res://shaders/buildings/common.gdshaderinc"
#include "res://shaders/buildings/patterns.gdshaderinc"

global uniform float night_amount;

uniform sampler2D palette : filter_nearest, repeat_disable;
uniform vec3 moss_color : source_color = vec3(0.33, 0.42, 0.22);
uniform vec3 rock_strata : source_color = vec3(0.66, 0.52, 0.38);
uniform vec3 window_color : source_color = vec3(1.0, 0.78, 0.38);
uniform vec3 night_color : source_color = vec3(1.0, 0.46, 0.12);
uniform vec3 lantern_color : source_color = vec3(1.0, 0.84, 0.48);
uniform float window_day = 2.6;
uniform float window_night = 2.3;
uniform float lantern_day = 1.2;
uniform float lantern_night = 2.8;
uniform float mana_night_multiplier = 2.1;

varying vec3 world_pos;
varying vec3 world_nrm;
varying flat int mat_id;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat_id = int(UV2.x + 0.5);
}

void fragment() {
	vec4 r0 = texelFetch(palette, ivec2(mat_id, 0), 0);
	vec4 r1 = texelFetch(palette, ivec2(mat_id, 1), 0);
	vec4 r2 = texelFetch(palette, ivec2(mat_id, 2), 0);
	vec4 r3 = texelFetch(palette, ivec2(mat_id, 3), 0);
	vec3 r4 = texelFetch(palette, ivec2(mat_id, 4), 0).rgb;
	int pattern = int(r0.a + 0.5);
	int flags = int(r2.a + 0.5);
	vec3 col = r0.rgb;
	if (pattern == 1) {
		vec3 tilt;
		col = bld_stone(world_pos, world_nrm, r0.rgb, r1.rgb, r4, moss_color, r3.xy, 0.028, 0.07, 0.45, tilt);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	} else if (pattern == 2) {
		col = bld_planks(world_pos, world_nrm, UV, (flags & 2) != 0, (flags & 1) != 0, r0.rgb, r1.rgb, r4, r3.x, 2.4, 0.014);
	} else if (pattern == 3) {
		col = bld_roof(UV, r0.rgb, r1.rgb, vec2(0.26, 0.19));
	} else if (pattern == 4) {
		col = bld_rock(world_pos, world_nrm, r0.rgb, r1.rgb, rock_strata, 3.2);
	}
	int kind = int(r3.z + 0.5);
	vec3 emission = vec3(0.0);
	if (pattern == 0 && r1.a > 0.0) {
		emission = r1.rgb * r1.a;
		if (kind == 1) {
			emission = mix(window_color, night_color, night_amount) * mix(window_day, window_night, night_amount);
			col = mix(r0.rgb, night_color * 0.22, night_amount);
		} else if (kind == 2) {
			emission = mix(lantern_color, night_color, night_amount * 0.7) * mix(lantern_day, lantern_night, night_amount);
		} else if (kind == 3) {
			emission *= mix(1.0, mana_night_multiplier, night_amount);
		}
	}
	ALBEDO = col;
	ROUGHNESS = r2.x;
	METALLIC = r2.y;
	SPECULAR = r2.z;
	EMISSION = emission;
}
