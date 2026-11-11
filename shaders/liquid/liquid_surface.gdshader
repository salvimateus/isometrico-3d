shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Shallow-water sheet: grid displaced by the sim, refraction + depth absorption, flow-mapped ripples, foam.
// LITE (mobile profile) drops the screen-texture refraction, caustics and the second ripple and foam octaves.

uniform sampler2D state_tex : filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D aux_tex : filter_linear, repeat_disable;
uniform sampler2D ripple_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
#ifndef LITE
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 area = vec4(-16.0, -16.0, 32.0, 32.0);
uniform vec2 texel = vec2(0.00390625);
uniform float cell = 0.125;
uniform vec3 shallow_color : source_color = vec3(0.44, 0.83, 0.85);
uniform vec3 scatter_color : source_color = vec3(0.18, 0.62, 0.72);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 absorption = vec3(1.6, 0.42, 0.30);
uniform float scatter_strength = 0.55;
uniform float refraction = 0.05;
uniform float edge_soft = 0.045;
uniform float ripple_scale = 0.55;
uniform float ripple_strength = 0.55;
uniform float flow_period = 1.4;
uniform float flow_strength = 0.35;
uniform float caustic_strength = 0.8;
uniform float foam_scale = 0.9;
uniform float day = 1.0;
uniform vec3 sky_top : source_color = vec3(0.24, 0.55, 0.9);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.9, 0.95);
uniform float reflect_strength = 1.0;
uniform float night = 0.0;
uniform vec3 moon_dir = vec3(0.47, 0.73, -0.51);
uniform vec3 moon_color : source_color = vec3(0.62, 0.71, 1.0);

varying vec3 world_pos;
varying float v_wet;

float surf_at(vec2 uv) {
	float h = textureLod(state_tex, uv, 0.0).r;
	return textureLod(height_tex, uv, 0.0).r + h;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (wp.xz - area.xy) / area.zw;
	float h0 = textureLod(state_tex, uv, 0.0).r;
	// Widened depth: the front becomes a sloped ramp over a few cells instead of a one-cell vertical wall.
	vec2 o = texel * 1.5;
	float hn = textureLod(state_tex, uv + vec2(o.x, 0.0), 0.0).r + textureLod(state_tex, uv - vec2(o.x, 0.0), 0.0).r
		+ textureLod(state_tex, uv + vec2(0.0, o.y), 0.0).r + textureLod(state_tex, uv - vec2(0.0, o.y), 0.0).r;
	float h = max(h0, 0.0) * 0.4 + hn * 0.15;
	h = min(h, h0 + 0.02);
	float b = textureLod(height_tex, uv, 0.0).r;
	float wet = smoothstep(0.0, 0.004, h);
	v_wet = wet;
	float y = b + h + 0.006 - (1.0 - wet) * 0.12;
	if (wet < 1.0) {
		// Dry vertex next to a drop (cliff, drain): stay just below the wet lip instead of stretching down.
		float lip = -1e6;
		for (int k = 0; k < 4; k++) {
			vec2 d = vec2(k == 0 ? -texel.x : (k == 1 ? texel.x : 0.0), k == 2 ? -texel.y : (k == 3 ? texel.y : 0.0));
			float hk = textureLod(state_tex, uv + d, 0.0).r;
			if (hk > 0.004) {
				lip = max(lip, textureLod(height_tex, uv + d, 0.0).r + hk);
			}
		}
		y = max(y, lip - 0.25);
	}
	VERTEX.y = y;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustics(vec2 p, float t) {
	vec2 q = p * 1.7;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		q += vec2(sin(q.y * 1.3 + t), cos(q.x * 1.1 - t * 0.8)) * 0.55;
		c += abs(sin(q.x + q.y) * cos(q.x - q.y * 0.7));
	}
	return pow(clamp(1.0 - c / 3.0, 0.0, 1.0), 6.0);
}

vec3 flow_sample(sampler2D tex, vec2 p, vec2 flow, float t) {
	float ph0 = fract(t);
	float ph1 = fract(t + 0.5);
	float w0 = 1.0 - abs(2.0 * ph0 - 1.0);
	vec3 a = texture(tex, p - flow * ph0).xyz;
	vec3 b = texture(tex, p - flow * ph1 + vec2(0.37, 0.61)).xyz;
	return mix(b, a, w0);
}

void fragment() {
	vec2 uv = (world_pos.xz - area.xy) / area.zw;
	vec4 st = texture(state_tex, uv);
	float h = st.r;
	vec2 vel = st.gb;
	float speed = length(vel);
	vec4 aux = texture(aux_tex, uv);

	float sl = surf_at(uv - vec2(texel.x, 0.0));
	float sr = surf_at(uv + vec2(texel.x, 0.0));
	float sb = surf_at(uv - vec2(0.0, texel.y));
	float stp = surf_at(uv + vec2(0.0, texel.y));
	vec2 grad = vec2(sr - sl, stp - sb) / (2.0 * cell);
	grad *= smoothstep(0.004, 0.03, h);
	float gl = length(grad);
	if (gl > 1.2) {
		grad *= 1.2 / gl;
	}

	float t = TIME / flow_period;
	vec2 flow = vel * flow_strength * flow_period * ripple_scale;
	vec2 rp = world_pos.xz * ripple_scale;
	vec3 r0 = flow_sample(ripple_tex, rp, flow, t) * 2.0 - 1.0;
#ifdef LITE
	vec3 r1 = vec3(0.0);
#else
	vec3 r1 = texture(ripple_tex, rp * 2.3 + vec2(TIME * 0.05, -TIME * 0.04)).xyz * 2.0 - 1.0;
#endif
	float rough = mix(0.25, 1.0, smoothstep(0.1, 2.0, speed)) * ripple_strength;
	vec2 ripple = (r0.xy * 0.75 + r1.xy * 0.35) * rough;
	vec3 n = normalize(vec3(-grad.x + ripple.x, 1.0, -grad.y + ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec3 scene_view = up.xyz / up.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float thick_v = max(world_pos.y - scene_world.y, 0.0);
	float path = clamp(length(scene_view - VERTEX), 0.0, 4.0);
	// Per-pixel wet mask with a noisy threshold: organic, grid-free silhouette.
	float en = texture(foam_tex, world_pos.xz * 0.45 + vec2(TIME * 0.03, 0.0)).r;
	float thr = 0.002 + 0.01 * en;
	float wet_px = smoothstep(thr, thr + 0.008, h);
	float edge = smoothstep(0.0, edge_soft, thick_v) * wet_px;

	vec2 offs = n.xz * refraction * clamp(thick_v * 4.0, 0.0, 1.0);
	vec2 ruv = SCREEN_UV + offs;
	float raw_r = texture(depth_tex, ruv).r;
	vec4 upr = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, raw_r, 1.0);
	vec3 sv_r = upr.xyz / upr.w;
	if (sv_r.z > VERTEX.z) {
		ruv = SCREEN_UV;
		sv_r = scene_view;
	}
#ifdef LITE
	// No screen copy on mobile: a lit body tint stands in for the refracted floor, and alpha shows the real one.
	vec3 refr = shallow_color * mix(0.25, 0.75, day);
#else
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
#endif
	vec3 sw_r = (INV_VIEW_MATRIX * vec4(sv_r, 1.0)).xyz;
	float shallow = 1.0 - smoothstep(0.05, 0.9, thick_v);
#ifdef LITE
	float ca = 0.0;
#else
	float ca = caustics(sw_r.xz, TIME * 1.3 + dot(vel, vec2(0.3))) * caustic_strength * day * shallow * edge;
#endif
	refr *= 1.0 + ca;

	vec3 trans = exp(-absorption * path);
	float body = 1.0 - (trans.r + trans.g + trans.b) / 3.0;
	vec3 water = refr * mix(vec3(1.0), shallow_color, 0.5) * trans + scatter_color * scatter_strength * (body + 0.1);
	vec3 vdir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 rdir = reflect(vdir, n);
	float ndv = clamp(dot(n, -vdir), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 sky = mix(sky_horizon, sky_top, smoothstep(0.0, 0.7, rdir.y));
	water = mix(water, sky, clamp(fres * reflect_strength + mix(0.06, 0.22, night), 0.0, 1.0));
	// Night: cool moon sheen (broad lobe) and glint, readable from the iso camera too.
	vec3 md = normalize(moon_dir);
	float lobe = max(dot(rdir, md), 0.0);
	float sheen = pow(lobe, 3.0) * 0.4 + pow(lobe, 60.0) * 2.5 + (0.08 + 0.25 * fres);
	water = mix(water, water * vec3(0.7, 0.85, 1.1), night * 0.6) + moon_color * sheen * night * (0.6 + 0.6 * clamp(ripple.x + ripple.y + 0.5, 0.0, 1.0));

	vec2 fp = world_pos.xz * foam_scale;
	vec2 fflow = vel * flow_strength * flow_period * foam_scale;
	float fn = flow_sample(foam_tex, fp, fflow, t + 0.25).r;
#ifdef LITE
	float fn2 = fn;
#else
	float fn2 = texture(foam_tex, fp * 2.7 - vel * TIME * 0.05).r;
#endif
	float foam_amt = clamp(aux.g, 0.0, 1.2);
	float pattern = fn * 0.65 + fn2 * 0.35;
	// Front cord: an irregular lace band just inside the wet edge, thicker where the sim made foam.
	float band_w = 0.07 + 0.12 * en + 0.12 * clamp(foam_amt, 0.0, 1.0);
	float band = smoothstep(thr, thr + 0.012, h) * (1.0 - smoothstep(band_w * 0.35, band_w, h));
	float cord = band * smoothstep(0.3, 0.52, pattern + 0.3 * foam_amt) * mix(0.55, 1.0, smoothstep(0.1, 0.6, foam_amt));
	float f = clamp(foam_amt * 0.8, 0.0, 1.2);
	float lace = smoothstep(1.0 - f * 0.55, 1.08 - f * 0.55, pattern);
	float foam = lace * smoothstep(0.18, 0.4, f) * mix(0.75, 1.0, smoothstep(0.6, 1.0, f));
	float steep = smoothstep(0.4, 1.2, gl) * smoothstep(0.02, 0.08, h);
	foam = max(foam, smoothstep(0.7 - steep * 0.25, 0.85 - steep * 0.25, pattern) * steep * 0.8);
	foam = max(foam, cord);

	ALBEDO = foam_color * foam;
	EMISSION = water * (1.0 - foam);
	ROUGHNESS = mix(0.035, 0.6, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
#ifdef LITE
	ALPHA = clamp(edge * clamp(0.4 + body * 0.55 + fres * 0.5 + foam, 0.0, 1.0), 0.0, 1.0);
#else
	ALPHA = clamp(edge * mix(0.96, 1.0, foam), 0.0, 1.0);
#endif
}
