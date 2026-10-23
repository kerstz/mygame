// Bark for trunks/branches and fallen logs. Procedural vertical furrows
// (stretched noise along the tube UV), moss on the up/shaded side, rain
// darkening. Uses the same tree_sway() as foliage so canopies stay attached.
// Instance custom: g = moss amount (forest), b = wind phase.
shader_type spatial;
render_mode cull_back, world_vertex_coords;

#include "res://shaders/include/common.gdshaderinc"

uniform bool static_object = false;
uniform float sway_height = 18.0;
uniform float moss_bias = 0.0;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying float v_moss;
varying vec3 v_wnormal;
varying float v_hue;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (!static_object) {
		float scale = length(MODEL_MATRIX[0].xyz);
		vec2 wd = normalize(wind_direction + vec2(1e-4));
		float gust = texture(wind_noise, origin.xz * 0.004 - wd * TIME * 0.03).r;
		VERTEX += tree_sway(VERTEX - origin, INSTANCE_CUSTOM.b, gust, sway_height * scale, TIME);
	}
	v_moss = INSTANCE_CUSTOM.g;
	v_hue = INSTANCE_CUSTOM.r;
	v_wnormal = NORMAL;
}

void fragment() {
	// UV.x wraps around the trunk, UV.y runs along it in metres.
	vec2 buv = vec2(UV.x * 3.0, UV.y * 0.18);
	float furrow = texture(tex_detail, buv + v_hue).r;
	float fine = texture(tex_detail, UV * vec2(9.0, 1.4)).r;
	float ridges = smoothstep(0.35, 0.65, furrow) * 0.7 + fine * 0.3;
	vec3 col = mix(vec3(0.06, 0.045, 0.035), vec3(0.22, 0.18, 0.14), ridges);
	col *= mix(0.85, 1.15, v_hue);
	vec3 wn = normalize(v_wnormal);
	// Moss grows on upward faces and near the ground.
	float moss = clamp(v_moss * 0.8 + moss_bias, 0.0, 1.0)
		* smoothstep(0.1, 0.6, wn.y * 0.6 + 0.4 - min(UV.y, 6.0) * 0.06 + fine * 0.4);
	col = mix(col, vec3(0.09, 0.15, 0.035) * (0.7 + fine * 0.6), moss);
	float wet = wetness;
	col *= mix(1.0, 0.6, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.45, wet);
	vec2 nd = (texture(tex_normal, buv * 2.0).xy * 2.0 - 1.0);
	NORMAL_MAP = vec3(nd * 0.8 * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
