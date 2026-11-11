shader_type spatial;

// Toy-paint skin for the head with procedural cheek blush, painted in mesh-local space.

uniform vec3 skin_color : source_color = vec3(0.941, 0.604, 0.361);
uniform vec3 blush_color : source_color = vec3(0.93, 0.42, 0.36);
uniform float blush_strength : hint_range(0.0, 1.0) = 0.55;
// Cheek centers in mesh-local space (x mirrored), and the blush radius.
uniform vec3 cheek_center = vec3(0.128, -0.03, 0.172);
uniform float blush_radius = 0.075;
uniform float roughness_value = 0.82;
uniform float rim_value = 0.35;
uniform float rim_tint_value = 0.6;
uniform float glow = 0.1;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = vec3(abs(local_pos.x), local_pos.yz);
	float d = length(p - cheek_center) / blush_radius;
	float mask = (1.0 - smoothstep(0.0, 1.0, d));
	mask *= mask;
	vec3 albedo = mix(skin_color, skin_color * blush_color * 1.35, mask * blush_strength);
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	RIM = rim_value;
	RIM_TINT = rim_tint_value;
	EMISSION = albedo * glow;
}
