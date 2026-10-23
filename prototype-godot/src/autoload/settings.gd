extends Node
## Global, persistent user settings (autoload "GameSettings").
##
## Graphics presets are plain dictionaries of individual settings, so the user
## can pick a preset and then fine-tune any value. Every consumer listens to
## `changed` and re-applies only what it needs.

signal changed(keys: PackedStringArray)

const SAVE_PATH := "user://settings.cfg"

enum Upscaler { BILINEAR, FSR1, FSR2 }

## Individual values that a preset sets. Values were chosen against a 10 ms
## budget at 3440x1440 on an RX 6900 XT class GPU; they are starting points to
## be confirmed with the in-game benchmark (see docs/PERFORMANCE.md).
const PRESETS := {
	"performance": {
		"render_scale": 0.59, "upscaler": Upscaler.FSR2,
		"view_chunks": 3, "far_chunks": 3,
		"grass_density": 0.45, "grass_distance": 55.0, "foliage_density": 0.7,
		"shadow_distance": 90.0, "shadow_quality": 1,
		"volumetric_fog": false, "ssao": false, "ssr": false, "sdfgi": false,
		"cloud_quality": 0, "rain_density": 0.5, "grass_shadows": false,
	},
	"high": {
		"render_scale": 0.77, "upscaler": Upscaler.FSR2,
		"view_chunks": 4, "far_chunks": 4,
		"grass_density": 0.75, "grass_distance": 85.0, "foliage_density": 0.9,
		"shadow_distance": 150.0, "shadow_quality": 2,
		"volumetric_fog": true, "ssao": true, "ssr": false, "sdfgi": false,
		"cloud_quality": 1, "rain_density": 0.8, "grass_shadows": false,
	},
	"ultra": {
		"render_scale": 1.0, "upscaler": Upscaler.FSR2,
		"view_chunks": 5, "far_chunks": 5,
		"grass_density": 1.0, "grass_distance": 115.0, "foliage_density": 1.0,
		"shadow_distance": 230.0, "shadow_quality": 3,
		"volumetric_fog": true, "ssao": true, "ssr": true, "sdfgi": false,
		"cloud_quality": 2, "rain_density": 1.0, "grass_shadows": false,
	},
}

## Non-graphics defaults.
const BASE := {
	"preset": "high",
	"vsync": false,
	"max_fps": 0,
	"fullscreen": true,
	"fov": 75.0,
	"mouse_sensitivity": 0.12,
	"invert_y": false,
	"head_motion": 0.35,
	"walk_speed": 1.45,
	"master_volume": 0.8,
	"ambience_volume": 0.6,
	"weather_intensity": 1.0,
	"time_of_day": "auto",  # auto (per biome) | morning | day | evening
	"world_seed": 20260,
}

var values: Dictionary = {}


func _ready() -> void:
	values = BASE.duplicate()
	values.merge(PRESETS["high"], true)
	_load()
	_apply_window()


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant, save := true) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	if key in PRESETS["high"]:
		values["preset"] = "custom"
	if key in ["vsync", "max_fps", "fullscreen"]:
		_apply_window()
	if save:
		_save()
	changed.emit(PackedStringArray([key]))


func apply_preset(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	values.merge(PRESETS[preset], true)
	values["preset"] = preset
	_save()
	changed.emit(PackedStringArray(PRESETS[preset].keys()))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(values["max_fps"])
	var want_fs: bool = values["fullscreen"]
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fs != is_fs:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in cfg.get_section_keys("settings"):
		# Ignore unknown keys from older versions; keep types of known keys.
		if values.has(k) and typeof(cfg.get_value("settings", k)) == typeof(values[k]):
			values[k] = cfg.get_value("settings", k)
