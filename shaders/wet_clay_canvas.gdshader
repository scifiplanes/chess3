shader_type canvas_item;
render_mode blend_mix, unshaded;

// Fake-3D clay slab: pixel-stable grain, extrude rim, contact shadow under.
uniform vec4 clay_tint : source_color = vec4(0.24, 0.15, 0.10, 1.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.55;
uniform float corner_px : hint_range(2.0, 48.0) = 14.0;
uniform vec2 rect_px = vec2(128.0, 64.0);
uniform float thickness : hint_range(0.0, 2.5) = 1.35;
uniform float extrude_px : hint_range(0.0, 24.0) = 10.0;
uniform float fingerprint : hint_range(0.0, 1.0) = 0.12;
uniform float tex_scale : hint_range(0.02, 0.25) = 0.09;
uniform vec2 light_dir = vec2(-0.4, -0.75);
uniform float press : hint_range(0.0, 1.0) = 0.0;
uniform float use_sdf_clip : hint_range(0.0, 1.0) = 1.0;

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
		p = p * 2.05 + vec2(13.7, 5.3);
		a *= 0.5;
	}
	return v;
}

float sd_round_box_px(vec2 uv, vec2 size_px, float r_px) {
	vec2 p = (uv - 0.5) * size_px;
	vec2 half_size = size_px * 0.5;
	float r = min(r_px, min(half_size.x, half_size.y) - 1.0);
	vec2 q = abs(p) - (half_size - vec2(r));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;
	if (src.a < 0.02) {
		discard;
	}

	// Backplate is oversized: content rect inset so extrude + shadow fit inside.
	vec2 size_px = max(rect_px, vec2(8.0));
	float pad_b = extrude_px + 8.0;
	float pad_r = extrude_px * 0.45 + 4.0;
	float pad_t = 2.0;
	float pad_l = 2.0;
	vec2 content = size_px - vec2(pad_l + pad_r, pad_t + pad_b);
	content = max(content, vec2(8.0));
	// UV mapped onto content face (then extrude hangs below/right in local px).
	vec2 local_px = UV * size_px;
	vec2 face_uv = (local_px - vec2(pad_l, pad_t)) / content;

	vec2 px = FRAGCOORD.xy * tex_scale;
	float wobble = (fbm(px * 0.55) - 0.5) * 1.1;
	float d_face = sd_round_box_px(face_uv, content, corner_px + wobble);

	// Extruded outer silhouette (face shifted down-right by extrude).
	vec2 face_uv_shift = (local_px - vec2(pad_l, pad_t) - vec2(extrude_px * 0.35, extrude_px)) / content;
	float d_outer = sd_round_box_px(face_uv_shift, content, corner_px + wobble * 0.8);

	float in_face = 1.0 - smoothstep(-0.6, 1.1, d_face);
	float in_outer = 1.0 - smoothstep(-0.6, 1.1, d_outer);
	float side = clamp(in_outer - in_face, 0.0, 1.0);

	// Soft contact shadow under outer slab.
	vec2 sh_uv = (local_px - vec2(pad_l + 2.0, pad_t + extrude_px + 3.0)) / content;
	float d_sh = sd_round_box_px(sh_uv, content, corner_px + 2.0);
	float shadow = (1.0 - smoothstep(-2.0, 14.0, d_sh)) * 0.55;
	shadow *= smoothstep(0.0, 0.15, UV.y); // only toward bottom of widget

	if (use_sdf_clip > 0.5) {
		if (in_outer < 0.02 && shadow < 0.02) {
			discard;
		}
	}

	float fp = fbm(px);
	float grain = fbm(px * 2.8 + 4.0);

	vec3 face_col = clay_tint.rgb;
	face_col *= mix(0.97, 1.02, fp);
	face_col = mix(face_col, face_col * 0.96, grain * fingerprint);

	// Bevel normals on face.
	vec2 eps = vec2(1.0 / content.x, 0.0);
	float nx = sd_round_box_px(face_uv + eps, content, corner_px) - sd_round_box_px(face_uv - eps, content, corner_px);
	eps = vec2(0.0, 1.0 / content.y);
	float ny = sd_round_box_px(face_uv + eps, content, corner_px) - sd_round_box_px(face_uv - eps, content, corner_px);
	vec3 nrm = normalize(vec3(-nx * content.x * 0.4, -ny * content.y * 0.4, 1.0));
	vec3 L = normalize(vec3(light_dir.x, light_dir.y, 0.95));
	float ndl = clamp(dot(nrm, L), 0.0, 1.0);
	face_col *= mix(0.88, 1.1, ndl * 0.55 + 0.45);

	float rim = pow(clamp(1.0 - abs(d_face) / max(corner_px, 1.0), 0.0, 1.0), 1.2) * thickness;
	float top = smoothstep(0.85, 0.12, face_uv.y);
	face_col += vec3(0.1, 0.08, 0.05) * top * rim * 0.7;
	face_col *= 1.0 - smoothstep(-1.0, 8.0, d_face) * 0.18;

	vec3 V = vec3(0.0, 0.2, 1.0);
	vec3 H = normalize(L + V);
	float spec = pow(clamp(dot(nrm, H), 0.0, 1.0), mix(28.0, 64.0, wetness));
	float fres = pow(1.0 - clamp(nrm.z, 0.0, 1.0), 2.4);
	face_col += vec3(0.7, 0.62, 0.5) * spec * wetness * fres * 0.4;

	// Side wall of the slab (extrude).
	vec3 side_col = clay_tint.rgb * 0.55;
	side_col *= mix(0.9, 1.05, fp);
	float side_lit = mix(0.75, 1.15, clamp(-light_dir.x * 0.5 + 0.5, 0.0, 1.0));
	side_col *= side_lit;
	// Soft top lip where face meets side.
	float lip = smoothstep(0.0, 3.0, abs(d_face)) * side;
	side_col += vec3(0.08, 0.06, 0.04) * (1.0 - lip) * 0.5;

	vec3 base = mix(face_col, side_col, side);
	base *= mix(1.0, 0.86, press);

	float alpha = src.a * clay_tint.a * max(in_outer, shadow * 0.85);
	// Multiply shadow into empty area under slab.
	if (in_outer < 0.15) {
		base = vec3(0.02, 0.01, 0.005);
		alpha = shadow * src.a;
	} else if (side > 0.05 && in_face < 0.5) {
		alpha = max(alpha, side * src.a);
	}

	COLOR = vec4(clamp(base, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
