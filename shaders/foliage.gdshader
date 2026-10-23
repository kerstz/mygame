// Foliage cards: conifer needles (pattern 0), broad leaves (1), fern fronds
// (2) and opaque far-LOD tree impostors (3).
//
// Leaf shapes are procedural alpha masks evaluated from UVs, so no texture
// assets are needed. Cards carry spherical normals (pointing away from the
// crown centre) which gives soft, volumetric canopy lighting.
// Instance custom: r = hue, g = dryness, b = random, a = tree scale/random.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;

#include "res://shaders/include/common.gdshaderinc"

uniform int pattern = 1;
uniform float sway_height = 18.0;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_detail : filter_linear_mipmap, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.08, 0.13, 0.05);
uniform vec3 color_b : source_color = vec3(0.18, 0.24, 0.07);
uniform vec3 dry_tint : source_color = vec3(0.36, 0.31, 0.17);

varying vec3 v_tint;
varying float v_dry;
varying float v_rand;
varying float v_height;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 rel = VERTEX - origin;
	float scale = length(MODEL_MATRIX[0].xyz);
	float tree_h = sway_height * scale;
	vec2 wd = normalize(wind_direction + vec2(1e-4));
	float gust = texture(wind_noise, origin.xz * 0.004 - wd * TIME * 0.03).r;
	float phase = INSTANCE_CUSTOM.b;
	VERTEX += tree_sway(rel, phase, gust, tree_h, TIME);
	if (pattern != 3) {
		// Leaf flutter: small, fast, spatially varying.
		float f = sin(TIME * (4.0 + phase * 3.0) + dot(VERTEX, vec3(1.7, 2.3, 1.3)));
		VERTEX += NORMAL * f * 0.025 * (0.3 + wind_strength) * clamp(rel.y / max(tree_h, 1.0) + 0.3, 0.0, 1.0);
	}
	v_tint = mix(vec3(0.85, 0.95, 0.85), vec3(1.15, 1.05, 0.9), INSTANCE_CUSTOM.r);
	v_dry = INSTANCE_CUSTOM.g;
	v_rand = INSTANCE_CUSTOM.r;
	v_height = clamp(rel.y / max(tree_h, 0.5), 0.0, 1.0);
}

float needle_mask(vec2 uv, float rnd) {
	float across = abs(uv.x - 0.5) * 2.0;
	// Branch outline tapers toward the tip, with ragged edges.
	float mass = texture(tex_detail, uv * vec2(1.3, 3.2) + rnd * 5.0).r;
	float envelope = (1.0 - uv.y * 0.55) - across + (mass - 0.5) * 0.9;
	// Diagonal needle strands growing out from the central twig.
	float strands = pow(abs(sin(uv.y * 46.0 + across * 9.0 + rnd * 10.0)), 3.0);
	float twig = 1.0 - smoothstep(0.02, 0.05, across);
	return max(twig * step(uv.y, 0.97), envelope * 2.2 + strands * 0.35 - 0.25);
}

float leaf_mask(vec2 uv, float rnd) {
	if (length(uv - 0.5) > 0.5) {
		return 0.0;
	}
	vec2 q = uv * 3.2 + rnd * 7.0;
	float m = 0.0;
	// Check the 4 nearest cells so leaves can cross cell borders.
	vec2 base = floor(q - 0.5);
	for (int j = 0; j <= 1; j++) {
		for (int i = 0; i <= 1; i++) {
			vec2 c = base + vec2(float(i), float(j));
			vec2 r = hash22(c);
			vec2 f = q - c - 0.25 - r * 0.5;
			float a = r.x * 6.283;
			vec2 fr = vec2(cos(a) * f.x - sin(a) * f.y, sin(a) * f.x + cos(a) * f.y);
			// Pointed leaf: ellipse narrowed toward one end.
			float w = 0.2 * (1.0 - smoothstep(-0.35, 0.42, fr.y) * 0.75);
			float leaf = (fr.x * fr.x) / (w * w) + (fr.y * fr.y) / (0.42 * 0.42);
			m = max(m, 1.0 - leaf);
		}
	}
	return m * 2.0;
}

float fern_mask(vec2 uv) {
	float across = abs(uv.x - 0.5) * 2.0;
	float envelope = sin(3.14159 * clamp(uv.y * 1.05, 0.0, 1.0)) * (1.0 - uv.y * 0.3);
	// Alternating pinnae, each slightly swept toward the tip.
	float pinna = fract(uv.y * 17.0 - across * 0.9 + (uv.x > 0.5 ? 0.5 : 0.0));
	float leaflet = 1.0 - abs(pinna - 0.5) * 2.0;
	float rib = 1.0 - smoothstep(0.03, 0.07, across);
	return max(rib, (leaflet * 1.4 - 0.35) * step(across, envelope));
}

void fragment() {
	float rnd = v_rand;
	float alpha = 1.0;
	float n1 = texture(tex_detail, UV * 0.7 + rnd).r;
	if (pattern == 0) {
		alpha = needle_mask(UV, rnd);
	} else if (pattern == 1) {
		alpha = leaf_mask(UV, rnd);
	} else if (pattern == 2) {
		alpha = fern_mask(UV);
	}
	vec3 col = mix(color_a, color_b, clamp(n1 * 1.2 - 0.1 + v_height * 0.3, 0.0, 1.0)) * v_tint;
	col = mix(col, dry_tint * (0.7 + n1 * 0.5), v_dry * (pattern == 0 ? 0.0 : 0.85));
	if (pattern == 3) {
		// Impostor: fake crown texture and darker base, fully opaque.
		float n2 = texture(tex_detail, UV * vec2(6.0, 10.0)).r;
		col *= mix(0.55, 1.15, n2) * mix(0.6, 1.0, v_height);
	}
	float wet = wetness;
	col *= mix(1.0, 0.8, wet);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = mix(0.7, 0.35, wet);
	SPECULAR = 0.4;
	// Inner crown is darker (self shadowing approximation).
	AO = mix(0.45, 1.0, v_height * 0.5 + 0.5);
	AO_LIGHT_AFFECT = 0.3;
	BACKLIGHT = col * (pattern == 3 ? 0.1 : 0.6);
}
