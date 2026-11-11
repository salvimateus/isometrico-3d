// Procedural surface patterns shared by the per-material shaders and the baked building_paint shader.
// Requires common.gdshaderinc. Call from fragment() only (uses fwidth).

// Stone blocks in world space. Writes a world-space normal tilt for the fake bevel.
vec3 bld_stone(vec3 wp, vec3 wn, vec3 light, vec3 dark, vec3 mortar_col, vec3 moss_col, vec2 block_size,
		float mortar_width, float bevel_width, float moss_height, out vec3 tilt) {
	int axis;
	vec2 uv = bld_project(wp, wn, axis);
	vec2 size = axis == 1 ? vec2(block_size.x * 0.85) : block_size;
	vec2 p = uv / size;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5 + bld_hash12(vec2(row, 7.0)) * 0.3;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 edge2 = min(f, 1.0 - f) * size;
	float edge = min(edge2.x, edge2.y);
	float aa = max(fwidth(edge), 0.002);
	// Fine detail fades out once a block covers only a few pixels (keeps the iso view clean).
	float detail = 1.0 - smoothstep(0.006, 0.02, fwidth(uv.x));
	float inside = smoothstep(mortar_width - aa, mortar_width + aa, edge);
	float h = bld_hash12(cell + float(axis) * 17.0);
	float h2 = bld_hash12(cell * 1.7 + 3.3);
	vec3 block = mix(dark, light, 0.25 + 0.75 * h);
	block *= mix(vec3(1.04, 1.0, 0.93), vec3(0.95, 0.98, 1.03), h2);
	float mottle = bld_vnoise(wp * 6.0 + vec3(h * 9.0));
	block *= 1.0 - 0.1 * detail * mottle;
	float ao = smoothstep(mortar_width, mortar_width + bevel_width, edge);
	block *= mix(0.78, 1.0, ao);
	if (axis != 1) {
		block *= 1.0 + 0.07 * smoothstep(0.7, 1.0, f.y) - 0.06 * smoothstep(0.3, 0.0, f.y);
	}
	vec2 bevel = vec2(
		(f.x < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(mortar_width, mortar_width + bevel_width, edge2.x)),
		(f.y < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(mortar_width, mortar_width + bevel_width, edge2.y)));
	bevel *= inside * detail * 0.55;
	tilt = axis == 0 ? vec3(0.0, bevel.y, bevel.x) : (axis == 2 ? vec3(bevel.x, bevel.y, 0.0) : vec3(bevel.x, 0.0, bevel.y));
	vec3 col = mix(mortar_col, block, inside);
	float low = 1.0 - smoothstep(0.0, moss_height, wp.y);
	if (axis != 1) {
		float patches = smoothstep(0.35, 0.7, bld_vnoise(wp * 3.5));
		col *= 1.0 - 0.18 * low;
		col = mix(col, moss_col, low * patches * 0.55);
	}
	return col;
}

// Wooden planks: world projection, or the mesh UV for tilted/animated parts.
vec3 bld_planks(vec3 wp, vec3 wn, vec2 mesh_uv, bool use_uv, bool horizontal, vec3 light, vec3 dark,
		vec3 seam_col, float plank_width, float plank_length, float seam_width) {
	int axis;
	vec2 uv = bld_project(wp, wn, axis);
	if (use_uv) {
		uv = mesh_uv;
		axis = 1;
	}
	vec2 p = (horizontal || axis == 1) ? uv : uv.yx;
	float across = p.y / plank_width;
	float row = floor(across);
	float along = p.x / plank_length + bld_hash12(vec2(row, float(axis))) * 3.0;
	vec2 cell = vec2(floor(along), row);
	float fy = fract(across);
	float fx = fract(along);
	float edge = min(min(fy, 1.0 - fy) * plank_width, min(fx, 1.0 - fx) * plank_length);
	float aa = max(fwidth(edge), 0.002);
	float inside = smoothstep(seam_width - aa, seam_width + aa, edge);
	float h = bld_hash12(cell + 3.1);
	vec3 plank = mix(dark, light, 0.35 + 0.65 * h);
	float grain = sin((p.x * 3.0 + h * 10.0) + sin(p.y * 40.0 + h * 6.0) * 0.6);
	plank *= 0.95 + 0.05 * grain;
	plank *= 0.9 + 0.1 * smoothstep(0.0, 0.45, min(fy, 1.0 - fy));
	return mix(seam_col, plank, inside);
}

// Scalloped roof tiles laid out by the roof mesh UV (along eave, up the slope).
vec3 bld_roof(vec2 mesh_uv, vec3 base, vec3 shadow, vec2 tile_size) {
	vec2 p = mesh_uv / tile_size;
	float row = floor(p.y);
	float fy = fract(p.y);
	float x = p.x + mod(row, 2.0) * 0.5;
	float fx = fract(x) - 0.5;
	float arc = 0.32 * (1.0 - sqrt(max(1.0 - 4.0 * fx * fx, 0.0)));
	vec2 cell = vec2(floor(x), row);
	float local_y = fy;
	if (fy < arc) {
		cell = vec2(floor(p.x + mod(row - 1.0, 2.0) * 0.5), row - 1.0);
		local_y = fy + 1.0;
	}
	float h = bld_hash12(cell + 11.0);
	vec3 col = mix(shadow, base, 0.72 + 0.28 * h);
	float shade = mix(1.08, 0.78, smoothstep(0.0, 1.1, local_y - arc));
	float d_edge = abs(fy - arc) * tile_size.y;
	float aa = max(fwidth(d_edge), 0.002);
	float groove = smoothstep(0.004 - aa, 0.004 + aa + 0.01, d_edge);
	col *= shade;
	return mix(shadow * 0.55, col, groove);
}

// Stylized rock with strata; tone varies by low-frequency world noise (valid after mesh baking).
vec3 bld_rock(vec3 wp, vec3 wn, vec3 light, vec3 dark, vec3 strata_col, float strata_scale) {
	float tone = bld_vnoise(wp * 0.9 + vec3(13.0));
	float n = bld_vnoise(wp * 2.5) * 0.6 + bld_vnoise(wp * 7.0) * 0.4;
	vec3 col = mix(dark, light, clamp(0.15 + 0.85 * n, 0.0, 1.0));
	float band = fract(wp.y * strata_scale + n * 0.9 + tone * 3.0);
	float strata = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.32, 0.42, band));
	col = mix(col, strata_col, strata * 0.45);
	col *= 0.86 + 0.24 * tone;
	col *= 1.0 + 0.12 * smoothstep(0.4, 0.95, wn.y);
	col *= mix(0.72, 1.0, smoothstep(0.0, 0.3, wp.y));
	return col;
}
