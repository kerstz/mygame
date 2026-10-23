// Rain streaks for GPUParticles3D. Each particle quad is stretched along its
// velocity (particle_flag_align_y) and billboarded around that axis toward
// the camera, so slanted rain in the wind still looks like thin streaks.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec4 sky_light_color;

uniform float streak_width = 0.010;
uniform float streak_length = 0.55;
uniform float opacity = 0.32;

varying float v_fade;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float dist = length(to_cam);
	vec3 side = normalize(cross(axis, to_cam / max(dist, 1e-3)));
	// Keep streaks at least ~1 px wide in the distance to avoid shimmering.
	float w = streak_width * max(1.0, dist * 0.08);
	vec3 wp = center + side * VERTEX.x * 2.0 * w + axis * VERTEX.y * streak_length;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_fade = smoothstep(0.4, 2.0, dist) * (1.0 - smoothstep(18.0, 30.0, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = sky_light_color.rgb * 1.3;
	ALPHA = across * along * opacity * v_fade;
}
