// Terrain material: blends meadow / forest / desert ground, slope rock,
// altitude snow, shorelines, rain wetness and puddles.
//
// Vertex colour = biome weights (r meadow, g forest, b desert) and a = forest
// canopy density, written by ChunkBuilder. All texturing is procedural from
// a handful of tiling noise textures sampled at several incommensurate
// scales, which hides tiling without any large texture set.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/include/common.gdshaderinc"

global uniform vec4 detail_rect;

uniform bool is_far = false;
uniform sampler2D tex_macro : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal_fine : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

const float WATER_LEVEL = -4.0;
const float SNOW_LINE = 230.0;

varying vec3 v_wpos;
varying vec3 v_wnormal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (is_far && detail_rect.z > detail_rect.x) {
		// Hide the far terrain where detail chunks exist. Vertices one far
		// cell (8 m) inside the rect drop out of sight; the boundary vertices
		// coincide with the detail chunks' outer LOD ring.
		const float inset = 7.9;
		bool inside = wp.x > detail_rect.x + inset && wp.x < detail_rect.z - inset
			&& wp.z > detail_rect.y + inset && wp.z < detail_rect.w - inset;
		if (inside) {
			VERTEX.y -= 400.0;
			wp.y -= 400.0;
		}
	}
	v_wpos = wp;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_wpos;
	vec3 n = normalize(v_wnormal);
	vec4 bw = COLOR;
	float dist = length(p - CAMERA_POSITION_WORLD);
	float slope = 1.0 - n.y;

	// Multi-scale noise.
	float m1 = texture(tex_macro, p.xz * 0.0011).r;
	float m2 = texture(tex_macro, p.xz * 0.0087 + 0.37).r;
	float d1 = texture(tex_detail, p.xz * 0.067).r;
	float d2 = texture(tex_detail, p.xz * 0.29 + 0.5).r;
	float cells = texture(tex_cells, p.xz * 0.043).r;

	// --- Meadow: grass-covered soil with drier and muddier patches.
	vec3 grass_dark = vec3(0.035, 0.045, 0.02);
	vec3 grass_light = vec3(0.075, 0.09, 0.04);
	vec3 meadow = mix(grass_dark, grass_light, smoothstep(0.3, 0.75, m2 * 0.7 + d1 * 0.3));
	meadow = mix(meadow, meadow * vec3(1.25, 1.05, 0.75), smoothstep(0.55, 0.8, m1));
	vec3 soil = vec3(0.15, 0.115, 0.08) * (0.75 + 0.5 * d2);
	meadow = mix(meadow, soil, smoothstep(0.62, 0.82, d1 * 0.6 + m2 * 0.5) * 0.3);

	// --- Forest floor: needle litter, moss carpets, dark humus.
	vec3 litter = vec3(0.15, 0.10, 0.06) * (0.7 + 0.6 * d2);
	vec3 moss = vec3(0.085, 0.13, 0.03) * (0.8 + 0.45 * d1);
	vec3 forest = mix(litter, moss, smoothstep(0.35, 0.7, m2 + (bw.a - 0.5) * 0.4 + (d1 - 0.5) * 0.3));
	forest = mix(forest, vec3(0.055, 0.042, 0.03), smoothstep(0.55, 0.9, cells) * 0.35);

	// --- Desert sand, warm and slightly varied.
	vec3 sand = mix(vec3(0.60, 0.43, 0.28), vec3(0.79, 0.61, 0.42), m2) * (0.93 + 0.1 * d1);

	vec3 albedo = meadow * bw.r + forest * bw.g + sand * bw.b;

	// --- Exposed rock on slopes (triplanar to avoid stretching on cliffs).
	float rock_mask = smoothstep(0.30, 0.46, slope + (d1 - 0.5) * 0.2 - bw.b * 0.07);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	float rn = texture(tex_detail, p.zy * 0.11).r * tw.x
		+ texture(tex_detail, p.xz * 0.11).r * tw.y
		+ texture(tex_detail, p.xy * 0.11).r * tw.z;
	float strata = sin(p.y * 1.7 + rn * 7.0) * 0.5 + 0.5;
	vec3 rock = mix(vec3(0.22, 0.21, 0.19), vec3(0.42, 0.39, 0.35), rn * 0.7 + strata * 0.3);
	rock = mix(rock, rock * vec3(1.35, 1.0, 0.72), bw.b);
	rock = mix(rock, moss * 1.3, bw.g * smoothstep(0.45, 0.95, n.y + d2 * 0.3) * 0.7);
	albedo = mix(albedo, rock, rock_mask);

	// --- Shoreline mud / wet sand.
	float shore = 1.0 - smoothstep(WATER_LEVEL + 0.1, WATER_LEVEL + 1.8, p.y + d1 * 0.5);
	vec3 shore_col = mix(vec3(0.15, 0.12, 0.09), vec3(0.42, 0.35, 0.26), bw.b);
	albedo = mix(albedo, shore_col, shore * (1.0 - rock_mask));

	// --- Snow above the snow line, on gentle slopes only.
	float snow = smoothstep(SNOW_LINE - 25.0, SNOW_LINE + 35.0, p.y + (m2 - 0.5) * 70.0)
		* smoothstep(0.6, 0.3, slope);
	albedo = mix(albedo, vec3(0.86, 0.88, 0.92), snow);

	// --- Seen from far away, forests read as dark canopy.
	if (is_far) {
		float canopy = bw.g * (0.35 + bw.a * 0.65) * (1.0 - snow) * (1.0 - rock_mask * 0.6);
		albedo = mix(albedo, vec3(0.035, 0.055, 0.025) * (0.75 + 0.5 * m2), canopy);
		float meadow_far = bw.r * (1.0 - rock_mask) * (1.0 - snow);
		albedo = mix(albedo, albedo * vec3(0.9, 1.05, 0.8), meadow_far * 0.5);
	}

	// Under tree cover, ambient light is occluded.
	float ao = 1.0 - bw.a * 0.5;

	float rough = mix(0.93, 0.8, rock_mask);
	rough = mix(rough, 0.88, bw.b);
	rough = mix(rough, 0.55, snow);

	// --- Rain: darker, glossier ground; deserts and snow barely react.
	float wet = clamp(wetness * (1.0 - bw.b * 0.85) * (1.0 - snow), 0.0, 1.0);
	float porosity = mix(0.5, 0.25, rock_mask);
	albedo *= mix(1.0, 1.0 - porosity, wet);
	rough = mix(rough, 0.35, wet * 0.75);
	albedo *= mix(1.0, 0.72, shore);
	rough = mix(rough, 0.22, shore * 0.8);

	// Puddles collect in flat hollows (low-frequency noise minima).
	float puddle = smoothstep(0.6, 0.67, m2 * 0.75 + cells * 0.35 - d1 * 0.1)
		* smoothstep(0.985, 0.996, n.y) * wet * (1.0 - rock_mask) * (1.0 - bw.b);

	// --- Detail normals in world space (no tangents needed on terrain).
	float detail_fade = 1.0 - smoothstep(60.0, 220.0, dist);
	vec2 nd = (texture(tex_normal, p.xz * 0.13).xy * 2.0 - 1.0) * 0.45;
	nd += (texture(tex_normal_fine, p.xz * 0.85).xy * 2.0 - 1.0) * 0.35 * detail_fade;
	nd *= mix(1.0, 2.2, rock_mask) * (1.0 - puddle);

	if (bw.b > 0.01) {
		// Wind ripples in sand: a warped sine field across the dune wind.
		vec2 rdir = normalize(vec2(0.8, 0.6));
		float ph = dot(p.xz, rdir) * 5.5 + d1 * 9.0 + m2 * 20.0;
		nd += rdir * cos(ph) * 0.35 * bw.b * (1.0 - rock_mask) * detail_fade;
	}
	if (puddle > 0.001) {
		nd += rain_ripples(p.xz, TIME) * rain_intensity * puddle * 0.6;
		albedo = mix(albedo, albedo * 0.45, puddle);
		rough = mix(rough, 0.04, puddle);
	}
	vec3 wn = normalize(n + vec3(nd.x, 0.0, nd.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
