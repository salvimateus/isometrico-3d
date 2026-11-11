shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color_main : source_color = vec3(0.85, 0.27, 0.18);
uniform vec3 color_trim : source_color = vec3(1.0, 0.79, 0.24);
uniform float trim_width = 0.12;
uniform float wave_speed = 4.0;
uniform float wave_amplitude = 0.07;
uniform float wave_length = 5.0;

void vertex() {
	float phase = NODE_POSITION_WORLD.x * 2.3 + NODE_POSITION_WORLD.z * 1.7;
	float k = UV.x;
	float w = sin(k * wave_length - TIME * wave_speed + phase);
	VERTEX.z += w * wave_amplitude * k;
	VERTEX.y -= k * k * wave_amplitude * 0.6;
	float dw = cos(k * wave_length - TIME * wave_speed + phase) * wave_length * wave_amplitude;
	NORMAL = normalize(vec3(-dw * k, 0.0, 1.0));
}

void fragment() {
	float border = min(min(UV.y, 1.0 - UV.y), 1.0 - UV.x);
	float t = step(trim_width, border);
	ALBEDO = mix(color_trim, color_main, t);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
