shader_type sky;
render_mode use_debanding;

#include "res://shaders/world/noise.gdshaderinc"

// Stylized toy sky: day/night gradient, soft sun, cheap stars and a moon.
uniform vec3 top_color : source_color = vec3(0.24, 0.55, 0.90);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.90, 0.95);
uniform vec3 below_color : source_color = vec3(0.16, 0.50, 0.66);
uniform vec3 night_top_color : source_color = vec3(0.012, 0.035, 0.07);
uniform vec3 night_horizon_color : source_color = vec3(0.05, 0.13, 0.17);
uniform vec3 night_below_color : source_color = vec3(0.02, 0.06, 0.09);
uniform float gradient_curve = 0.45;
uniform float horizon_band = 0.06;

uniform vec3 sun_tint : source_color = vec3(1.0, 0.93, 0.78);
uniform float sun_disk = 0.9994;
uniform float sun_glow = 0.35;


uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_direction = vec3(0.45, 0.55, -0.70);
uniform vec3 moon_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float moon_disk = 0.99955;
uniform float moon_glow = 0.25;
uniform float star_density = 0.035;
uniform float star_brightness = 1.4;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float up = pow(clamp(h, 0.0, 1.0), gradient_curve);
	vec3 top = mix(top_color, night_top_color, night);
	vec3 hor = mix(horizon_color, night_horizon_color, night);
	vec3 below = mix(below_color, night_below_color, night);
	vec3 col = mix(hor, top, smoothstep(0.0, 1.0, up));
	col = mix(mix(hor, below, smoothstep(0.0, 0.35, -h)), col, smoothstep(-horizon_band * 0.25, horizon_band * 0.25, h));

	float day = 1.0 - night;
	if (LIGHT0_ENABLED && day > 0.0) {
		float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += sun_tint * (pow(sd, 6.0) * sun_glow * 0.35 + pow(sd, 60.0) * sun_glow) * day;
		col += sun_tint * smoothstep(sun_disk, sun_disk + 0.0003, sd) * 6.0 * day;
	}

	vec3 md = normalize(moon_direction);
	float mdot = max(dot(d, md), 0.0);
	if (night > 0.0) {
		col += moon_color * (pow(mdot, 40.0) * moon_glow + pow(mdot, 400.0) * moon_glow) * night;
		col += moon_color * smoothstep(moon_disk, moon_disk + 0.00015, mdot) * 2.5 * night;
	}

	if (!AT_CUBEMAP_PASS && h > 0.0) {
		if (night > 0.0) {
			vec2 sp = d.xz / (h + 1.0) * 180.0;
			vec2 cell = floor(sp);
			float r = hash12(cell);
			vec2 jitter = vec2(hash12(cell + 7.1), hash12(cell + 3.3)) - 0.5;
			float dist = length(fract(sp) - 0.5 - jitter * 0.6);
			float star = step(1.0 - star_density, r) * (1.0 - smoothstep(0.03, 0.16, dist));
			float twinkle = 0.65 + 0.35 * sin(r * 91.0);
			col += vec3(star * twinkle * star_brightness) * smoothstep(0.03, 0.3, h) * night;
		}
	}
	COLOR = col;
}
