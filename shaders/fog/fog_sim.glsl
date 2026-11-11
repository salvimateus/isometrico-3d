#[compute]
#version 450

// 2D stable-fluids ground fog on the XZ plane. One kernel, pass selected by push constant mode.
// State texel: xy = velocity (world units/s), z = density, w = divergence source.
// Lift texel: x = lift height (world units), y = vertical velocity of the lifted fog.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src_a;
layout(set = 0, binding = 1) uniform sampler2D src_b;
layout(set = 0, binding = 2) uniform sampler2D obstacle_tex;
layout(set = 0, binding = 3) uniform sampler2D base_tex;
layout(set = 0, binding = 6) uniform sampler2D reach_tex; // blurred base map: 1 near thick fog, low deep in clear areas
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 5, std430) restrict readonly buffer Splats {
	vec4 data[];
} splats;

layout(push_constant, std430) uniform Params {
	vec4 p0; // res.x, res.y, mode, splat_count
	vec4 p1; // dt, cell size, time, coord reset flags (coords pass) / night floor variation (advect pass)
	vec4 p2; // wind.xy, ambient keep, regen
	vec4 p3; // vorticity, source keep, drift strength, drift frequency (per cell)
	vec4 p4; // impulse coupling, impulse carve, impulse push, drift speed
	vec4 p5; // burst source, burst radial, burst swirl, burst carve
	vec4 p6; // ring gain, burst lift, night floor (fraction), base max
	vec4 p7; // patch amount, patch frequency (per cell), patch speed, night front
} pc;

const int MODE_ADVECT = 0;
const int MODE_CURL = 1;
const int MODE_VORTICITY = 2;
const int MODE_DIVERGENCE = 3;
const int MODE_JACOBI = 4;
const int MODE_GRADIENT = 5;
const int MODE_COORDS = 6;
const int MODE_COPY = 7;
const int MODE_INIT = 8;
const int MODE_LIFT = 9;

ivec2 g_res;

vec4 fetch_a(ivec2 c) {
	return texelFetch(src_a, clamp(c, ivec2(0), g_res - 1), 0);
}

vec4 fetch_b(ivec2 c) {
	return texelFetch(src_b, clamp(c, ivec2(0), g_res - 1), 0);
}

bool solid(ivec2 c) {
	if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, g_res))) {
		return false;
	}
	return texelFetch(obstacle_tex, c, 0).r > 0.5;
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(hash22(i), f);
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float drift_potential(vec2 p, float t) {
	return gnoise(p + vec2(t * 0.7, t * 0.4)) + 0.45 * gnoise(p * 2.13 - vec2(t * 0.5, -t * 0.9) + 17.3);
}

// Base map is a density fraction (no global floor). Sparse drifting patches add low wisps that
// come and go where the map is thin, so calm areas stay mostly clear.
float base_density(vec2 uv, vec2 cell_pos, float t) {
	float m = clamp(texture(base_tex, uv).r, 0.0, 1.0);
	// Night floor spreads from thick areas inward as the front (1 -> below 0) sweeps over the reach map.
	float reach = texture(reach_tex, uv).r;
	float front = pc.p7.w;
	float n = gnoise(cell_pos * pc.p7.y + vec2(t, -0.6 * t) * pc.p7.z) + 0.5 * gnoise(cell_pos * pc.p7.y * 2.3 - vec2(0.7 * t, t) * pc.p7.z + 31.7);
	// Night floor is not uniform: drifting thick lows and thinner rises keep it reading as rolling fog.
	float swell = mix(1.0 - pc.p1.w, 1.15, clamp(0.5 + n * 1.3, 0.0, 1.0));
	m = max(m, pc.p6.z * swell * smoothstep(front - 0.12, front + 0.04, reach));
	float patches = smoothstep(0.18, 0.5, n);
	return pc.p6.w * (m + pc.p7.x * patches * (1.0 - m));
}

void advect(ivec2 c, vec2 uv) {
	float dt = pc.p1.x;
	float h = pc.p1.y;
	vec2 res = vec2(g_res);
	vec4 here = texelFetch(src_a, c, 0);
	vec2 back = uv - dt * here.xy / (h * res);
	vec4 s = texture(src_a, back);
	vec2 vel = s.xy;
	float dens = s.z;
	float source = here.w * pc.p3.y;

	// Ambient: wind plus slow divergence-free eddies from a curl-noise potential.
	float t = pc.p1.z * pc.p4.w;
	vec2 q = vec2(c) * pc.p3.w;
	float e = 0.05;
	float dpx = drift_potential(q + vec2(e, 0.0), t) - drift_potential(q - vec2(e, 0.0), t);
	float dpz = drift_potential(q + vec2(0.0, e), t) - drift_potential(q - vec2(0.0, e), t);
	vec2 drift = vec2(dpz, -dpx) / (2.0 * e) * pc.p3.z;
	vec2 ambient = pc.p2.xy + drift;
	vel = mix(ambient, vel, pc.p2.z);

	float base = base_density(uv, vec2(c), pc.p1.z);
	dens += (base - dens) * pc.p2.w;

	int count = int(pc.p0.w);
	vec2 pos = vec2(c) + 0.5;
	for (int k = 0; k < count; k++) {
		vec4 a = splats.data[k * 2];
		vec4 b = splats.data[k * 2 + 1];
		vec2 d = pos - a.xy;
		float r = max(a.z, 0.5);
		float d2 = dot(d, d) / (r * r);
		if (d2 > 9.0) {
			continue;
		}
		float strength = b.z;
		if (a.w < 0.5) {
			// Moving body: drags the fog toward its velocity, pushes a bow ahead, thins its core.
			float w = exp(-d2 * 1.6);
			vec2 bv = b.xy;
			vel = mix(vel, bv * (1.0 + pc.p4.z), clamp(w * pc.p4.x * strength, 0.0, 1.0));
			dens *= 1.0 - clamp(w * pc.p4.y * strength, 0.0, 0.9);
		} else {
			// Radial burst: divergence source, outward kick, swirl, density pushed from center to rim.
			float rr = sqrt(d2);
			vec2 dir = rr > 1e-4 ? d / (rr * r) : vec2(0.0);
			float core = exp(-d2 * 2.0);
			float rim = exp(-pow(rr - 1.25, 2.0) * 5.0);
			float ang = atan(d.y, d.x);
			float swirl_noise = sin(ang * 5.0 + b.w * 6.28) * 0.6 + sin(ang * 9.0 - b.w * 11.0) * 0.4;
			source += pc.p5.x * strength * core;
			vel += dir * (pc.p5.y * strength * exp(-pow(rr - 0.8, 2.0) * 2.0));
			vel += vec2(-dir.y, dir.x) * (pc.p5.z * strength * swirl_noise * rim);
			if (strength > 0.0) {
				float carved = dens * clamp(pc.p5.w * strength * core, 0.0, 0.95);
				dens -= carved;
				dens += rim * strength * (pc.p6.x * base + pc.p6.y);
			}
		}
	}

	if (solid(c)) {
		vel = vec2(0.0);
		dens = base;
	}
	imageStore(dst, c, vec4(vel, max(dens, 0.0), source));
}

// Ballistic lift: interaction throws fog up, horizontal flow carries it, soft gravity settles it.
// Params in this mode: p2 = (gravity, drag keep, decay keep, max height), p3 = (impulse lift, run speed ref, burst lift, burst core ratio).
void lift_step(ivec2 c, vec2 uv) {
	float dt = pc.p1.x;
	float h = pc.p1.y;
	vec2 vel = texelFetch(src_b, c, 0).xy;
	vec2 back = uv - dt * vel / (h * vec2(g_res));
	vec2 lw = texture(src_a, back).xy;
	int count = int(pc.p0.w);
	vec2 pos = vec2(c) + 0.5;
	for (int k = 0; k < count; k++) {
		vec4 a = splats.data[k * 2];
		vec4 b = splats.data[k * 2 + 1];
		vec2 d = pos - a.xy;
		float r = max(a.z, 0.5);
		float d2 = dot(d, d) / (r * r);
		if (d2 > 9.0) {
			continue;
		}
		if (a.w < 0.5) {
			// Plume rises behind the body, never through it.
			float speed = length(b.xy);
			float run = clamp(speed / pc.p3.y, 0.0, 1.0);
			vec2 behind = a.xy - (speed > 1e-3 ? b.xy / speed : vec2(0.0)) * r * 1.4;
			vec2 db = pos - behind;
			float body_clear = smoothstep(0.7, 1.3, sqrt(d2));
			float target_w = pc.p3.x * run * run * exp(-dot(db, db) / (r * r) * 1.2) * body_clear;
			lw.y = max(lw.y, target_w);
		} else if (b.z > 0.0) {
			float rr = sqrt(d2);
			float rim = exp(-pow(rr - 1.2, 2.0) * 3.0);
			float core = exp(-d2 * 2.0);
			lw.y += pc.p3.z * sqrt(b.z) * (rim + pc.p3.w * core);
		}
	}
	lw.y = lw.y * pc.p2.y - pc.p2.x * dt;
	lw.x += lw.y * dt;
	if (lw.x <= 0.0) {
		lw = vec2(0.0);
	} else if (lw.y < 0.0) {
		// Cushion: falling fog slows down as it nears the floor, so it settles without a cut.
		lw.y *= mix(0.93, 1.0, smoothstep(0.0, 0.3, lw.x));
	}
	lw.x = min(lw.x * pc.p2.z, pc.p2.w);
	if (solid(c)) {
		lw = vec2(0.0);
	}
	imageStore(dst, c, vec4(lw, 0.0, 0.0));
}

void main() {
	g_res = ivec2(pc.p0.xy);
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= g_res.x || c.y >= g_res.y) {
		return;
	}
	vec2 uv = (vec2(c) + 0.5) / vec2(g_res);
	int mode = int(pc.p0.z);
	float h = pc.p1.y;

	if (mode == MODE_ADVECT) {
		advect(c, uv);
	} else if (mode == MODE_CURL) {
		float w = (fetch_a(c + ivec2(1, 0)).y - fetch_a(c - ivec2(1, 0)).y) - (fetch_a(c + ivec2(0, 1)).x - fetch_a(c - ivec2(0, 1)).x);
		imageStore(dst, c, vec4(w / (2.0 * h), 0.0, 0.0, 0.0));
	} else if (mode == MODE_VORTICITY) {
		vec4 s = texelFetch(src_a, c, 0);
		float w = texelFetch(src_b, c, 0).x;
		vec2 grad = vec2(abs(fetch_b(c + ivec2(1, 0)).x) - abs(fetch_b(c - ivec2(1, 0)).x), abs(fetch_b(c + ivec2(0, 1)).x) - abs(fetch_b(c - ivec2(0, 1)).x));
		float len = length(grad);
		if (len > 1e-5) {
			vec2 n = grad / len;
			s.xy += pc.p3.x * h * vec2(n.y, -n.x) * w * pc.p1.x;
		}
		if (solid(c)) {
			s.xy = vec2(0.0);
		}
		imageStore(dst, c, s);
	} else if (mode == MODE_DIVERGENCE) {
		vec2 vl = solid(c - ivec2(1, 0)) ? vec2(0.0) : fetch_a(c - ivec2(1, 0)).xy;
		vec2 vr = solid(c + ivec2(1, 0)) ? vec2(0.0) : fetch_a(c + ivec2(1, 0)).xy;
		vec2 vb = solid(c - ivec2(0, 1)) ? vec2(0.0) : fetch_a(c - ivec2(0, 1)).xy;
		vec2 vt = solid(c + ivec2(0, 1)) ? vec2(0.0) : fetch_a(c + ivec2(0, 1)).xy;
		vec4 s = texelFetch(src_a, c, 0);
		float div = (vr.x - vl.x + vt.y - vb.y) / (2.0 * h) - s.w;
		imageStore(dst, c, vec4(div, 0.0, 0.0, 0.0));
	} else if (mode == MODE_JACOBI) {
		float pc0 = texelFetch(src_a, c, 0).x;
		float sum = 0.0;
		ivec2 offs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
		for (int i = 0; i < 4; i++) {
			ivec2 n = c + offs[i];
			if (any(lessThan(n, ivec2(0))) || any(greaterThanEqual(n, g_res))) {
				sum += 0.0; // open border
			} else if (solid(n)) {
				sum += pc0;
			} else {
				sum += texelFetch(src_a, n, 0).x;
			}
		}
		float div = texelFetch(src_b, c, 0).x;
		float p = (sum - h * h * div) * 0.25;
		imageStore(dst, c, vec4(solid(c) ? 0.0 : p, 0.0, 0.0, 0.0));
	} else if (mode == MODE_GRADIENT) {
		vec4 s = texelFetch(src_a, c, 0);
		if (solid(c)) {
			s.xy = vec2(0.0);
		} else {
			float p0 = texelFetch(src_b, c, 0).x;
			float pl = solid(c - ivec2(1, 0)) ? p0 : (c.x == 0 ? 0.0 : fetch_b(c - ivec2(1, 0)).x);
			float pr = solid(c + ivec2(1, 0)) ? p0 : (c.x == g_res.x - 1 ? 0.0 : fetch_b(c + ivec2(1, 0)).x);
			float pb = solid(c - ivec2(0, 1)) ? p0 : (c.y == 0 ? 0.0 : fetch_b(c - ivec2(0, 1)).x);
			float pt = solid(c + ivec2(0, 1)) ? p0 : (c.y == g_res.y - 1 ? 0.0 : fetch_b(c + ivec2(0, 1)).x);
			s.xy -= vec2(pr - pl, pt - pb) / (2.0 * h);
			// No flow into walls.
			if (solid(c - ivec2(1, 0))) s.x = max(s.x, 0.0);
			if (solid(c + ivec2(1, 0))) s.x = min(s.x, 0.0);
			if (solid(c - ivec2(0, 1))) s.y = max(s.y, 0.0);
			if (solid(c + ivec2(0, 1))) s.y = min(s.y, 0.0);
		}
		imageStore(dst, c, s);
	} else if (mode == MODE_COORDS) {
		// Two-phase displacement of noise coordinates (world units), each phase reset on its wrap.
		float dt = pc.p1.x;
		vec2 vel = texelFetch(src_b, c, 0).xy;
		vec2 back = uv - dt * vel / (h * vec2(g_res));
		vec4 disp = texture(src_a, back) - vec4(vel, vel) * dt;
		int flags = int(pc.p1.w);
		if ((flags & 1) != 0) disp.xy = vec2(0.0);
		if ((flags & 2) != 0) disp.zw = vec2(0.0);
		imageStore(dst, c, clamp(disp, vec4(-60.0), vec4(60.0)));
	} else if (mode == MODE_COPY) {
		imageStore(dst, c, texelFetch(src_a, c, 0));
	} else if (mode == MODE_LIFT) {
		lift_step(c, uv);
	} else if (mode == MODE_INIT) {
		imageStore(dst, c, vec4(pc.p2.xy, base_density(uv, vec2(c), 0.0), 0.0));
	}
}
