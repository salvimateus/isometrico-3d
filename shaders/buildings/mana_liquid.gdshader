shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 color_deep : source_color = vec3(0.45, 0.1, 0.62);
uniform vec3 color_bright : source_color = vec3(0.98, 0.5, 1.0);
uniform float emission_energy = 2.2;
uniform float pulse_speed = 1.7;
uniform float ripple = 0.025;

varying vec3 local_pos;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 1.7 + NODE_POSITION_WORLD.z * 1.1;
	float ang = atan(VERTEX.z, VERTEX.x);
	VERTEX += NORMAL * ripple * sin(VERTEX.y * 9.0 + ang * 3.0 + TIME * 2.3 + phase);
	local_pos = VERTEX;
}

void fragment() {
	float phase = NODE_POSITION_WORLD.x * 1.7 + NODE_POSITION_WORLD.z * 1.1;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float swirl = 0.5 + 0.5 * sin(local_pos.y * 7.0 - TIME * 1.4 + sin(local_pos.x * 5.0 + TIME * 0.9 + phase) * 1.5);
	float pulse = 0.78 + 0.22 * sin(TIME * pulse_speed + phase);
	vec3 col = mix(color_deep, color_bright, clamp(swirl * 0.55 + fres * 0.45, 0.0, 1.0));
	ALBEDO = col * 0.5;
	EMISSION = col * emission_energy * pulse;
	ROUGHNESS = 0.15;
	SPECULAR = 0.8;
}
