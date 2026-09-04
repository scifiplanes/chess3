shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float colour_preserve : hint_range(0.0, 1.0) = 0.6;
uniform float pixel_size : hint_range(1.0, 8.0) = 1.0;
uniform float levels : hint_range(2.0, 32.0) = 10.0;
uniform float matrix_size : hint_range(2.0, 8.0) = 4.0; // 2, 4, 8
uniform float palette : hint_range(0.0, 4.0) = 4.0; // 0..4 (4 = no snap)
uniform float palette0_mix : hint_range(0.0, 1.0) = 1.0;
uniform float post_levels : hint_range(0.0, 3.0) = 1.0;
uniform float post_lift : hint_range(-0.5, 0.5) = 0.0;
uniform float post_gamma : hint_range(0.2, 3.0) = 1.0;

float bayer2(vec2 p) {
	int x = int(mod(p.x, 2.0));
	int y = int(mod(p.y, 2.0));
	if (x == 0 && y == 0) {
		return 0.0;
	}
	if (x == 1 && y == 0) {
		return 2.0;
	}
	if (x == 0 && y == 1) {
		return 3.0;
	}
	return 1.0;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	const int m[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
	return float(m[idx]);
}

float bayer8(vec2 p) {
	int x = int(mod(p.x, 8.0));
	int y = int(mod(p.y, 8.0));
	int idx = x + y * 8;
	const int m[64] = {
		0, 32, 8, 40, 2, 34, 10, 42,
		48, 16, 56, 24, 50, 18, 58, 26,
		12, 44, 4, 36, 14, 46, 6, 38,
		60, 28, 52, 20, 62, 30, 54, 22,
		3, 35, 11, 43, 1, 33, 9, 41,
		51, 19, 59, 27, 49, 17, 57, 25,
		15, 47, 7, 39, 13, 45, 5, 37,
		63, 31, 55, 23, 61, 29, 53, 21
	};
	return float(m[idx]);
}

float bayer(vec2 p, float size) {
	if (size < 3.0) {
		return bayer2(p) / 4.0;
	}
	if (size < 6.0) {
		return bayer4(p) / 16.0;
	}
	return bayer8(p) / 64.0;
}

vec3 palette_color(int pal, int idx) {
	if (pal == 0) {
		const vec3 c[5] = {
			vec3(0.05, 0.04, 0.06),
			vec3(0.22, 0.16, 0.14),
			vec3(0.55, 0.34, 0.22),
			vec3(0.85, 0.63, 0.33),
			vec3(1.00, 0.92, 0.72)
		};
		return c[idx];
	}
	if (pal == 1) {
		const vec3 c[5] = {
			vec3(0.03, 0.05, 0.08),
			vec3(0.10, 0.18, 0.22),
			vec3(0.22, 0.34, 0.38),
			vec3(0.55, 0.75, 0.78),
			vec3(0.92, 0.98, 1.00)
		};
		return c[idx];
	}
	if (pal == 2) {
		const vec3 c[5] = {
			vec3(0.06),
			vec3(0.22),
			vec3(0.44),
			vec3(0.70),
			vec3(0.92)
		};
		return c[idx];
	}
	const vec3 c[5] = {
		vec3(0.05, 0.04, 0.03),
		vec3(0.25, 0.19, 0.12),
		vec3(0.48, 0.37, 0.22),
		vec3(0.72, 0.58, 0.38),
		vec3(0.95, 0.86, 0.68)
	};
	return c[idx];
}

vec3 snap_to_palette(vec3 col, int pal) {
	float best = 1e9;
	vec3 outc = col;
	for (int i = 0; i < 5; i++) {
		vec3 p = palette_color(pal, i);
		float d = dot(col - p, col - p);
		if (d < best) {
			best = d;
			outc = p;
		}
	}
	return outc;
}

vec3 quantize(vec3 col, float steps) {
	return floor(col * (steps - 1.0) + 0.5) / (steps - 1.0);
}

void fragment() {
	vec2 frag = FRAGCOORD.xy;
	float ps = max(1.0, pixel_size);
	vec2 pix = floor(frag / ps) * ps;

	vec4 src = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 col = src.rgb;

	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 mono = vec3(luma);
	col = mix(mono, col, clamp(colour_preserve, 0.0, 1.0));

	float d = bayer(pix, matrix_size) - 0.5;
	float s = max(2.0, levels);
	vec3 q = quantize(col + d / s, s);

	int pal = int(floor(palette + 0.5));
	vec3 snapped;
	if (pal >= 4) {
		snapped = q;
	} else if (pal == 0) {
		vec3 warm = snap_to_palette(q, 0);
		snapped = mix(q, warm, clamp(palette0_mix, 0.0, 1.0));
	} else {
		snapped = snap_to_palette(q, pal);
	}

	vec3 outc = mix(src.rgb, snapped, clamp(strength, 0.0, 1.0));
	float gain = max(0.0, post_levels);
	float lift = post_lift;
	float gamma = max(1e-6, post_gamma);
	outc = clamp(outc * gain + lift, 0.0, 1.0);
	outc = pow(outc, vec3(1.0 / gamma));
	COLOR = vec4(outc, 1.0);
}
