class_name Benchmark
extends Node
## Scripted, repeatable benchmark: for each biome, teleport, wait for the
## world to stream in, then walk forward for a fixed time while recording
## per-frame CPU/GPU timings. Results are printed and saved as JSON to
## user://benchmark_<preset>.json. Run with:
##   godot --path . -- --benchmark --preset=ultra

const WARMUP_SEC := 3.0
const MEASURE_SEC := 15.0

var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var results := {
		"engine": Engine.get_version_info()["string"],
		"adapter": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"render_scale": GameSettings.get_value("render_scale"),
		"preset": GameSettings.get_value("preset"),
		"biomes": {},
	}
	for b in WorldNoise.BIOME_NAMES.size():
		main._teleport_to_biome(b)
		var t0 := Time.get_ticks_msec()
		while (main.player.frozen or not main.world.is_area_loaded()) and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
		var load_sec := (Time.get_ticks_msec() - t0) / 1000.0
		main.player.auto_walk = Vector2(0, -1)
		await get_tree().create_timer(WARMUP_SEC).timeout
		var frames := PackedFloat32Array()
		var gpu := PackedFloat32Array()
		var cpu := PackedFloat32Array()
		var draws := 0.0
		var prims := 0.0
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec() - start < MEASURE_SEC * 1e6:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		main.player.auto_walk = Vector2.ZERO
		var n := frames.size()
		var sorted := frames.duplicate()
		sorted.sort()
		var r := {
			"load_seconds": load_sec,
			"frames": n,
			"avg_ms": _avg(frames),
			"avg_fps": 1000.0 / maxf(_avg(frames), 0.001),
			"p99_ms": sorted[int(n * 0.99)] if n > 0 else 0.0,
			"max_ms": sorted[n - 1] if n > 0 else 0.0,
			"gpu_avg_ms": _avg(gpu),
			"cpu_render_avg_ms": _avg(cpu),
			"draw_calls_avg": draws / maxi(n, 1),
			"primitives_avg_m": prims / maxi(n, 1) / 1.0e6,
			"vram_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			"chunks": main.world.chunks.size(),
		}
		results["biomes"][WorldNoise.BIOME_NAMES[b]] = r
		print("[benchmark] %s: %.1f fps avg (%.2f ms), p99 %.2f ms, GPU %.2f ms, CPU %.2f ms, %d draws, %.2f M prims" % [
			WorldNoise.BIOME_NAMES[b], r["avg_fps"], r["avg_ms"], r["p99_ms"], r["gpu_avg_ms"],
			r["cpu_render_avg_ms"], r["draw_calls_avg"], r["primitives_avg_m"]])
	var path := "user://benchmark_%s.json" % GameSettings.get_value("preset")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("[benchmark] saved ", ProjectSettings.globalize_path(path))
	get_tree().quit()


static func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()
