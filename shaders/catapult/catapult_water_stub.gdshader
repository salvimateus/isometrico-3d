shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

// Sandbox pond: flat tinted water with expanding splash rings (xz = local center, z = age, w = strength).
uniform vec4 water_color : source_color = vec4(0.25, 0.65, 0.9, 0.75);
uniform vec4 ring_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform vec4 splashes[8];
uniform float ring_speed = 2.2;
uniform float ring_life = 1.6;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float rings = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 s = splashes[i];
		if (s.w <= 0.0 || s.z >= ring_life) {
			continue;
		}
		float d = length(local_pos.xz - s.xy);
		float fade = 1.0 - s.z / ring_life;
		for (int k = 0; k < 3; k++) {
			float r = max(s.z - float(k) * 0.25, 0.0) * ring_speed;
			float w = 0.06 + 0.05 * float(k);
			rings += (1.0 - smoothstep(0.0, w, abs(d - r))) * fade * min(s.w, 1.0) * step(0.001, r);
		}
	}
	rings = clamp(rings, 0.0, 1.0);
	ALBEDO = mix(water_color.rgb, ring_color.rgb, rings);
	ALPHA = mix(water_color.a, 0.95, rings);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
