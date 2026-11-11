shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Cheap fake light halo (billboard quad) used where real lights are too expensive.
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.25);
uniform float intensity = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float fall = clamp(1.0 - d, 0.0, 1.0);
	fall = fall * fall;
	ALBEDO = color * fall * intensity;
}
