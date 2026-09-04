shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 clay_tint : source_color = vec4(0.55, 0.38, 0.26, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.7;
uniform float fingerprint : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.55;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 8.0;
	float fp = fbm(uv);
	float grain = fbm(uv * 3.5 + 4.0);
	vec3 albedo = clay_tint.rgb * mix(0.78, 1.08, fp);
	albedo = mix(albedo, albedo * vec3(0.85, 0.78, 0.68), grain * fingerprint * 0.4);

	float wet_mask = smoothstep(0.35, 0.75, fp) * wetness;
	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_base, 0.18, wet_mask);
	SPECULAR = mix(0.25, 0.75, wet_mask);
	NORMAL_MAP_DEPTH = 0.45 + fingerprint * 0.35;
}
