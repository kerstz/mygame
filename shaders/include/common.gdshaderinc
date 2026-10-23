// Shared helpers for STILLWORLD spatial shaders.
// Global uniforms are declared in project.godot [shader_globals] and driven by
// the weather system each frame.

global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wetness;
global uniform float rain_intensity;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Whole-tree sway used by bark AND foliage so leaves stay attached to
// branches. `rel` is the vertex position relative to the tree base (world
// space), `phase` a per-instance random. Displacement grows with height^2
// (a cantilever), plus a slower large-scale gust from the wind texture.
vec3 tree_sway(vec3 rel, float phase, float gust, float tree_h, float t) {
	vec2 wd = normalize(wind_direction + vec2(1e-4));
	float h = max(rel.y, 0.0) / max(tree_h, 1.0);
	float bend = h * h;
	float sway = (gust * 1.2 + 0.25) * wind_strength;
	float osc = sin(t * (0.55 + phase * 0.25) + phase * 6.283) * 0.35
		+ sin(t * (1.13 + phase * 0.4) + phase * 17.0) * 0.15;
	vec2 d = wd * (sway + osc * (0.25 + wind_strength)) * bend * 0.035 * tree_h;
	return vec3(d.x, -length(d) * 0.15 * h, d.y);
}

// Expanding rain ripple rings on a grid of random drop sites. Returns a
// world-space XZ normal perturbation. Cheap analytic version of the classic
// "rain ripples" technique: each cell holds one drop with a random phase.
vec2 rain_ripples(vec2 p, float time) {
	vec2 acc = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p * (layer == 0 ? 2.3 : 3.1) + float(layer) * 17.3;
		vec2 cell = floor(q);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				vec2 rnd = hash22(c);
				vec2 center = c + rnd;
				float t = fract(time * 0.9 + rnd.x * 7.0);
				vec2 dv = q - center;
				float d = length(dv);
				float radius = t * 1.2;
				float ring = d - radius;
				float wave = sin(ring * 30.0) * exp(-ring * ring * 60.0) * (1.0 - t) * (1.0 - t);
				acc += (d > 1e-3 ? dv / d : vec2(0.0)) * wave;
			}
		}
	}
	return acc * 0.5;
}
