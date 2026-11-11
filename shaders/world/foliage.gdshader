shader_type spatial;
render_mode cull_back, diffuse_burley;

// INSTANCE_CUSTOM: tint mode (a < -0.5): rgb = tint.
// Shake mode (a >= 0): r = brightness, g = warm/cool hue shift, b = bump time (world_time), a = bump direction angle.

global uniform vec3 player_position;
global uniform float world_time;
global uniform vec4 pond_splash;
global uniform float night_amount;

uniform float wind_strength = 1.0;
uniform float wind_speed = 1.2;
uniform float sway_amount = 0.06;
uniform float sway_height = 2.0;
uniform float rim_strength = 0.18;
uniform vec3 backlight_color : source_color = vec3(0.12, 0.2, 0.04);
uniform float roughness_value = 0.82;
uniform float camera_fade_near = 0.45;
uniform float camera_fade_far = 1.2;
uniform float push_radius = 1.0;
uniform float push_amount = 0.0;
uniform float shake_amount = 0.0;
uniform float shake_decay = 4.0;
uniform float shake_freq = 22.0;
uniform float splash_bob = 0.0;

varying vec3 vcol;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec4 custom = INSTANCE_CUSTOM;
	vec3 tint = custom.a < -0.5 ? custom.rgb : vec3(custom.r * (1.0 + custom.g), custom.r, custom.r * (1.0 - custom.g));
	vcol = COLOR.rgb * tint;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	float phase = dot(origin.xz, vec2(0.37, 0.23)) + TIME * wind_speed;
	float gust = 0.6 + 0.4 * sin(TIME * 0.45 + origin.x * 0.05);
	float bend = h * h * sway_amount * wind_strength * gust;
	vec3 offset_world = vec3(sin(phase) * bend, 0.0, cos(phase * 0.83 + 1.3) * bend * 0.7);

	if (push_amount > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 away = wp.xz - player_position.xz;
		float d = length(away);
		float near = (1.0 - smoothstep(push_radius * 0.3, push_radius, d)) * (1.0 - smoothstep(0.4, 1.6, abs(wp.y - player_position.y)));
		vec2 dir = away / max(d, 0.001);
		offset_world += vec3(dir.x, -0.35, dir.y) * near * h * push_amount;
	}
	if (custom.a >= 0.0 && shake_amount > 0.0) {
		float age = world_time - custom.b;
		if (age >= 0.0 && age < 3.0) {
			float s = exp(-age * shake_decay) * sin(age * shake_freq) * shake_amount * h * h;
			offset_world += vec3(cos(custom.a), 0.0, sin(custom.a)) * s;
		}
	}
	if (splash_bob > 0.0) {
		float sage = world_time - pond_splash.z;
		if (sage >= 0.0 && sage < 4.0) {
			float sd = distance(origin.xz, pond_splash.xy);
			float wave = sin(sd * 5.0 - sage * 9.0) * exp(-sage * 1.2) * exp(-sd * 0.35) * smoothstep(sage * 1.5 + 0.3, sage * 1.5 - 0.6, sd);
			offset_world.y += wave * splash_bob * 0.06 * pond_splash.w;
			offset_world.xz += normalize(origin.xz - pond_splash.xy + 0.001) * wave * splash_bob * 0.08 * pond_splash.w * h;
		}
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset_world;
}

void fragment() {
	float cam_dist = length(VERTEX);
	float keep = smoothstep(camera_fade_near, camera_fade_far, cam_dist);
	if (keep < 0.999) {
		vec2 px = floor(FRAGCOORD.xy);
		float bayer = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
		if (keep <= bayer) {
			discard;
		}
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vcol * mix(vec3(1.0), vec3(0.62, 0.74, 0.98), night_amount) * (1.0 + rim * rim_strength);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	BACKLIGHT = backlight_color;
}
