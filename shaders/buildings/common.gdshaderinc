float bld_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Dominant-axis projection: returns face coords and writes which axis won (0 = X, 1 = Y, 2 = Z).
vec2 bld_project(vec3 p, vec3 n, out int axis) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) {
		axis = 1;
		return p.xz;
	}
	if (a.x >= a.z) {
		axis = 0;
		return vec2(p.z, p.y);
	}
	axis = 2;
	return vec2(p.x, p.y);
}

float bld_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// Trilinear value noise in [0, 1].
float bld_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(bld_hash13(i), bld_hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(bld_hash13(i + vec3(0.0, 1.0, 0.0)), bld_hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(bld_hash13(i + vec3(0.0, 0.0, 1.0)), bld_hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(bld_hash13(i + vec3(0.0, 1.0, 1.0)), bld_hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
