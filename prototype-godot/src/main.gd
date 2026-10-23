extends Node3D
## Entry point: wires together the independent systems.
##
##   WorldStreamer  terrain + vegetation chunks (threaded)
##   Atmosphere     sky, sun, fog, weather state, global shader uniforms
##   RainSystem     rain particles     WaterPlane    lakes
##   AmbientAudio   rain/wind ambience  Player        first-person walker
##   PauseMenu      settings UI         PerfOverlay   F3 developer stats
##
## Command line (after `--`):
##   --benchmark           scripted walk through 3 biomes, prints/saves stats
##   --screenshot=PATH     capture one frame once the world is loaded, quit
##   --biome=meadow|forest|desert  --preset=ultra|high|performance
##   --look=YAW,PITCH (degrees)    --seed=N    --frames=N (settle frames)

var world: WorldStreamer
var atmosphere: Atmosphere
var player: Player
var rain: RainSystem
var water: WaterPlane
var audio: AmbientAudio
var menu: PauseMenu
var overlay: PerfOverlay

var _fade: ColorRect
var _biome_timer := 0.0
var _args := {}
var _paused := false


func _ready() -> void:
	_parse_args()
	if _args.has("preset"):
		GameSettings.apply_preset(_args["preset"])
	var seed: int = int(_args.get("seed", GameSettings.get_value("world_seed")))

	WorldAssets.init()

	atmosphere = Atmosphere.new()
	add_child(atmosphere)

	world = WorldStreamer.new()
	world.seed = seed
	add_child(world)

	player = Player.new()
	player.world = world
	add_child(player)
	world.target = player

	water = WaterPlane.new()
	water.camera = player.camera
	add_child(water)

	rain = RainSystem.new()
	rain.camera = player.camera
	add_child(rain)

	audio = AmbientAudio.new()
	add_child(audio)

	menu = PauseMenu.new()
	menu.resume_requested.connect(_set_paused.bind(false))
	menu.quit_requested.connect(func(): get_tree().quit())
	menu.teleport_requested.connect(_teleport_to_biome)
	add_child(menu)

	overlay = PerfOverlay.new()
	overlay.world = world
	overlay.atmosphere = atmosphere
	overlay.player = player
	add_child(overlay)

	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 5
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	add_child(fade_layer)

	_apply_render_settings()
	GameSettings.changed.connect(func(_k): _apply_render_settings())

	var biome := WorldNoise.BIOME_NAMES.find(_args.get("biome", "meadow"))
	_spawn(maxi(biome, 0), Vector2.ZERO)
	if _args.has("look"):
		var parts: PackedStringArray = str(_args["look"]).split(",")
		player.set_look(deg_to_rad(float(parts[0])), deg_to_rad(float(parts[1])))

	if _args.has("benchmark"):
		var bench := Benchmark.new()
		bench.main = self
		add_child(bench)
	elif _args.has("screenshot"):
		_capture_screenshot.call_deferred(str(_args["screenshot"]), int(_args.get("frames", 90)))
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = true


func _apply_render_settings() -> void:
	var vp := get_viewport()
	var up: int = GameSettings.get_value("upscaler")
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	if up == GameSettings.Upscaler.FSR2 and forward_plus:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.use_taa = false
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if up == GameSettings.Upscaler.FSR1 and forward_plus \
			else Viewport.SCALING_3D_MODE_BILINEAR
		vp.use_taa = forward_plus
	vp.scaling_3d_scale = GameSettings.get_value("render_scale")
	vp.fsr_sharpness = 0.35
	RenderingServer.global_shader_parameter_set("grass_view_distance", GameSettings.get_value("grass_distance"))
	RenderingServer.global_shader_parameter_set("grass_density_scale", GameSettings.get_value("grass_density"))
	world.configure(GameSettings.get_value("view_chunks"), GameSettings.get_value("far_chunks"),
		GameSettings.get_value("grass_density"), GameSettings.get_value("grass_shadows"))


func _spawn(biome: int, near: Vector2) -> void:
	var p := world.noise.find_spawn(biome, near)
	var h := world.noise.height(p.x, p.y)
	# Face along the slope's downhill direction: usually the more open view.
	var gx := world.noise.height(p.x + 10.0, p.y) - world.noise.height(p.x - 10.0, p.y)
	var gz := world.noise.height(p.x, p.y + 10.0) - world.noise.height(p.x, p.y - 10.0)
	var yaw := atan2(gx, gz) if absf(gx) + absf(gz) > 0.2 else 0.6
	player.teleport(Vector3(p.x, h + 0.3, p.y), yaw)
	atmosphere.target_weights = world.noise.biome_weights(p.x, p.y)
	# Jump the weather straight to the new region (we fade through black).
	atmosphere.current = WeatherProfiles.for_biomes(atmosphere.target_weights,
		GameSettings.get_value("time_of_day"))
	atmosphere.wetness = clampf(atmosphere.current["rain"] * 1.3, 0.0, 1.0)
	_fade.color.a = 1.0


func _teleport_to_biome(biome: int) -> void:
	_set_paused(false)
	var p := player.global_position
	_spawn(biome, Vector2(p.x, p.z))


func _set_paused(on: bool) -> void:
	_paused = on
	get_tree().paused = on
	if on:
		menu.open()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		menu.close()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not _paused)
	elif event is InputEventMouseButton and event.pressed and not _paused:
		# Re-capture after the window lost focus (alt-tab etc.).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _paused and not _args.has("benchmark") \
			and not _args.has("screenshot"):
		_set_paused(true)


func _process(delta: float) -> void:
	_biome_timer -= delta
	var p := player.global_position
	if _biome_timer <= 0.0:
		_biome_timer = 0.25
		atmosphere.target_weights = world.noise.biome_weights(p.x, p.z)
	var wind_dir := atmosphere.wind_dir
	var wind := atmosphere.wind_strength
	var r := atmosphere.current_rain()
	rain.update_rain(r, wind_dir * wind)
	audio.update_levels(r, wind, delta)
	# Fade in once the ground is solid under the player.
	var target_a := 1.0 if player.frozen else 0.0
	_fade.color.a = move_toward(_fade.color.a, target_a, delta * 0.8)
	_fade.visible = _fade.color.a > 0.001


func _capture_screenshot(path: String, settle_frames: int) -> void:
	# Wait for the surrounding area (and the far horizon) to stream in.
	var t0 := Time.get_ticks_msec()
	while (not world.is_area_loaded() or world.pending_count() > 0 or player.frozen) \
			and Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
	_fade.color.a = 0.0
	_fade.visible = false
	for i in settle_frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("STILLWORLD screenshot saved: ", path, " after ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	get_tree().quit()
