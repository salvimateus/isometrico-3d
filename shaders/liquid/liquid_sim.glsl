#[compute]
#version 450

// Shallow water on a heightfield, virtual-pipe model with hydrostatic face depth (robust wet/dry fronts).
// state: x = depth, yz = velocity (world XZ), w = rise rate (or drained volume rate on drain cells).
// flux:  outflow volume rate through the faces -X, +X, -Z, +Z.
// aux:   x = wetness, y = foam, z = wall impact, w = turbulence.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D height_tex;
layout(set = 0, binding = 1) uniform sampler2D solid_tex;
layout(set = 0, binding = 2) uniform sampler2D drain_tex;
layout(rgba32f, set = 0, binding = 3) uniform restrict image2D state_img;
layout(rgba32f, set = 0, binding = 4) uniform restrict image2D flux_img;
layout(set = 0, binding = 5) uniform sampler2D aux_src;
layout(rgba16f, set = 0, binding = 6) uniform restrict writeonly image2D aux_dst;
layout(rgba32f, set = 0, binding = 7) uniform restrict writeonly image2D readback_img;
layout(set = 0, binding = 8, std430) restrict readonly buffer Emitters {
	vec4 data[];
} emitters;

layout(push_constant, std430) uniform Params {
	vec4 p0; // res.x, res.y, mode, cell
	vec4 p1; // dt, gravity, wall drag, source count (disturbances follow the sources in the buffer)
	vec4 p2; // disturbance count, linear drag, bed drag, max speed
	vec4 p3; // absorb film, absorb flat, basin decay rate, film depth
	vec4 p4; // wet rise, dry rate, foam decay, wet depth
	vec4 p5; // foam speed lo, foam speed hi, foam from speed, foam from front
	vec4 p6; // foam from converge, foam from wall, foam from drain, drain drop
	vec4 p7; // area origin x, area origin z, readback div, disturb gain
} pc;

const int MODE_FLUX = 0;
const int MODE_DEPTH = 1;
const int MODE_FX = 2;
const int MODE_COPY = 3;
const int MODE_REDUCE = 4;
const int MODE_CLEAR = 5;

ivec2 g_res;
float g_cell;

bool inside(ivec2 c) {
	return all(greaterThanEqual(c, ivec2(0))) && all(lessThan(c, g_res));
}

float terrain(ivec2 c) {
	return texelFetch(height_tex, clamp(c, ivec2(0), g_res - 1), 0).r;
}

bool solid(ivec2 c) {
	return !inside(c) || texelFetch(solid_tex, c, 0).r > 0.5;
}

// drain_tex: >= 0.9 drain; below that, the basin factor scaled by 1/0.8 (puddle-holding depressions).
bool drain(ivec2 c) {
	return inside(c) && texelFetch(drain_tex, c, 0).r > 0.9;
}

float basin(ivec2 c) {
	return clamp(texelFetch(drain_tex, c, 0).r / 0.8, 0.0, 1.0);
}

vec4 state(ivec2 c) {
	return inside(c) ? imageLoad(state_img, c) : vec4(0.0);
}

vec4 flux(ivec2 c) {
	return inside(c) ? imageLoad(flux_img, c) : vec4(0.0);
}

vec2 world_xz(ivec2 c) {
	return pc.p7.xy + (vec2(c) + 0.5) * g_cell;
}

const ivec2 DIRS[4] = ivec2[4](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));

// Momentum pushed into the faces by jets and wading bodies (volume rate, conserved by the pipes).
vec4 pushes(ivec2 c, float h) {
	vec4 add = vec4(0.0);
	vec2 p = world_xz(c);
	int count = int(pc.p1.w);
	for (int i = 0; i < count; i++) {
		vec4 a = emitters.data[i * 2];
		vec4 b = emitters.data[i * 2 + 1];
		float d = length(p - a.xy) / max(a.z, 1e-3);
		if (d < 1.6) {
			float w = exp(-d * d * 1.4);
			vec2 v = b.xy * b.z * w;
			add += vec4(max(-v.x, 0.0), max(v.x, 0.0), max(-v.y, 0.0), max(v.y, 0.0));
		}
	}
	int dcount = int(pc.p2.x);
	for (int i = 0; i < dcount; i++) {
		vec4 a = emitters.data[(count + i) * 2];
		vec4 b = emitters.data[(count + i) * 2 + 1];
		float d = length(p - a.xy) / max(a.z, 1e-3);
		if (d < 1.0) {
			float w = 1.0 - d * d;
			w *= w;
			// Bow wave ahead, trough behind: push along the motion and a little outward.
			vec2 radial = (p - a.xy) / max(length(p - a.xy), 1e-3);
			vec2 v = (b.xy + radial * length(b.xy) * 0.6) * w * pc.p7.w;
			add += vec4(max(-v.x, 0.0), max(v.x, 0.0), max(-v.y, 0.0), max(v.y, 0.0));
		}
	}
	// Relaxes face flux toward the pushed velocity over ~1/6 s.
	return add * h * g_cell * pc.p1.x * 6.0;
}

void pass_flux(ivec2 c) {
	if (solid(c) || drain(c)) {
		imageStore(flux_img, c, vec4(0.0));
		return;
	}
	float dt = pc.p1.x;
	float g = pc.p1.y;
	float b = terrain(c);
	float h = state(c).x;
	float surf = b + h;
	vec4 f_old = imageLoad(flux_img, c);
	vec4 f = vec4(0.0);
	if (h > 0.0) {
		vec4 push = pushes(c, h);
		// Flow running into a wall loses its momentum to spray instead of climbing it.
		float near_wall = 0.0;
		for (int k = 0; k < 4; k++) {
			near_wall += solid(c + DIRS[k] * 2) || solid(c + DIRS[k]) ? 1.0 : 0.0;
		}
		float wall_keep = exp(-dt * pc.p1.z * min(near_wall, 1.0));
		for (int k = 0; k < 4; k++) {
			ivec2 n = c + DIRS[k];
			if (solid(n)) {
				continue;
			}
			float bn = terrain(n);
			float surf_n;
			float h_face;
			if (drain(n)) {
				surf_n = min(b, bn) - pc.p6.w;
				h_face = h;
			} else {
				surf_n = bn + state(n).x;
				float b_face = max(b, bn);
				h_face = max(0.0, max(surf, surf_n) - b_face);
				if (surf <= bn) {
					// The water is below the neighbour's ground: it cannot climb the step.
					continue;
				}
			}
			float drag = exp(-dt * (pc.p2.y + pc.p2.z / max(h_face, 0.006)));
			float fk = f_old[k] * drag * wall_keep + dt * g * h_face * (surf - surf_n) + push[k];
			f[k] = max(fk, 0.0);
		}
		float total = f.x + f.y + f.z + f.w;
		float avail = h * g_cell * g_cell;
		if (total * dt > avail) {
			f *= avail / (total * dt);
		}
	}
	imageStore(flux_img, c, f);
}

void pass_depth(ivec2 c) {
	if (solid(c)) {
		imageStore(state_img, c, vec4(0.0));
		return;
	}
	float dt = pc.p1.x;
	vec4 s = imageLoad(state_img, c);
	vec4 f = imageLoad(flux_img, c);
	vec4 fl = flux(c + DIRS[0]);
	vec4 fr = flux(c + DIRS[1]);
	vec4 fb = flux(c + DIRS[2]);
	vec4 ft = flux(c + DIRS[3]);
	float inflow = fl.y + fr.x + fb.w + ft.z;
	float outflow = f.x + f.y + f.z + f.w;
	float area = g_cell * g_cell;
	float h_old = s.x;
	float h = max(0.0, h_old + dt * (inflow - outflow) / area);

	vec2 p = world_xz(c);
	int count = int(pc.p1.w);
	for (int i = 0; i < count; i++) {
		vec4 a = emitters.data[i * 2];
		float r = max(a.z, g_cell);
		float d = length(p - a.xy) / r;
		if (d < 1.0) {
			float w = 1.0 - d * d;
			w *= w;
			h += dt * a.w * w / (3.14159265 * r * r / 3.0);
		}
	}

	if (drain(c)) {
		float rate = h * area / max(dt, 1e-5);
		imageStore(state_img, c, vec4(0.0, 0.0, 0.0, rate));
		return;
	}

	// Thin sheets soak in fast, flat flooding drains steadily, water held in depressions lingers as puddles.
	// Puddles decay exponentially (p3.z = 1/s) with a tiny floor, so they stay a while and fade slowly.
	float absorb = mix(mix(pc.p3.x, pc.p3.y, smoothstep(0.0, pc.p3.w, h)), h * pc.p3.z + 0.0002, basin(c));
	h = max(0.0, h - absorb * dt);

	float hm = max(0.5 * (h_old + h), 1e-4);
	float qx = 0.5 * ((fl.y - f.x) + (f.y - fr.x));
	float qz = 0.5 * ((fb.w - f.z) + (f.w - ft.z));
	vec2 v = vec2(qx, qz) / (g_cell * hm);
	v *= smoothstep(0.0005, 0.004, hm);
	float sp = length(v);
	if (sp > pc.p2.w) {
		v *= pc.p2.w / sp;
	}
	float rise = max(0.0, h - h_old) / max(dt, 1e-5);
	imageStore(state_img, c, vec4(h, v, mix(s.w, rise, 0.25)));
}

void pass_fx(ivec2 c) {
	float dt = pc.p1.x;
	vec2 uv = (vec2(c) + 0.5) / vec2(g_res);
	vec4 s = state(c);
	float h = s.x;
	vec2 v = s.yz;
	vec4 own = texelFetch(aux_src, c, 0);
	vec4 adv = textureLod(aux_src, uv - v * dt / (g_cell * vec2(g_res)), 0.0);

	float wet = own.x;
	if (h > pc.p4.w) {
		wet = min(1.0, wet + pc.p4.x * dt * smoothstep(pc.p4.w, pc.p4.w * 4.0, h));
	} else {
		wet = max(0.0, wet - pc.p4.y * dt);
	}

	float foam = adv.y * exp(-pc.p4.z * dt);
	float wall = 0.0;
	float turb = 0.0;
	if (h > 0.0005 && !solid(c)) {
		vec2 vl = state(c + DIRS[0]).yz;
		vec2 vr = state(c + DIRS[1]).yz;
		vec2 vb = state(c + DIRS[2]).yz;
		vec2 vt = state(c + DIRS[3]).yz;
		float div = (vr.x - vl.x + vt.y - vb.y) / (2.0 * g_cell);
		float curl = (vr.y - vl.y - (vt.x - vb.x)) / (2.0 * g_cell);
		float speed = length(v);
		for (int k = 0; k < 4; k++) {
			ivec2 n = c + DIRS[k];
			if (inside(n) && solid(n)) {
				wall = max(wall, dot(v, vec2(DIRS[k])));
			}
			if (drain(n)) {
				foam += dt * pc.p6.z * smoothstep(0.2, 1.5, speed);
			}
		}
		wall = max(wall, 0.0);
		turb = abs(curl) * 0.08 + max(-div, 0.0) * 0.1;
		float gen = pc.p5.z * smoothstep(pc.p5.x, pc.p5.y, speed);
		gen += pc.p5.w * smoothstep(0.25, 1.4, s.w);
		gen += pc.p6.x * smoothstep(0.5, 4.0, max(-div, 0.0)) * smoothstep(0.3, 1.2, speed);
		gen += pc.p6.y * smoothstep(0.3, 2.0, wall);
		vec2 p = world_xz(c);
		int count = int(pc.p1.w);
		for (int i = 0; i < count; i++) {
			vec4 e = emitters.data[i * 2];
			float d = length(p - e.xy) / max(e.z * 1.7, 1e-3);
			gen += 6.0 * max(1.0 - d * d, 0.0) * smoothstep(0.0, 4.0, e.w);
		}
		foam += gen * dt;
		foam *= smoothstep(0.0, 0.006, h);
	} else {
		foam *= exp(-6.0 * dt);
	}
	imageStore(aux_dst, c, vec4(wet, clamp(foam, 0.0, 1.5), wall * min(h * 6.0, 1.0), turb));
}

// Readback layout: [0, rres.x) holds per-block (mean depth, mean velocity, max depth) at `div`;
// then pairs of texels per coarse event block at 2 * div: (wall, drained, surface y, foam) and
// (sum depth, sum depth * speed, max depth, max speed).
void pass_reduce(ivec2 c) {
	int div = int(pc.p7.z);
	ivec2 rres = g_res / div;
	ivec2 eres = rres / 2;
	if (c.y >= rres.y || c.x >= rres.x + eres.x * 2) {
		return;
	}
	if (c.x < rres.x) {
		ivec2 base = c * div;
		float sum_h = 0.0;
		vec2 sum_q = vec2(0.0);
		float max_h = 0.0;
		for (int y = 0; y < div; y++) {
			for (int x = 0; x < div; x++) {
				vec4 s = imageLoad(state_img, base + ivec2(x, y));
				sum_h += s.x;
				sum_q += s.yz * s.x;
				max_h = max(max_h, s.x);
			}
		}
		vec2 v = sum_h > 1e-6 ? sum_q / sum_h : vec2(0.0);
		imageStore(readback_img, c, vec4(sum_h / float(div * div), v, max_h));
		return;
	}
	if (c.y >= eres.y) {
		return;
	}
	int e = c.x - rres.x;
	int part = e % 2;
	int ediv = div * 2;
	ivec2 base = ivec2(e / 2, c.y) * ediv;
	float wall = 0.0;
	float drained = 0.0;
	float surf_sum = 0.0;
	float surf_w = 0.0;
	float foam = 0.0;
	float sum_h = 0.0;
	float sum_e = 0.0;
	float max_h = 0.0;
	float max_v = 0.0;
	for (int y = 0; y < ediv; y++) {
		for (int x = 0; x < ediv; x++) {
			ivec2 q = base + ivec2(x, y);
			vec4 s = imageLoad(state_img, q);
			if (part == 0) {
				vec4 a = texelFetch(aux_src, q, 0);
				wall = max(wall, a.z);
				foam = max(foam, a.y * step(0.003, s.x));
				if (drain(q)) {
					drained += s.w;
				} else if (s.x > 0.003) {
					surf_sum += terrain(q) + s.x;
					surf_w += 1.0;
				}
			} else {
				float sp = length(s.yz);
				sum_h += s.x;
				sum_e += s.x * sp;
				max_h = max(max_h, s.x);
				max_v = max(max_v, sp * step(0.003, s.x));
			}
		}
	}
	if (part == 0) {
		imageStore(readback_img, c, vec4(wall, drained, surf_w > 0.0 ? surf_sum / surf_w : -1000.0, foam));
	} else {
		imageStore(readback_img, c, vec4(sum_h, sum_e, max_h, max_v));
	}
}

void main() {
	g_res = ivec2(pc.p0.xy);
	g_cell = pc.p0.w;
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	int mode = int(pc.p0.z);
	if (mode == MODE_REDUCE) {
		pass_reduce(c);
		return;
	}
	if (!inside(c)) {
		return;
	}
	if (mode == MODE_FLUX) {
		pass_flux(c);
	} else if (mode == MODE_DEPTH) {
		pass_depth(c);
	} else if (mode == MODE_FX) {
		pass_fx(c);
	} else if (mode == MODE_COPY) {
		imageStore(aux_dst, c, texelFetch(aux_src, c, 0));
	} else if (mode == MODE_CLEAR) {
		imageStore(state_img, c, vec4(0.0));
		imageStore(flux_img, c, vec4(0.0));
	}
}
