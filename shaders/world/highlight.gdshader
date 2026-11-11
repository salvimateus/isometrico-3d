shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

// Additive overlay: thin silhouette rim plus a faint warm lift, so base colors keep their saturation.

uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.45);
uniform float strength = 0.45;
uniform float rim_power = 5.0;
uniform float fill = 0.0;
uniform float pulse = 0.0;
uniform float pulse_speed = 3.5;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	float p = 1.0 + pulse * sin(TIME * pulse_speed);
	ALBEDO = rim_color * (rim * strength + fill) * p;
}
