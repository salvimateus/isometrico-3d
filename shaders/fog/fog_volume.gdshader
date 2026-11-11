shader_type spatial;
// Raymarched ground-fog slab. Drawn on the box back faces without depth test, so it works with the
// camera outside, grazing or inside the fog; the ray stops at opaque scene depth.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

#ifndef FOG_NO_DEPTH
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif
uniform sampler2D state_tex : filter_linear, repeat_disable;
uniform sampler2D coords_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D obstacle_tex : filter_linear, repeat_disable;
uniform sampler2D lift_tex : filter_linear, repeat_disable;
uniform float lift_density = 0.5;
uniform float lift_floor_gap = 0.3;
uniform float lift_spread = 0.75;

uniform vec2 area_origin;
uniform vec2 area_size;
uniform float box_height = 1.9;
uniform float fog_height = 0.9;
uniform float top_min = 0.3;
uniform float top_softness = 0.55;
uniform float extinction = 2.6;
uniform float edge_fade = 2.2;
uniform float wisp_scale = 0.9;
uniform float wisp_strength = 0.85;
uniform float top_noise_scale = 0.33;
uniform float top_noise_strength = 0.45;
uniform float flow_period = 2.4;
uniform float flow_time = 0.0;
uniform int steps_min = 14;
uniform int steps_max = 40;
uniform float step_length = 0.12;
uniform float max_distance = 60.0;
uniform float clear_near = 0.15;
uniform float clear_far = 1.1;
uniform vec2 grazing_dir_y = vec2(0.12, 0.42);
uniform vec2 grazing_fade = vec2(3.0, 26.0);
uniform float grazing_far_density = 0.28;
uniform float grazing_max_alpha = 0.8;

uniform vec3 sun_dir = vec3(-0.6, 0.74, 0.27);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float sun_scatter = 1.05;
uniform vec3 top_color : source_color = vec3(1.0, 0.96, 0.92);
uniform vec3 shadow_color : source_color = vec3(0.66, 0.76, 0.87);
uniform float ambient = 0.62;
uniform float self_shadow = 0.9;
uniform float forward_scatter = 0.35;
uniform float density_scale = 1.0;
uniform float density_contrast = 1.35;
uniform float light_probe = 0.45;
uniform float obstacle_shadow_height = 2.6;
uniform float obstacle_shadow = 0.8;
uniform float night = 0.0;
uniform bool high_lighting = true;
uniform float billow_shading = 0.45;
uniform int light_count = 0;
uniform vec4 light_pos[8]; // xyz, range
uniform vec4 light_col[8]; // rgb * energy
uniform float light_fog_gain = 0.6;
uniform float fade = 1.0;
uniform bool debug_view = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 slab(vec3 ro, vec3 rd) {
	vec3 bmin = vec3(area_origin.x, 0.0, area_origin.y);
	vec3 bmax = vec3(area_origin.x + area_size.x, box_height, area_origin.y + area_size.y);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (bmin - ro) * inv;
	vec3 t1 = (bmax - ro) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	return vec2(max(max(tn.x, tn.y), tn.z), min(min(tf.x, tf.y), tf.z));
}

float flow_noise(vec4 disp, vec2 xz, float scale, vec2 offset, float wa) {
	float na = texture(noise_tex, (xz + disp.xy) * scale + offset).r;
	float nb = texture(noise_tex, (xz + disp.zw) * scale + offset + vec2(0.37, 0.61)).r;
	float n = mix(nb, na, wa) - 0.5;
	// Keep contrast when the two phases blend.
	return n / sqrt(wa * wa + (1.0 - wa) * (1.0 - wa)) + 0.5;
}

// Fog density at p; also returns the local top height and the raw 2D sim density.
float fog_density(vec3 p, float wa, out float top, out float d, out float tn) {
	vec2 uv = (p.xz - area_origin) / area_size;
	d = texture(state_tex, uv).z * density_scale;
	float lift = texture(lift_tex, uv).x;
	d += lift * lift_density;
	top = 0.0;
	tn = 0.5;
	if (d < 0.002) {
		return 0.0;
	}
	vec4 disp = texture(coords_tex, uv);
	tn = flow_noise(disp, p.xz, top_noise_scale, vec2(0.0), wa);
	// Saturating: piled-up fog bulges instead of spiking.
	top = fog_height * (top_min + (1.0 - top_min) * 1.3 * (1.0 - exp(-1.2 * d))) * (1.0 + top_noise_strength * (tn - 0.5) * 2.0);
	// Lifted fog: the column rises (height = base + lift), wisps keep riding the flow map.
	float top0 = top;
	top += lift * (0.75 + 0.5 * tn);
	if (p.y > top) {
		return 0.0;
	}
	float wn = flow_noise(disp, p.xz, wisp_scale, vec2(p.y * 0.45, -p.y * 0.3), wa);
	float hf = 1.0 - smoothstep(top * (1.0 - top_softness), top, p.y);
	// A rolling plume thins out near the floor beneath it.
	hf *= mix(1.0, 0.45 + 0.55 * smoothstep(0.0, lift * lift_floor_gap + 1e-3, p.y), smoothstep(0.1, 0.5, lift));
	vec2 edge = min(p.xz - area_origin, area_origin + area_size - p.xz);
	float ef = smoothstep(0.0, edge_fade, min(edge.x, edge.y));
	float wisp = mix(1.0, clamp((wn - 0.5) * 2.6 + 1.0, 0.0, 2.2), wisp_strength);
	float body = pow(clamp(d, 0.0, 3.0), density_contrast);
	// Lifting spreads the same fog over a taller column, so plumes read as wisps, not walls.
	body *= mix(1.0, top0 / max(top, 1e-3), lift_spread);
	return body * hf * wisp * ef;
}

// Shadow of tall obstacles (buildings, trunks) cast through the fog along the light.
float obstacle_light(vec3 p, vec3 L) {
	float reach = max(obstacle_shadow_height - p.y, 0.0) / max(L.y, 0.12);
	// Averaged taps give soft shaft edges instead of hard shadow walls.
	float occ = 0.0;
	for (int k = 0; k < 6; k++) {
		vec2 q = p.xz + L.xz * reach * ((float(k) + 0.5) / 6.0);
		occ += texture(obstacle_tex, (q - area_origin) / area_size).r;
	}
	return 1.0 - obstacle_shadow * smoothstep(0.0, 0.6, occ / 6.0 * 2.5);
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(world_pos - ro);
#ifdef FOG_NO_DEPTH
	// Cheap tier: no depth read (it forces a depth resolve / tile flush); the ray ends on the ground plane.
	float t_scene = rd.y < -1e-4 ? ro.y / -rd.y : 1e6;
#else
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float t_scene = length(view.xyz);
#endif

	vec2 hit = slab(ro, rd);
	float t0 = max(hit.x, 0.0);
	float t1 = min(min(hit.y, t_scene), t0 + max_distance);
	if (t1 <= t0) {
		discard;
	}

	float phase = fract(flow_time / flow_period);
	float wa = 1.0 - abs(2.0 * phase - 1.0);

	if (debug_view) {
		// Density and velocity on the first surface the ray reaches (ground or fog floor).
		vec3 p = ro + rd * t1;
		vec4 st = texture(state_tex, (p.xz - area_origin) / area_size);
		vec2 v = st.xy;
		float speed = length(v);
		vec3 hue = 0.5 + 0.5 * vec3(v.x, v.y, -v.x) / max(speed, 1e-4);
		vec3 col = vec3(st.z * 0.55) + hue * clamp(speed * 0.6, 0.0, 1.0) * 0.8 + vec3(0.0, 0.0, st.w * 0.05);
		ALBEDO = col;
		ALPHA = 0.88;
	} else {
		float span = t1 - t0;
		int steps = clamp(int(span / step_length), steps_min, steps_max);
		float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		// A setting sun / rising moon below the horizon would black out the fog: keep the key light above it.
		vec3 L = normalize(vec3(sun_dir.x, max(sun_dir.y, 0.3), sun_dir.z));
		float mu = dot(rd, L);
		float phase_fn = 1.0 + forward_scatter * max(mu, 0.0) * max(mu, 0.0);
		float sun_path = 1.0 / max(L.y, 0.2);
		float grazing = 1.0 - smoothstep(grazing_dir_y.x, grazing_dir_y.y, abs(rd.y));

		float trans = 1.0;
		vec3 acc = vec3(0.0);
		float prev_t = t0;
		for (int i = 0; i < steps; i++) {
			// Steps bunch up near the camera, where detail is visible in grazing views.
			float s = (float(i) + jitter) / float(steps);
			float t = t0 + span * (0.45 * s * s + 0.55 * s);
			float dt = t - prev_t;
			prev_t = t;
			vec3 p = ro + rd * t;
			float top;
			float d;
			float far_thin = mix(1.0, grazing_far_density, grazing * smoothstep(grazing_fade.x, grazing_fade.y, t));
			float tn;
			float dens = fog_density(p, wa, top, d, tn) * smoothstep(clear_near, clear_far, t) * far_thin;
			if (dens <= 0.0) {
				continue;
			}
			// Light: one probe toward the light for clump self-shadowing, plus depth below the local top.
			float optical = min(d, 2.0) * max(top - p.y, 0.0) * sun_path * 0.5;
			float shafts = 1.0;
			if (high_lighting) {
				float top_l;
				float d_l;
				float tn_l;
				optical += fog_density(p + L * light_probe, wa, top_l, d_l, tn_l) * light_probe;
				shafts = obstacle_light(p, L);
			} else {
				// Cheap stand-in for the probe: deeper below the local top reads darker.
				optical *= 1.6;
			}
			float sun_t = exp(-extinction * optical * self_shadow) * shafts;
			float hgrad = smoothstep(0.0, top, p.y);
			// Billows: higher swells of the top catch more light, troughs sit in shade.
			float billow = mix(1.0 - billow_shading, 1.0 + billow_shading, tn);
			vec3 amb = mix(shadow_color, top_color, hgrad * billow) * ambient;
			vec3 col = amb + sun_color * sun_scatter * sun_t * phase_fn * billow * (0.4 + 0.6 * hgrad);
			for (int k = 0; k < light_count; k++) {
				vec3 dv = light_pos[k].xyz - p;
				float f = max(1.0 - dot(dv, dv) / (light_pos[k].w * light_pos[k].w), 0.0);
				col += light_col[k].rgb * (f * f * light_fog_gain);
			}
			float a = 1.0 - exp(-extinction * dens * dt);
			acc += trans * a * col;
			trans *= 1.0 - a;
			if (trans < 0.01) {
				break;
			}
		}
		float alpha = 1.0 - trans;
		float alpha_cap = mix(1.0, grazing_max_alpha, grazing);
		if (alpha > alpha_cap) {
			acc *= alpha_cap / alpha;
			alpha = alpha_cap;
		}
		if (alpha < 0.002) {
			discard;
		}
		ALBEDO = acc / alpha;
		ALPHA = alpha * fade;
	}
}
