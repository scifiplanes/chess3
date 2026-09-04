shader_type canvas_item;

uniform float levels : hint_range(2.0, 12.0) = 6.0;
uniform float strength : hint_range(0.0, 1.0) = 0.72;

float bayer4(vec2 p) {
	ivec2 ip = ivec2(int(mod(p.x, 4.0)), int(mod(p.y, 4.0)));
	int i = ip.x + ip.y * 4;
	const int m[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
	return float(m[i]) / 16.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (c.a < 0.08) {
		discard;
	}
	float thr = bayer4(UV * 128.0) - 0.5;
	vec3 rgb = clamp(c.rgb + thr * strength / max(levels, 1.0), 0.0, 1.0);
	rgb = floor(rgb * levels + 0.5) / levels;
	COLOR = vec4(rgb, c.a);
}
