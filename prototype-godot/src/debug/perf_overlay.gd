class_name PerfOverlay
extends CanvasLayer
## Developer overlay (F3, hidden by default — gameplay has no HUD).
## Shows CPU and GPU frame times separately, as measured by the engine, plus
## draw calls, primitives, VRAM and streaming state.

var world: WorldStreamer
var atmosphere: Atmosphere
var player: Node3D
var _label: Label
var _accum := 0.0
var _frames := 0
var _worst := 0.0


func _ready() -> void:
	layer = 20
	visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perf_overlay"):
		visible = not visible


func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if not visible or _accum < 0.25:
		return
	var vp := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var p := player.global_position if player else Vector3.ZERO
	var w := world.noise.biome_weights(p.x, p.z) if world else Vector3.ZERO
	var lines := PackedStringArray([
		"%d FPS   frame %.2f ms (worst %.1f)" % [_frames / _accum, 1000.0 * _accum / _frames, _worst * 1000.0],
		"CPU render %.2f ms   GPU %.2f ms   process %.2f ms" % [cpu, gpu,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0],
		"draw calls %d   objects %d   primitives %.2f M" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6],
		"VRAM %.0f MB (textures %.0f MB)   RAM %.0f MB" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
			OS.get_static_memory_usage() / 1048576.0],
		"chunks %d + far %d   pending %d   last gen %.1f ms" % [
			world.chunks.size() if world else 0, world.far.size() if world else 0,
			world.pending_count() if world else 0, (world.last_gen_usec if world else 0) / 1000.0],
		"pos %.0f %.0f %.0f   biome M%.2f F%.2f D%.2f   rain %.2f" % [p.x, p.y, p.z, w.x, w.y, w.z,
			atmosphere.current_rain() if atmosphere else 0.0],
		"%s · %s · %s" % [Engine.get_version_info()["string"], RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method()],
	])
	_label.text = "\n".join(lines)
	_accum = 0.0
	_frames = 0
	_worst = 0.0
