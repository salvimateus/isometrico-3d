shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.85, 0.95, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = tint;
	ALPHA = mix(base_alpha, rim_alpha, fres);
	EMISSION = tint * fres * 0.15;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
