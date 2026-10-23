// Sky: analytic atmosphere + raymarched volumetric clouds.
//
// Techniques adapted (re-implemented, MIT-compatible) from:
//  * clayjohn/godot-volumetric-cloud-demo (MIT) and A. Schneider, "The
//    Real-Time Volumetric Cloudscapes of Horizon Zero Dawn" (SIGGRAPH 2015):
//    height gradient + coverage remapping, Beer-powder lighting, multiple
//    Henyey-Greenstein lobes.
//  * Preetham/three.js "Sky" analytic scattering (MIT) for the atmosphere.
//
// Cost control: clouds are marched in the half resolution pass only, with a
// per-preset step count, early exit at full opacity, and light marching only
// inside clouds. The radiance cubemap uses a much cheaper march.
shader_type sky;
render_mode use_half_res_pass;

uniform sampler3D shape_noise : filter_linear_mipmap, repeat_enable;
uniform sampler3D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weather_map : filter_linear_mipmap, repeat_enable;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_density : hint_range(0.0, 0.2) = 0.045;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cloud_offset = vec2(0.0);  // accumulated wind drift, metres
uniform int cloud_steps = 32;
uniform int light_steps = 4;

uniform float rayleigh : hint_range(0.0, 8.0) = 2.0;
uniform vec3 rayleigh_color : source_color = vec3(0.26, 0.41, 0.58);
uniform float mie : hint_range(0.0, 0.1) = 0.005;
uniform float mie_eccentricity : hint_range(-1.0, 1.0) = 0.8;
uniform vec3 mie_color : source_color = vec3(0.63, 0.77, 0.92);
uniform float turbidity : hint_range(0.0, 100.0) = 10.0;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;  // flattens/greys the sky dome
uniform vec3 overcast_color : source_color = vec3(0.55, 0.58, 0.62);
uniform vec3 ground_color : source_color = vec3(0.12, 0.12, 0.11);
uniform float sky_exposure = 0.12;
uniform float sun_disk_scale = 1.0;

const float EARTH_R = 6360000.0;
const float CLOUD_BOTTOM = 1400.0;
const float CLOUD_TOP = 3600.0;
const float SUN_ENERGY = 1000.0;
const float SOL_SIZE = 0.00872663806;

float hg(float c, float g) {
	return 0.0795774715 * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
}

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) / (b - a) * (d - c);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 atmosphere(vec3 dir, vec3 sun_dir, float sun_energy_scale) {
	float zenith_cos = clamp(sun_dir.y, -1.0, 1.0);
	float sun_energy = max(0.0, 1.0 - exp(-((PI * 0.5) - acos(zenith_cos)))) * SUN_ENERGY * sun_energy_scale;
	float sun_fade = 1.0 - clamp(1.0 - exp(sun_dir.y), 0.0, 1.0);
	vec3 rb = (rayleigh - (1.0 - sun_fade)) * rayleigh_color * 0.0001;
	vec3 mb = turbidity * mie * mie_color * 0.000434;
	float zenith = acos(max(0.0, dir.y));
	float mass = 1.0 / (cos(zenith) + 0.15 * pow(93.885 - degrees(zenith), -1.253));
	vec3 extinction = exp(-(rb * 8.4e3 * mass + mb * 1.25e3 * mass));
	float ct = dot(dir, sun_dir);
	vec3 brt = rb * (3.0 / (16.0 * PI)) * (1.0 + pow(ct * 0.5 + 0.5, 2.0));
	vec3 bmt = mb * hg(ct, mie_eccentricity);
	vec3 lin = pow(sun_energy * ((brt + bmt) / (rb + mb)) * (1.0 - extinction), vec3(1.5));
	lin *= mix(vec3(1.0), pow(sun_energy * ((brt + bmt) / (rb + mb)) * extinction, vec3(0.5)),
		clamp(pow(1.0 - zenith_cos, 5.0), 0.0, 1.0));
	vec3 col = lin * 0.04;
	col = pow(col, vec3(1.0 / (1.2 + 1.2 * sun_fade)));
	col *= sky_exposure;
	// Overcast: the dome becomes a soft grey gradient lit from above.
	vec3 grey = overcast_color * 1.6 * (0.6 + 0.4 * smoothstep(-0.1, 0.7, dir.y)) * clamp(sun_dir.y * 2.0 + 0.4, 0.15, 1.0);
	col = mix(col, grey, overcast);
	col = mix(ground_color * (0.3 + 0.7 * clamp(sun_dir.y + 0.2, 0.0, 1.0)), col, smoothstep(-0.08, 0.02, dir.y));
	return col;
}

float cloud_density_at(vec3 p, float hf, bool cheap) {
	vec2 wp = (p.xz + cloud_offset) * 0.000035;
	float weather = texture(weather_map, wp).r;
	float cov = clamp(weather * 0.9 + cloud_coverage * 1.15 - 0.55, 0.0, 1.0);
	if (cov <= 0.0) {
		return 0.0;
	}
	vec3 sp = vec3(p.x + cloud_offset.x, p.y, p.z + cloud_offset.y) * 0.00011;
	float shape = textureLod(shape_noise, sp, 0.0).r;
	// Cumulus-like vertical profile; taller where coverage is high.
	float grad = smoothstep(0.0, 0.12, hf) * (1.0 - smoothstep(0.35 + cov * 0.45, 1.0, hf));
	float base = remap(shape * grad, 1.0 - cov, 1.0, 0.0, 1.0);
	base = clamp(base, 0.0, 1.0) * cov;
	if (base <= 0.0 || cheap) {
		return base;
	}
	// Erode edges with a smaller, faster-moving detail noise.
	vec3 dp = sp * 5.3 + vec3(0.0, TIME * 0.004, 0.0);
	float detail = textureLod(detail_noise, dp, 0.0).r;
	base = remap(base, detail * 0.32 * (1.0 - hf * 0.5), 1.0, 0.0, 1.0);
	return clamp(base, 0.0, 1.0);
}

// Returns (in-scattered light, transmittance).
vec4 march_clouds(vec3 dir, vec3 sun_dir, vec3 sun_col, vec3 amb_top, vec3 amb_bottom, int steps, int lsteps, bool cheap, vec2 seed_uv) {
	// Ray/shell intersections on a curved planet so clouds meet the horizon.
	vec3 o = vec3(0.0, EARTH_R, 0.0);
	float b = dot(o, dir);
	float c0 = dot(o, o) - pow(EARTH_R + CLOUD_BOTTOM, 2.0);
	float c1 = dot(o, o) - pow(EARTH_R + CLOUD_TOP, 2.0);
	float t0 = -b + sqrt(b * b - c0);
	float t1 = -b + sqrt(b * b - c1);
	float len = min(t1 - t0, 9000.0);
	float ds = len / float(steps);
	float jitter = hash13(vec3(seed_uv * 1000.0, fract(TIME) * 37.0));
	float trans = 1.0;
	vec3 light = vec3(0.0);
	float cos_t = dot(dir, sun_dir);
	float phase = max(hg(cos_t, 0.6) * 0.7 + hg(cos_t, -0.2) * 0.3, 0.08);
	float lds = (CLOUD_TOP - CLOUD_BOTTOM) / float(lsteps * 3);
	for (int i = 0; i < steps; i++) {
		float t = t0 + (float(i) + jitter) * ds;
		vec3 p = o + dir * t;
		float alt = length(p) - EARTH_R;
		float hf = clamp((alt - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
		vec3 wp = vec3(p.x, alt, p.z);
		float d = cloud_density_at(wp, hf, cheap) * cloud_density;
		if (d > 0.0) {
			// Light march toward the sun.
			float od = 0.0;
			vec3 lp = wp;
			for (int j = 0; j < lsteps; j++) {
				lp += sun_dir * lds * float(j + 1);
				float lhf = clamp((lp.y - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM), 0.0, 1.0);
				od += cloud_density_at(lp, lhf, true) * cloud_density * lds * float(j + 1);
			}
			float beer = max(exp(-od), exp(-od * 0.25) * 0.7);
			float powder = 1.0 - exp(-d * ds * 2.0);
			vec3 amb = mix(amb_bottom, amb_top, hf) * (1.0 - cloud_darkness * 0.6);
			vec3 s = (sun_col * beer * phase * mix(1.0, powder * 2.0, 0.5) * (1.0 - cloud_darkness * 0.85) + amb) * d;
			float dt = exp(-d * ds);
			// Energy-conserving integration (Hillaire 2015).
			light += trans * (s - s * dt) / max(d, 1e-5);
			trans *= dt;
			if (trans < 0.02) {
				break;
			}
		}
	}
	// Fade distant clouds into the horizon haze.
	float fade = exp(-max(t0 - 2000.0, 0.0) * 0.000045);
	return vec4(light * fade, mix(1.0, trans, fade));
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float sun_scale = LIGHT0_ENABLED ? LIGHT0_ENERGY : 0.0;
	if (AT_HALF_RES_PASS) {
		if (dir.y > 0.0) {
			vec3 bg_top = atmosphere(vec3(0.0, 1.0, 0.0), sun_dir, sun_scale);
			vec3 bg_hor = atmosphere(normalize(vec3(sun_dir.x, 0.05, sun_dir.z)), sun_dir, sun_scale);
			vec3 sun_col = LIGHT0_COLOR * sun_scale * 1.6 * clamp(sun_dir.y * 3.0 + 0.2, 0.0, 1.0);
			vec3 amb_top = bg_top * 0.9 + vec3(0.06) * (1.0 - overcast);
			vec3 amb_bot = mix(bg_hor * 0.35, ground_color * 0.6, 0.4);
			int steps = AT_CUBEMAP_PASS ? 12 : int(mix(float(cloud_steps), float(cloud_steps) * 0.6, dir.y));
			int ls = AT_CUBEMAP_PASS ? 2 : light_steps;
			vec4 c = march_clouds(dir, sun_dir, sun_col, amb_top, amb_bot, steps, ls, AT_CUBEMAP_PASS, SCREEN_UV);
			COLOR = c.rgb;
			ALPHA = c.a;
		} else {
			COLOR = vec3(0.0);
			ALPHA = 1.0;
		}
	} else {
		vec3 bg = atmosphere(dir, sun_dir, sun_scale);
		float trans = dir.y > 0.0 ? HALF_RES_COLOR.a : 1.0;
		vec3 clouds = dir.y > 0.0 ? HALF_RES_COLOR.rgb : vec3(0.0);
		// Sun disk, hidden by clouds and by overcast haze.
		float ct = dot(dir, sun_dir);
		float disk = smoothstep(cos(SOL_SIZE * sun_disk_scale), cos(SOL_SIZE * sun_disk_scale * 0.5), ct);
		vec3 sun = LIGHT0_COLOR * sun_scale * disk * 40.0 * (1.0 - overcast) * trans;
		// Under full overcast the cloud deck is one uniform luminous layer:
		// individual cloud shapes fade into the grey dome.
		COLOR = mix(bg * trans + clouds, bg, overcast * 0.8) + sun;
	}
}
