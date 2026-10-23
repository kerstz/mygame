class_name Atmosphere
extends Node3D
## Sky, sun, fog, post-processing and weather state.
##
## Every frame it blends the weather profile toward the one implied by the
## biome under the player (slowly, so walking across a biome border feels
## like the weather changing, not a switch) and pushes the result to the
## Environment, the sun, the sky shader and the global shader uniforms.

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial

var target_weights := Vector3(1, 0, 0)
var current := {}
## Rain on the ground lags behind the sky: wets in ~30 s, dries in ~2 min.
var wetness := 0.0
var _wind_angle := 0.6
var _cloud_offset := Vector2.ZERO
var _time := 0.0
var _volumetric_allowed := true
var wind_dir := Vector2(1, 0)
var wind_strength := 0.0


func _ready() -> void:
	_build_sky()
	_build_environment()
	_build_sun()
	current = WeatherProfiles.for_biomes(target_weights, GameSettings.get_value("time_of_day"))
	apply_quality()
	GameSettings.changed.connect(func(_k): apply_quality())
	_apply(0.0)


func _build_sky() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	# 3D cloud noise generated at startup (seamless, tileable). Cellular noise
	# inverted gives billowy cauliflower shapes; FBM adds structure.
	var shape := FastNoiseLite.new()
	shape.noise_type = FastNoiseLite.TYPE_CELLULAR
	shape.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	shape.frequency = 0.045
	shape.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape.fractal_octaves = 3
	shape.seed = 3
	var shape_tex := NoiseTexture3D.new()
	shape_tex.noise = shape
	shape_tex.width = 64
	shape_tex.height = 64
	shape_tex.depth = 64
	shape_tex.seamless = true
	shape_tex.invert = true
	var det := FastNoiseLite.new()
	det.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	det.frequency = 0.12
	det.fractal_octaves = 3
	det.seed = 4
	var det_tex := NoiseTexture3D.new()
	det_tex.noise = det
	det_tex.width = 32
	det_tex.height = 32
	det_tex.depth = 32
	det_tex.seamless = true
	var wm := FastNoiseLite.new()
	wm.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wm.frequency = 0.012
	wm.fractal_octaves = 4
	wm.seed = 5
	var wm_tex := NoiseTexture2D.new()
	wm_tex.noise = wm
	wm_tex.width = 256
	wm_tex.height = 256
	wm_tex.seamless = true
	wm_tex.generate_mipmaps = true
	sky_mat.set_shader_parameter("shape_noise", shape_tex)
	sky_mat.set_shader_parameter("detail_noise", det_tex)
	sky_mat.set_shader_parameter("weather_map", wm_tex)


func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256  # realtime skies require 256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX (Godot 4.4+) handles bright skies more gracefully than ACES.
	var v := Engine.get_version_info()
	if v["major"] == 4 and v["minor"] >= 4:
		env.tonemap_mode = 4 as Environment.ToneMapper  # TONE_MAPPER_AGX
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_sky_affect = 0.55
	env.fog_aerial_perspective = 0.35
	env.fog_height = WorldNoise.WATER_LEVEL + 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.1
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.6
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_use_occlusion = true
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.light_angular_distance = 0.6  # soft penumbrae (PCSS-style)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


## Applies the graphics settings that live in the environment / sun / sky.
func apply_quality() -> void:
	var s := GameSettings
	var sq: int = s.get_value("shadow_quality")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sq >= 2 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = s.get_value("shadow_distance")
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	RenderingServer.directional_shadow_atlas_set_size(4096 if sq >= 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sq])
	env.ssao_enabled = s.get_value("ssao")
	env.ssr_enabled = s.get_value("ssr")
	env.sdfgi_enabled = s.get_value("sdfgi")
	_volumetric_allowed = s.get_value("volumetric_fog")
	env.volumetric_fog_enabled = _volumetric_allowed
	var cq: int = s.get_value("cloud_quality")
	sky_mat.set_shader_parameter("cloud_steps", [22, 34, 52][cq])
	sky_mat.set_shader_parameter("light_steps", [3, 4, 5][cq])


func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	_time += delta
	var tod: String = GameSettings.get_value("time_of_day")
	var target := WeatherProfiles.for_biomes(target_weights, tod)
	var intensity: float = GameSettings.get_value("weather_intensity")
	target["rain"] = target["rain"] * intensity
	WeatherProfiles.approach(current, target, delta, 6.0)
	var c := current

	# --- Sun.
	var elev := deg_to_rad(c["sun_elevation"])
	var azim := deg_to_rad(c["sun_azimuth"])
	sun.rotation = Vector3(-elev, azim, 0.0)
	sun.light_energy = c["sun_energy"]
	# Under full overcast, shadows become very faint and diffuse.
	sun.shadow_opacity = lerpf(1.0, 0.35, c["overcast"])
	sun.light_color = c["sun_color"]

	# --- Wind: slowly wandering direction with gusts.
	_wind_angle += sin(_time * 0.013) * delta * 0.02
	var wdir := Vector2(cos(_wind_angle), sin(_wind_angle))
	var gust := 0.75 + 0.25 * sin(_time * 0.21) * sin(_time * 0.057 + 1.3)
	var wind: float = c["wind"] * gust
	wind_dir = wdir
	wind_strength = wind
	RenderingServer.global_shader_parameter_set("wind_direction", wdir)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)

	# --- Rain and ground wetness.
	var rain: float = c["rain"]
	var rate := 1.0 / 30.0 if rain > wetness else 1.0 / 120.0
	wetness = move_toward(wetness, clampf(rain * 1.3, 0.0, 1.0), delta * rate)
	RenderingServer.global_shader_parameter_set("rain_intensity", rain)
	RenderingServer.global_shader_parameter_set("wetness", wetness)

	# --- Sky.
	_cloud_offset += wdir * (6.0 + wind * 14.0) * delta
	sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
	for k in ["cloud_coverage", "cloud_density", "cloud_darkness", "overcast", "overcast_color", "turbidity"]:
		sky_mat.set_shader_parameter(k, c[k])

	# --- Fog & ambient.
	var fog_col: Color = c["fog_color"]
	# Fog takes on the light: darker under heavy overcast, warmer at sunset.
	var light_tint: Color = c["sun_color"].lerp(Color.WHITE, 0.6)
	fog_col = fog_col * light_tint * clampf(0.6 + c["sun_energy"] * 0.3, 0.5, 1.2)
	# Overcast: fog colour = sky horizon luminance (see sky.gdshader grey dome),
	# so terrain dissolves into the sky with no visible horizon line.
	var horizon: Color = c["overcast_color"] * 1.03
	fog_col = fog_col.lerp(horizon, c["overcast"])
	env.fog_light_color = fog_col
	env.fog_density = c["fog_density"] * (1.0 + rain * 0.35)
	env.fog_height_density = c["fog_height_density"]
	env.fog_sun_scatter = 0.15 * (1.0 - c["overcast"])
	env.volumetric_fog_enabled = _volumetric_allowed and c["vol_fog_density"] > 0.001
	env.volumetric_fog_density = c["vol_fog_density"]
	env.volumetric_fog_albedo = c["vol_fog_albedo"]
	env.volumetric_fog_anisotropy = c["vol_fog_anisotropy"]
	env.ambient_light_energy = c["ambient_energy"]
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_exposure = c["exposure"]
	env.adjustment_saturation = c["saturation"]
	env.adjustment_contrast = c["contrast"]
	RenderingServer.global_shader_parameter_set("sky_light_color", fog_col)


func current_rain() -> float:
	return current.get("rain", 0.0)
