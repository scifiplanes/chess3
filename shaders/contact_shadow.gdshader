shader_type spatial;
// Soft contact ellipse on the board floor. World-flat. Clipped to board AABB.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.05, 0.156);
uniform float edge_softness = 0.92;
uniform vec2 board_center = vec2(7.0, 7.0);
uniform float board_half = 7.2;
uniform float board_edge_softness = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = vec2(world_pos.x, world_pos.z) - board_center;
	float pd = max(abs(xz.x), abs(xz.y));
	float inside = 1.0 - smoothstep(
		board_half - board_edge_softness,
		board_half,
		pd
	);
	if (inside <= 0.002) {
		discard;
	}

	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float a = 1.0 - smoothstep(1.0 - edge_softness, 1.0, d);
	a = pow(a, 1.55);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a * inside;
	if (ALPHA < 0.001) {
		discard;
	}
}
