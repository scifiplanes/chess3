shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, depth_prepass_alpha, shadows_disabled;

uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform float levels : hint_range(2.0, 12.0) = 6.0;
uniform float strength : hint_range(0.0, 1.0) = 0.72;
uniform vec3 tint_rgb = vec3(1.0, 1.0, 1.0);
uniform float outline_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 outline_rgb = vec3(1.0, 0.45, 0.15);

float bayer4(vec2 p) {
	ivec2 ip = ivec2(int(mod(p.x, 4.0)), int(mod(p.y, 4.0)));
	int i = ip.x + ip.y * 4;
	const int m[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
	return float(m[i]) / 16.0;
}

void fragment() {
	vec4 c = texture(texture_albedo, UV);
	if (c.a < 0.08) {
		discard;
	}
	float thr = bayer4(UV * 128.0) - 0.5;
	vec3 rgb = c.rgb * tint_rgb;
	rgb = clamp(rgb + thr * strength / max(levels, 1.0), 0.0, 1.0);
	rgb = floor(rgb * levels + 0.5) / levels;
	rgb = mix(rgb, outline_rgb, outline_mix * 0.4);
	ALBEDO = rgb;
	ALPHA = c.a;
}
