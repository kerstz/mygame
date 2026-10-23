class_name WeatherProfiles
extends RefCounted
## Atmosphere / weather presets. A profile is a flat dictionary of floats and
## colours so profiles can be blended linearly by biome weight and over time.
##
## New weather types (snow, dense fog, dry wind…) are added by adding a
## profile here and mapping it in `for_biomes()`.

const BIOME := {
	# Rainy meadow (art direction: docs/ART_DIRECTION.md). Uniform luminous
	# grey overcast, no visible sun, thick fog that swallows the horizon,
	# low contrast and muted colour.
	"meadow": {
		"sun_elevation": 34.0, "sun_azimuth": 210.0, "sun_energy": 0.3,
		"sun_color": Color(0.9, 0.92, 0.95),
		"cloud_coverage": 0.97, "cloud_density": 0.05, "cloud_darkness": 0.45, "overcast": 1.0,
		"overcast_color": Color(0.66, 0.68, 0.70), "turbidity": 12.0,
		"rain": 0.6, "wind": 0.6,
		"fog_density": 0.0075, "fog_color": Color(0.60, 0.62, 0.635), "fog_height_density": 0.01,
		"vol_fog_density": 0.005, "vol_fog_albedo": Color(0.8, 0.82, 0.84), "vol_fog_anisotropy": 0.2,
		"ambient_energy": 1.2, "exposure": 1.15, "saturation": 0.8, "contrast": 0.96,
	},
	# Overgrown forest: broken clouds, sunbeams through mist, no rain.
	"forest": {
		"sun_elevation": 38.0, "sun_azimuth": 150.0, "sun_energy": 1.35,
		"sun_color": Color(1.0, 0.93, 0.80),
		"cloud_coverage": 0.55, "cloud_density": 0.045, "cloud_darkness": 0.1, "overcast": 0.2,
		"overcast_color": Color(0.6, 0.64, 0.66), "turbidity": 9.0,
		"rain": 0.0, "wind": 0.25,
		"fog_density": 0.0035, "fog_color": Color(0.55, 0.60, 0.58), "fog_height_density": 0.06,
		"vol_fog_density": 0.02, "vol_fog_albedo": Color(0.85, 0.88, 0.85), "vol_fog_anisotropy": 0.7,
		"ambient_energy": 0.8, "exposure": 1.0, "saturation": 0.95, "contrast": 1.06,
	},
	# Desert: clear, hazy, warm late-afternoon light.
	"desert": {
		"sun_elevation": 16.0, "sun_azimuth": 250.0, "sun_energy": 1.7,
		"sun_color": Color(1.0, 0.82, 0.62),
		"cloud_coverage": 0.25, "cloud_density": 0.035, "cloud_darkness": 0.0, "overcast": 0.0,
		"overcast_color": Color(0.7, 0.66, 0.6), "turbidity": 18.0,
		"rain": 0.0, "wind": 0.4,
		"fog_density": 0.0011, "fog_color": Color(0.78, 0.68, 0.56), "fog_height_density": 0.004,
		"vol_fog_density": 0.002, "vol_fog_albedo": Color(0.95, 0.85, 0.7), "vol_fog_anisotropy": 0.6,
		"ambient_energy": 0.9, "exposure": 0.95, "saturation": 1.0, "contrast": 1.05,
	},
}

## Optional time-of-day overrides (only the sun/sky keys).
const TIME_OF_DAY := {
	"morning": {"sun_elevation": 11.0, "sun_azimuth": 95.0, "sun_color": Color(1.0, 0.86, 0.7)},
	"day": {"sun_elevation": 52.0, "sun_azimuth": 170.0, "sun_color": Color(1.0, 0.97, 0.92)},
	"evening": {"sun_elevation": 7.0, "sun_azimuth": 265.0, "sun_color": Color(1.0, 0.68, 0.45)},
}


## Weighted blend of biome profiles (weights = meadow, forest, desert).
static func for_biomes(w: Vector3, time_of_day: String) -> Dictionary:
	var out := {}
	var names := ["meadow", "forest", "desert"]
	for i in 3:
		var prof: Dictionary = BIOME[names[i]]
		for k in prof:
			var v = prof[k]
			if out.has(k):
				out[k] = out[k] + v * w[i]
			else:
				out[k] = v * w[i]
	if TIME_OF_DAY.has(time_of_day):
		out.merge(TIME_OF_DAY[time_of_day], true)
	return out


## Moves `current` toward `target` with an exponential time constant.
static func approach(current: Dictionary, target: Dictionary, delta: float, tau: float) -> void:
	var k := 1.0 - exp(-delta / tau)
	for key in target:
		if not current.has(key):
			current[key] = target[key]
		else:
			current[key] = current[key] + (target[key] - current[key]) * k
