// Grass clumps (and seeding stalks with is_seedhead = true).
//
// Instances come from MultiMesh with custom data:
//   r = hue variation, g = dryness, b = random keep threshold, a = wind phase.
// Mesh UV.y is 0 at the root and 1 at the blade tip.
//
// Distance handling: blades whose random threshold exceeds the local density
// collapse to a point (degenerate triangles, no fragment cost), so density
// falls off smoothly with distance instead of popping per chunk.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;

#include "res://shaders/include/common.gdshaderinc"

global uniform float grass_view_distance;
global uniform float grass_density_scale;

uniform bool is_seedhead = false;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_macro : filter_linear_mipmap, repeat_enable;
uniform vec3 root_color : source_color = vec3(0.025, 0.032, 0.018);
uniform vec3 mid_color : source_color = vec3(0.085, 0.11, 0.05);
uniform vec3 tip_color : source_color = vec3(0.19, 0.21, 0.12);
uniform vec3 dry_color : source_color = vec3(0.34, 0.30, 0.19);
uniform vec3 seed_color : source_color = vec3(0.52, 0.51, 0.44);

varying float v_h;
varying vec3 v_tint;
varying float v_gust;
varying float v_dry;
varying float v_pick;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = UV.y;
	v_h = h;
	v_dry = INSTANCE_CUSTOM.g;
	v_pick = INSTANCE_CUSTOM.r;
	v_gust = 0.0;
	float dist = length(origin - CAMERA_POSITION_WORLD);
	float view = grass_view_distance * (is_seedhead ? 0.8 : 1.0);
	float keep = INSTANCE_CUSTOM.b;
	// Full density up to 35 % of the range, thinning to 20 % at the end.
	float density = mix(0.2, 1.0, 1.0 - smoothstep(view * 0.35, view, dist));
	density *= 1.0 - smoothstep(view * 0.85, view, dist);
	if (keep > density) {
		VERTEX = origin;
	} else {
		// Blades near their culling threshold shrink first (no popping).
		float shrink = clamp((density - keep) * 8.0, 0.0, 1.0);
		vec3 rel = VERTEX - origin;
		rel *= mix(0.2, 1.0, shrink);
		// Far blades get a little wider to keep coverage.
		rel.xz *= 1.0 + smoothstep(20.0, view, dist) * 0.8;

		vec2 wd = normalize(wind_direction + vec2(1e-4));
		float gust = texture(wind_noise, origin.xz * 0.011 - wd * TIME * 0.045 * (0.6 + wind_strength)).r;
		gust = smoothstep(0.25, 0.85, gust);
		v_gust = gust;
		float phase = INSTANCE_CUSTOM.a * 6.283;
		float flutter = sin(TIME * (1.7 + INSTANCE_CUSTOM.a) + phase + origin.x * 0.4) * 0.5
			+ sin(TIME * 3.1 + phase * 2.0 + origin.z * 0.7) * 0.25;
		float blade_h = max(rel.y, 0.0);
		float k = h * h;
		vec2 bend = wd * (0.08 + gust * 0.9) * wind_strength
			+ vec2(flutter, flutter * 0.7) * 0.06 * (0.25 + wind_strength);
		bend *= 1.0 + rain_intensity * 0.25;
		rel.xz += bend * k * blade_h * 1.6;
		rel.y -= length(bend) * k * blade_h * 0.5;
		VERTEX = origin + rel;
	}
	// Mostly-up normals give soft, field-like shading instead of harsh blades.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.7));

	vec3 macro = vec3(texture(tex_macro, origin.xz * 0.004).r);
	float hue = INSTANCE_CUSTOM.r;
	v_tint = mix(vec3(0.85, 0.95, 0.8), vec3(1.15, 1.05, 0.85), hue) * mix(0.8, 1.15, macro.r);
}

void fragment() {
	float h = v_h;
	vec3 col = mix(root_color, mid_color, smoothstep(0.0, 0.45, h));
	col = mix(col, tip_color, smoothstep(0.45, 1.0, h));
	col *= v_tint;
	float dry = v_dry;
	col = mix(col, dry_color * mix(0.6, 1.0, h), dry);
	if (is_seedhead && h > 0.72) {
		// Pale, slightly translucent seed heads: the bright specks in the
		// reference image. Straw to grey-beige variation per stalk.
		col = mix(seed_color * vec3(1.05, 1.0, 0.85), seed_color * 0.8, v_pick);
	}
	// Wind "sheen": bent tips catch more light, like real grass waves.
	col *= 1.0 + v_gust * wind_strength * 0.25 * h;
	float wet = wetness;
	col *= mix(1.0, 0.78, wet);
	ALBEDO = col;
	// Water droplets beaded on blades: sparse, very smooth specks that
	// glint under the diffuse sky when the field is wet.
	float drop = step(0.985, hash12(floor(UV * vec2(3.0, 38.0)) + v_pick * 97.0));
	ROUGHNESS = mix(mix(0.62, 0.38, wet), 0.15, drop * wet);
	SPECULAR = 0.35 + wet * 0.2;
	// Self-occlusion at the root of the clump.
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.7, h));
	AO_LIGHT_AFFECT = 0.4;
	// Thin blades transmit light: strong when backlit by the sun.
	BACKLIGHT = col * 0.75;
}
