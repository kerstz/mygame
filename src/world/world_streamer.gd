class_name WorldStreamer
extends Node3D
## Streams terrain chunks around a target node.
##
## * Detail chunks (64 m) carry vegetation, and collision near the player.
##   Their mesh resolution drops with distance (LOD rings).
## * Far chunks (512 m, 8 m grid) form the horizon. Inside the area already
##   covered by detail chunks their vertices are sunk out of sight by the
##   terrain shader (global uniform `detail_rect`), so the two layers never
##   overlap visibly.
##
## Generation runs on WorkerThreadPool; the main thread only uploads results,
## within a per-frame time budget, so streaming never stalls rendering.

signal stats_changed

var seed := 1
var target: Node3D
var view_chunks := 4
var far_chunks := 4
var grass_density := 1.0
var grass_shadows := false
## Main-thread time allowed for turning results into nodes, per frame.
var finalize_budget_usec := 2500

var noise: WorldNoise
var chunks := {}  # Vector2i -> TerrainChunk
var far := {}  # Vector2i -> TerrainChunk
var last_gen_usec := 0
var total_generated := 0

var _pending := {}  # "d|x|y" or "f|x|y" -> {"task": id, "lod": int}
var _results: Array[ChunkBuilder.Result] = []
var _mutex := Mutex.new()
var _max_tasks := 2
var _center := Vector2i(1 << 30, 0)
var _far_center := Vector2i(1 << 30, 0)
var _rect_center := Vector2i(1 << 30, 0)
var _dirty := true
var _space: RID


func _ready() -> void:
	noise = WorldNoise.new(seed)
	_max_tasks = clampi(OS.get_processor_count() - 2, 1, 10)
	_space = get_world_3d().space
	RenderingServer.global_shader_parameter_set("detail_rect", Vector4.ZERO)


func configure(p_view: int, p_far: int, p_grass_density: float, p_grass_shadows: bool) -> void:
	view_chunks = p_view
	far_chunks = p_far
	grass_density = p_grass_density
	grass_shadows = p_grass_shadows
	for c in chunks.values():
		c.apply_grass_density(grass_density, grass_shadows)
	_rect_center = Vector2i(1 << 30, 0)
	_dirty = true


static func chunk_of(p: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


func lod_for(d: int) -> int:
	if d <= 1:
		return 0
	if d >= view_chunks:
		return 3  # outer ring matches the far terrain's 8 m grid exactly
	return mini(d - 1, 2)


func _process(_delta: float) -> void:
	if target == null:
		return
	var p := target.global_position
	var c := chunk_of(p, ChunkBuilder.DETAIL_SIZE)
	var fc := chunk_of(p, ChunkBuilder.FAR_SIZE)
	if c != _center or fc != _far_center:
		_center = c
		_far_center = fc
		_dirty = true
	_collect_results()
	if _dirty or _pending.size() < _max_tasks:
		_schedule()
	_update_collision()
	_update_detail_rect()


func _schedule() -> void:
	_dirty = false
	# Unload chunks outside the hysteresis band (radius + 1).
	for k in chunks.keys():
		if _cheb(k, _center) > view_chunks + 1:
			chunks[k].queue_free()
			chunks.erase(k)
	for k in far.keys():
		if _cheb(k, _far_center) > far_chunks + 1:
			far[k].queue_free()
			far.erase(k)

	# Collect missing / wrong-LOD chunks, nearest first. Detail chunks always
	# take priority over far chunks.
	var wanted: Array = []
	for dz in range(-view_chunks, view_chunks + 1):
		for dx in range(-view_chunks, view_chunks + 1):
			var k := _center + Vector2i(dx, dz)
			var d := maxi(absi(dx), absi(dz))
			var lod := lod_for(d)
			var existing: TerrainChunk = chunks.get(k)
			if existing != null and existing.lod == lod:
				continue
			var key := "d|%d|%d" % [k.x, k.y]
			if _pending.has(key):
				continue  # a stale-LOD result is discarded on arrival, then rescheduled
			wanted.append([dx * dx + dz * dz, k, lod, false, key])
	var far_wanted: Array = []
	for dz in range(-far_chunks, far_chunks + 1):
		for dx in range(-far_chunks, far_chunks + 1):
			var k := _far_center + Vector2i(dx, dz)
			if far.has(k):
				continue
			var key := "f|%d|%d" % [k.x, k.y]
			if _pending.has(key):
				continue
			far_wanted.append([100000 + dx * dx + dz * dz, k, 0, true, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	far_wanted.sort_custom(func(a, b): return a[0] < b[0])
	wanted.append_array(far_wanted)
	for w in wanted:
		if _pending.size() >= _max_tasks:
			_dirty = true  # more work remains
			break
		var task := WorkerThreadPool.add_task(_build_task.bind(w[1], w[2], w[3]), false, "chunk")
		_pending[w[4]] = {"task": task, "lod": w[2]}


func _build_task(coord: Vector2i, lod: int, is_far: bool) -> void:
	var r := ChunkBuilder.build(seed, coord, lod, is_far)
	_mutex.lock()
	_results.append(r)
	_mutex.unlock()


func _collect_results() -> void:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < finalize_budget_usec:
		_mutex.lock()
		var r: ChunkBuilder.Result = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if r == null:
			return
		var key := "%s|%d|%d" % ["f" if r.is_far else "d", r.coord.x, r.coord.y]
		if _pending.has(key):
			# The task has finished; this releases its pool slot immediately.
			WorkerThreadPool.wait_for_task_completion(_pending[key]["task"])
			var expected_lod: int = _pending[key]["lod"]
			_pending.erase(key)
			if expected_lod != r.lod:
				continue
		_dirty = true
		last_gen_usec = r.gen_usec
		total_generated += 1
		if r.is_far:
			if _cheb(r.coord, _far_center) > far_chunks + 1:
				continue
			var fchunk := TerrainChunk.new()
			fchunk.setup(r)
			add_child(fchunk)
			if far.has(r.coord):
				far[r.coord].queue_free()
			far[r.coord] = fchunk
		else:
			var d := _cheb(r.coord, _center)
			if d > view_chunks + 1:
				continue
			var chunk := TerrainChunk.new()
			chunk.setup(r)
			chunk.apply_grass_density(grass_density, grass_shadows)
			add_child(chunk)
			# Replace a previous LOD only once the new one exists: no holes.
			if chunks.has(r.coord):
				chunks[r.coord].queue_free()
			chunks[r.coord] = chunk
	stats_changed.emit()


func _update_collision() -> void:
	for k in chunks:
		var ch: TerrainChunk = chunks[k]
		ch.set_collision(_cheb(k, _center) <= 1 and ch.lod == 0, _space)


## Publishes the square fully covered by detail chunks, once complete.
func _update_detail_rect() -> void:
	if _rect_center == _center:
		return
	for dz in range(-view_chunks, view_chunks + 1):
		for dx in range(-view_chunks, view_chunks + 1):
			if not chunks.has(_center + Vector2i(dx, dz)):
				return
	_rect_center = _center
	var s := ChunkBuilder.DETAIL_SIZE
	RenderingServer.global_shader_parameter_set("detail_rect", Vector4(
		(_center.x - view_chunks) * s, (_center.y - view_chunks) * s,
		(_center.x + view_chunks + 1) * s, (_center.y + view_chunks + 1) * s))


## True once the ground under `p` has collision (used before spawning).
func is_ground_ready(p: Vector3) -> bool:
	var ch: TerrainChunk = chunks.get(chunk_of(p, ChunkBuilder.DETAIL_SIZE))
	return ch != null and ch.has_collision()


func is_area_loaded() -> bool:
	return _rect_center == _center


func pending_count() -> int:
	return _pending.size()


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _exit_tree() -> void:
	for key in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[key]["task"])
	_pending.clear()
