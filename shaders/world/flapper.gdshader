shader_type spatial;
render_mode cull_disabled, diffuse_burley, shadows_disabled;

uniform float flap_speed = 14.0;
uniform float flap_angle = 1.1;

varying vec3 vcol;

void vertex() {
	vcol = pow(COLOR.rgb, vec3(2.2));
	float phase = TIME * flap_speed + float(INSTANCE_ID) * 1.7;
	float a = sin(phase) * flap_angle;
	float side = sign(VERTEX.x);
	float r = abs(VERTEX.x);
	VERTEX.x = side * r * cos(a);
	VERTEX.y += r * sin(a);
}

void fragment() {
	ALBEDO = vcol;
	ROUGHNESS = 0.8;
	EMISSION = vcol * 0.12;
}
