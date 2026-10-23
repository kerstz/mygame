// Lakes: a camera-following plane at WATER_LEVEL. Depth-based absorption and
// refraction from the screen texture, sky reflections via the engine's
// radiance (low roughness), animated normals and rain ripples.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, blend_mix;

#include "res://shaders/include/common.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.012, 0.03, 0.03);
uniform vec3 shallow_tint : source_color = vec3(0.55, 0.62, 0.55);
uniform float absorption = 0.45;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wd = normalize(wind_direction + vec2(1e-4));
	vec2 p = v_wpos.xz;
	float t = TIME;
	vec2 n1 = texture(tex_normal, p * 0.045 + wd * t * 0.012).xy * 2.0 - 1.0;
	vec2 n2 = texture(tex_normal, p * 0.11 - wd.yx * t * 0.02).xy * 2.0 - 1.0;
	vec2 nd = (n1 * 0.6 + n2 * 0.4) * (0.08 + wind_strength * 0.12);
	nd += rain_ripples(p * 0.8, t) * rain_intensity * 0.5;
	vec3 wn = normalize(vec3(nd.x, 1.0, nd.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Water depth along the view ray (reverse-Z, Godot 4.3+).
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thickness = max(-view.z - (-VERTEX.z), 0.0);
	vec2 refr_uv = SCREEN_UV + nd * 0.08 * clamp(thickness, 0.0, 1.0);
	vec3 refr = textureLod(screen_tex, refr_uv, 0.0).rgb;
	float trans = exp(-thickness * absorption);
	vec3 body = mix(deep_color, refr * shallow_tint, trans);

	ALBEDO = vec3(0.0);
	EMISSION = body;
	ROUGHNESS = 0.04 + rain_intensity * 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// Soft shoreline.
	ALPHA = smoothstep(0.0, 0.25, thickness);
}
