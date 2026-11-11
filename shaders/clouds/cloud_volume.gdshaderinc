// Shared body of the cloud raymarch; the including shader sets render_mode (and CLOUD_ANALYTIC_GROUND on mobile).

#define MAX_BLOBS 12

global uniform vec3 player_position;

uniform vec4 blobs[MAX_BLOBS];
uniform int blob_count = 0;
uniform vec3 half_extents = vec3(5.0);
uniform float base_y = -2.0;
uniform float top_y = 2.0;
uniform float fade = 1.0;
uniform vec3 noise_offset = vec3(0.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;
#ifndef CLOUD_ANALYTIC_GROUND
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
#else
// Mobile: no depth copy; the scene behind a cloud is approximated by the plane y = ground_y.
uniform float ground_y = 0.0;
#endif

uniform int max_steps = 56;
uniform float step_length = 0.42;
uniform int light_steps = 4;
uniform bool light_noise = true;
uniform bool lobe_noise = true;
uniform float density = 1.0;
uniform float absorption = 3.2;
uniform float softness = 0.9;
uniform float erosion = 0.75;
uniform float detail_erosion = 0.35;
uniform float noise_scale = 0.075;
uniform float detail_scale = 0.21;

uniform vec3 light_dir = vec3(-0.6, 0.74, 0.27);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.8);
uniform float sun_intensity = 1.35;
uniform vec3 top_color : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 base_color : source_color = vec3(0.58, 0.66, 0.82);
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.9);
uniform float rim_strength = 1.0;
uniform float light_absorption = 0.9;
uniform float powder_strength = 0.55;
uniform float phase_forward_g = 0.6;
uniform float phase_back_g = -0.2;
// Half-lambert on the billow normal at the first hit: carves lobes when seen from above.
uniform float lobe_shading = 0.55;
uniform vec3 lobe_shadow_tint : source_color = vec3(0.62, 0.7, 0.88);

uniform float near_fade_start = 1.5;
uniform float near_fade_end = 9.0;
uniform vec4 content_rect = vec4(-17.0, -17.0, 34.0, 34.0);
uniform float content_soft = 8.0;
// Veil: over ground the optical depth is scaled down (thin parts clear first, cores keep their form),
// then opacity is capped; near the target an extra fade with a noise-cut edge opens a window.
uniform float veil_ground_depth = 0.8;
uniform float veil_content_depth = 0.45;
uniform float veil_content_cap = 0.75;
uniform float veil_center = 0.8;
uniform float veil_center_radius = 0.3;
uniform float veil_player = 0.3;
uniform float veil_player_radius = 0.13;
uniform float veil_edge_noise = 0.9;

float smin(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

float envelope(vec3 p) {
	float d = 1e5;
	for (int i = 0; i < MAX_BLOBS; i++) {
		if (i >= blob_count) {
			break;
		}
		vec4 b = blobs[i];
		d = smin(d, length(p - b.xyz) - b.w, 1.8);
	}
	return max(d, (base_y - p.y) * 1.6);
}

float sample_density(vec3 p, float env) {
	vec3 q = p + noise_offset;
	float base = texture(noise_tex, q * noise_scale).r;
	float fine = texture(noise_tex, q * detail_scale + vec3(0.37, 0.11, 0.73)).g;
	float shape = -env / softness;
	float inner = clamp(shape, 0.0, 1.0);
	float d = shape + (base - 0.5) * erosion * 2.0 - (1.0 - fine) * detail_erosion * (1.0 - inner);
	return clamp(d, 0.0, 1.0) * density;
}

// Low-frequency density field without clamping, for the surface normal at the first hit.
float surface_field(vec3 p) {
	if (!lobe_noise) {
		return -envelope(p) / softness;
	}
	vec3 q = p + noise_offset;
	float base = texture(noise_tex, q * noise_scale).r;
	float fine = texture(noise_tex, q * detail_scale + vec3(0.37, 0.11, 0.73)).g;
	return -envelope(p) / softness + (base - 0.5) * erosion * 2.0 - (1.0 - fine) * detail_erosion * 0.5;
}

float light_depth(vec3 p) {
	float od = 0.0;
	float travelled = 0.0;
	float seg = 0.3;
	for (int j = 0; j < light_steps; j++) {
		vec3 q = p + light_dir * (travelled + seg * 0.5);
		float erode = 0.15;
		if (light_noise) {
			erode = (texture(noise_tex, (q + noise_offset) * noise_scale).r - 0.5) * erosion * 2.0;
		}
		od += clamp(-envelope(q) / softness + erode, 0.0, 1.0) * seg;
		travelled += seg;
		seg *= 1.7;
	}
	return od * density;
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}

float ign(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 frag_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(frag_world - cam);
	vec3 ro = cam - MODEL_MATRIX[3].xyz;

	vec3 inv = 1.0 / rd;
	vec3 t0 = (-half_extents - ro) * inv;
	vec3 t1 = (half_extents - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float t_near = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float t_far = min(min(tmax.x, tmax.y), tmax.z);

#ifndef CLOUD_ANALYTIC_GROUND
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float scene_t = length(scene_view.xyz);
	float ground = depth > 1e-6 ? 1.0 : 0.0;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
#else
	float ground = rd.y < -1e-4 ? 1.0 : 0.0;
	float scene_t = ground > 0.0 ? (ground_y - cam.y) / rd.y : 1e6;
	vec3 scene_world = cam + rd * min(scene_t, 1e4);
#endif
	t_far = min(t_far, scene_t);
	if (t_far <= t_near) {
		discard;
	}

	float cos_theta = dot(rd, light_dir);
	float phase = mix(hg(cos_theta, phase_back_g), hg(cos_theta, phase_forward_g), 0.5);
	float phase_term = min(0.35 + 0.65 * phase, 3.0);
	float forward = pow(max(cos_theta, 0.0), 5.0);
	vec3 sun = sun_color * sun_intensity;
	float skip_margin = softness * (erosion + 0.15);
	float inv_height = 1.0 / max(top_y - base_y, 0.01);

	float t = t_near + step_length * ign(FRAGCOORD.xy);
	float trans = 1.0;
	vec3 col = vec3(0.0);
	float first_hit = -1.0;
	vec3 hit_p = vec3(0.0);
	for (int i = 0; i < max_steps; i++) {
		if (t >= t_far || trans < 0.02) {
			break;
		}
		vec3 p = ro + rd * t;
		float env = envelope(p);
		if (env > skip_margin) {
			t += max(env - skip_margin, step_length);
			continue;
		}
		float d = sample_density(p, env) * fade * smoothstep(near_fade_start, near_fade_end, t);
		if (d > 0.002) {
			if (first_hit < 0.0) {
				first_hit = t;
				hit_p = p;
			}
			float tl = exp(-light_depth(p) * light_absorption);
			float h = clamp((p.y - base_y) * inv_height, 0.0, 1.0);
			float powder = mix(1.0, 1.0 - exp(-d * 6.0), powder_strength * (1.0 - forward));
			vec3 ambient = mix(base_color, top_color, smoothstep(0.0, 1.0, h));
			float edge = 1.0 - clamp(d * 3.0, 0.0, 1.0);
			vec3 s = ambient + sun * tl * phase_term * powder + rim_color * rim_strength * forward * edge * (0.3 + 0.7 * tl);
			float a = 1.0 - exp(-d * absorption * step_length);
			col += trans * a * s;
			trans *= 1.0 - a;
		}
		t += step_length;
	}

	float alpha = 1.0 - trans;
	if (alpha < 0.004) {
		discard;
	}
	vec3 color = col / alpha;
	if (lobe_shading > 0.0) {
		float e = 0.3;
		float f0 = surface_field(hit_p);
		vec3 grad = vec3(surface_field(hit_p + vec3(e, 0.0, 0.0)), surface_field(hit_p + vec3(0.0, e, 0.0)), surface_field(hit_p + vec3(0.0, 0.0, e))) - f0;
		vec3 n = -normalize(grad + vec3(0.0, 1e-5, 0.0));
		float lambert = smoothstep(-0.35, 0.75, dot(n, light_dir));
		color = mix(color, color * lobe_shadow_tint, lobe_shading * (1.0 - lambert));
	}

	vec2 lo = content_rect.xy;
	vec2 hi = content_rect.xy + content_rect.zw;
	vec2 outside = max(lo - scene_world.xz, scene_world.xz - hi);
	float content = (1.0 - smoothstep(-content_soft * 0.5, content_soft, max(outside.x, outside.y))) * ground;
	float depth_scale = mix(1.0, mix(veil_ground_depth, veil_content_depth, content), ground);
	float veiled = 1.0 - pow(max(trans, 1e-4), depth_scale);
	veiled *= mix(1.0, veil_content_cap, content);

	// Organic window edges: the cloud's own billows push the fade boundary in and out.
	float billow = texture(noise_tex, (hit_p + noise_offset) * noise_scale * 0.7).r - 0.5;
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	float center_d = length((SCREEN_UV - 0.5) * vec2(aspect, 1.0));
	float center_r = veil_center_radius * (1.0 + billow * veil_edge_noise);
	veiled *= mix(1.0, veil_center, (1.0 - smoothstep(center_r * 0.4, center_r, center_d)) * content);
	if (player_position.y > -50.0) {
		vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(player_position, 1.0));
		if (clip.w > 0.0) {
			vec2 puv = clip.xy / clip.w * 0.5 + 0.5;
			float player_d = length((SCREEN_UV - puv) * vec2(aspect, 1.0));
			float player_t = length(player_position - cam);
			float occluding = 1.0 - smoothstep(player_t * 0.85, player_t, max(first_hit, 0.0));
			float player_r = veil_player_radius * (1.0 + billow * veil_edge_noise);
			veiled *= mix(1.0, veil_player, (1.0 - smoothstep(player_r * 0.35, player_r, player_d)) * occluding);
		}
	}

	ALBEDO = color;
	ALPHA = veiled;
}
