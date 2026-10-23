// Boulders and concrete ruins (concrete = true). Geometry is merged per
// chunk, so per-object variation comes from vertex colour:
//   r = moss amount, g = sand/dust amount, b = hue random.
// Texturing is world-space triplanar noise; detail normals are perturbed in
// world space so no tangents are needed on the merged meshes.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/include/common.gdshaderinc"

uniform bool concrete = false;
uniform sampler2D tex_macro : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal_fine : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_wpos;
varying vec3 v_wnormal;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_sample(sampler2D t, vec3 p, vec3 w, float s) {
	return texture(t, p.zy * s).r * w.x + texture(t, p.xz * s).r * w.y + texture(t, p.xy * s).r * w.z;
}

vec2 tri_normal(sampler2D t, vec3 p, vec3 w, float s) {
	// Returns an XZ-ish perturbation; good enough for rough stone.
	vec2 a = texture(t, p.zy * s).xy * 2.0 - 1.0;
	vec2 b = texture(t, p.xz * s).xy * 2.0 - 1.0;
	vec2 c = texture(t, p.xy * s).xy * 2.0 - 1.0;
	return a * w.x + b * w.y + c * w.z;
}

void fragment() {
	vec3 p = v_wpos;
	vec3 n = normalize(v_wnormal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float d1 = tri_sample(tex_detail, p, w, 0.35);
	float d2 = tri_sample(tex_detail, p, w, 1.6);
	float cells = tri_sample(tex_cells, p, w, 0.25);
	float moss_amt = COLOR.r;
	float sand_amt = COLOR.g;
	float hue = COLOR.b;
	vec3 col;
	float rough;
	if (concrete) {
		col = mix(vec3(0.30, 0.30, 0.29), vec3(0.50, 0.49, 0.46), d1 * 0.6 + d2 * 0.4);
		// Rain streaks running down vertical faces.
		float streak = texture(tex_detail, vec2(p.x + p.z, p.y * 0.08) * vec2(1.5, 1.0)).r;
		col *= mix(1.0, 0.55, smoothstep(0.5, 0.8, streak) * (1.0 - abs(n.y)));
		// Cracks.
		col *= mix(1.0, 0.45, smoothstep(0.08, 0.02, cells));
		// Overgrowth: thick moss on every upward face.
		moss_amt = 0.85;
		rough = 0.85;
	} else {
		float strata = sin((p.y + d1 * 2.0) * 6.0) * 0.5 + 0.5;
		col = mix(vec3(0.20, 0.19, 0.18), vec3(0.45, 0.43, 0.40), d1 * 0.65 + strata * 0.15 + d2 * 0.2);
		col *= mix(vec3(0.95, 0.97, 1.0), vec3(1.1, 1.0, 0.9), hue);
		col = mix(col, col * vec3(1.45, 1.05, 0.7), sand_amt);  // desert sandstone
		rough = 0.82;
	}
	float macro = texture(tex_macro, p.xz * 0.02).r;
	float moss = moss_amt * smoothstep(0.25, 0.75, n.y + (d2 - 0.5) * 0.8 + (macro - 0.5) * 0.6);
	col = mix(col, vec3(0.08, 0.14, 0.03) * (0.7 + d2 * 0.6), moss);
	float dust = sand_amt * smoothstep(0.4, 0.9, n.y + d2 * 0.3);
	col = mix(col, vec3(0.72, 0.56, 0.38), dust * 0.8);

	float wet = wetness * (1.0 - sand_amt * 0.8);
	col *= mix(1.0, 0.62, wet * (1.0 - moss * 0.3));
	rough = mix(rough, 0.3, wet);
	rough = mix(rough, 0.9, moss * (1.0 - wet));

	vec2 nd = tri_normal(tex_normal, p, w, 0.5) * 0.6 + tri_normal(tex_normal_fine, p, w, 2.0) * 0.35;
	vec3 t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 t2 = cross(n, t1);
	vec3 wn = normalize(n + (t1 * nd.x + t2 * nd.y) * (1.0 - moss * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}
