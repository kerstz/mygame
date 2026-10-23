class_name ChunkBuilder
extends RefCounted
## Builds all CPU-side data of one chunk. Runs on WorkerThreadPool threads, so
## it only produces packed arrays: no nodes, no resources, no RenderingServer
## calls. The streamer turns the result into nodes on the main thread.

const DETAIL_SIZE := 64.0
const FAR_SIZE := 512.0
## Grid cells per chunk side for each LOD of detail chunks (1, 2, 4, 8 m).
const LOD_CELLS := [64, 32, 16, 8]
const FAR_CELLS := 64

## Base densities (instances per m²) at density setting 1.0.
const GRASS_PER_M2 := 5.0
const SEEDHEADS_PER_M2 := 0.5
const FERNS_PER_M2 := 0.22


class Result:
	extends RefCounted
	var coord := Vector2i.ZERO
	var lod := 0
	var is_far := false
	var size := DETAIL_SIZE
	var origin := Vector3.ZERO
	var mesh_arrays: Array = []
	var aabb := AABB()
	## Full resolution (1 m) heights for collision, only for LOD 0.
	var collision_heights := PackedFloat32Array()
	var collision_res := 0
	## layer name -> {"buffer": PackedFloat32Array, "count": int}
	var layers := {}
	var rocks_arrays: Array = []
	var ruins_arrays: Array = []
	## Simple collision primitives: [type, Transform3D (chunk local), Vector3 params]
	var colliders: Array = []
	var gen_usec := 0


## Entry point for worker threads.
static func build(seed: int, coord: Vector2i, lod: int, is_far: bool) -> Result:
	var t0 := Time.get_ticks_usec()
	var wn := WorldNoise.new(seed)
	var r := Result.new()
	r.coord = coord
	r.lod = lod
	r.is_far = is_far
	r.size = FAR_SIZE if is_far else DETAIL_SIZE
	r.origin = Vector3(coord.x * r.size, 0.0, coord.y * r.size)
	var cells: int = FAR_CELLS if is_far else LOD_CELLS[lod]
	var grid := _sample_grid(wn, r.origin, r.size, cells)
	_build_terrain_mesh(r, grid, cells, is_far)
	if not is_far:
		if lod == 0:
			r.collision_res = cells
			r.collision_heights = grid["inner"]
		_place_vegetation(r, wn, grid, cells, seed)
	r.gen_usec = Time.get_ticks_usec() - t0
	return r


## Samples heights, biome weights and canopy on a (cells+3)² grid: one extra
## ring on each side so normals at the chunk edge use the same central
## differences as the neighbouring chunk (seamless lighting across chunks).
static func _sample_grid(wn: WorldNoise, origin: Vector3, size: float, cells: int) -> Dictionary:
	var spacing := size / cells
	var n := cells + 3
	var h := PackedFloat32Array()
	h.resize(n * n)
	var inner := PackedFloat32Array()
	inner.resize((cells + 1) * (cells + 1))
	var w := PackedVector3Array()
	w.resize((cells + 1) * (cells + 1))
	var canopy := PackedFloat32Array()
	canopy.resize((cells + 1) * (cells + 1))
	for iz in n:
		for ix in n:
			var x := origin.x + (ix - 1) * spacing
			var z := origin.z + (iz - 1) * spacing
			var bw := wn.biome_weights(x, z)
			var hv := wn.height_with(x, z, bw)
			h[iz * n + ix] = hv
			if ix >= 1 and iz >= 1 and ix <= cells + 1 and iz <= cells + 1:
				var k := (iz - 1) * (cells + 1) + (ix - 1)
				inner[k] = hv
				w[k] = bw
				canopy[k] = wn.canopy(x, z) if bw.y > 0.05 else 0.0
	return {"h": h, "inner": inner, "w": w, "canopy": canopy, "n": n, "spacing": spacing}


static func _build_terrain_mesh(r: Result, grid: Dictionary, cells: int, is_far: bool) -> void:
	var h: PackedFloat32Array = grid["h"]
	var w: PackedVector3Array = grid["w"]
	var canopy: PackedFloat32Array = grid["canopy"]
	var n: int = grid["n"]
	var sp: float = grid["spacing"]
	var side := cells + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	var miny := INF
	var maxy := -INF
	for iz in side:
		for ix in side:
			var gi := (iz + 1) * n + (ix + 1)
			var y := h[gi]
			var k := iz * side + ix
			verts[k] = Vector3(ix * sp, y, iz * sp)
			# Central-difference normal from the bordered grid.
			var dx := h[gi + 1] - h[gi - 1]
			var dz := h[gi + n] - h[gi - n]
			normals[k] = Vector3(-dx, 2.0 * sp, -dz).normalized()
			var bw := w[k]
			colors[k] = Color(bw.x, bw.y, bw.z, canopy[k] * bw.y)
			miny = minf(miny, y)
			maxy = maxf(maxy, y)
	for iz in cells:
		for ix in cells:
			var a := iz * side + ix
			var b := a + 1
			var c := a + side + 1
			var d := a + side
			# Same diagonal split as height_at_grid() so vegetation sits exactly
			# on the rendered surface. Clockwise when viewed from above.
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	# Skirts: a strip hanging down from every edge hides T-junction cracks
	# between neighbouring chunks of different LOD.
	var skirt := sp * 1.5 + 1.0
	if is_far:
		skirt = 30.0
	var edges := [
		_edge_indices(side, 0, 0, 1, 0),  # north edge, z = 0, +x
		_edge_indices(side, side - 1, 0, 0, 1),  # east edge, x = max, +z
		_edge_indices(side, side - 1, side - 1, -1, 0),  # south edge, -x
		_edge_indices(side, 0, side - 1, 0, -1),  # west edge, -z
	]
	for e in edges:
		var prev_top := -1
		var prev_bot := -1
		for idx in e:
			var v: Vector3 = verts[idx]
			verts.append(v - Vector3(0, skirt, 0))
			normals.append(normals[idx])
			colors.append(colors[idx])
			var bot := verts.size() - 1
			if prev_top >= 0:
				# Edges walk clockwise around the chunk seen from above; this
				# order makes the skirt face outward (clockwise from outside).
				indices.append_array(PackedInt32Array([prev_top, prev_bot, bot, prev_top, bot, idx]))
			prev_top = idx
			prev_bot = bot
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	r.mesh_arrays = arr
	r.aabb = AABB(Vector3(0, miny - skirt, 0), Vector3(r.size, maxy - miny + skirt + 1.0, r.size))


static func _edge_indices(side: int, x0: int, z0: int, dx: int, dz: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := x0
	var z := z0
	for i in side:
		out.append(z * side + x)
		x += dx
		z += dz
	return out


## Height on the rendered triangle surface at chunk-local (lx, lz).
static func height_at_grid(grid: Dictionary, cells: int, lx: float, lz: float) -> float:
	var inner: PackedFloat32Array = grid["inner"]
	var sp: float = grid["spacing"]
	var side := cells + 1
	var fx := clampf(lx / sp, 0.0, cells - 0.0001)
	var fz := clampf(lz / sp, 0.0, cells - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	fx -= ix
	fz -= iz
	var h00 := inner[iz * side + ix]
	var h10 := inner[iz * side + ix + 1]
	var h01 := inner[(iz + 1) * side + ix]
	var h11 := inner[(iz + 1) * side + ix + 1]
	if fx >= fz:
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## Bilinear lookup of biome weights / canopy / slope at chunk-local position.
static func _sample_attr(grid: Dictionary, cells: int, lx: float, lz: float) -> Array:
	var w: PackedVector3Array = grid["w"]
	var canopy: PackedFloat32Array = grid["canopy"]
	var h: PackedFloat32Array = grid["h"]
	var n: int = grid["n"]
	var sp: float = grid["spacing"]
	var side := cells + 1
	var ix := clampi(int(round(lx / sp)), 0, cells)
	var iz := clampi(int(round(lz / sp)), 0, cells)
	var k := iz * side + ix
	var gi := (iz + 1) * n + (ix + 1)
	var slope := Vector2(h[gi + 1] - h[gi - 1], h[gi + n] - h[gi - n]).length() / (2.0 * sp)
	return [w[k], canopy[k], slope]


# --------------------------------------------------------------------------
# Vegetation

static func _rng_for(seed: int, coord: Vector2i, layer: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, coord.x, coord.y, layer])
	return rng


## Appends one instance (3x4 transform + 4 custom floats) to a MultiMesh buffer.
static func _push(buf: PackedFloat32Array, basis: Basis, origin: Vector3, custom: Color) -> void:
	buf.append_array(PackedFloat32Array([
		basis.x.x, basis.y.x, basis.z.x, origin.x,
		basis.x.y, basis.y.y, basis.z.y, origin.y,
		basis.x.z, basis.y.z, basis.z.z, origin.z,
		custom.r, custom.g, custom.b, custom.a]))


static func _layer(r: Result, name: String, buf: PackedFloat32Array) -> void:
	if buf.size() > 0:
		r.layers[name] = {"buffer": buf, "count": buf.size() / 16}


static func _place_vegetation(r: Result, wn: WorldNoise, grid: Dictionary, cells: int, seed: int) -> void:
	var size := r.size
	var near := r.lod <= 1
	var area := size * size

	# ---- Grass and seed heads (only close chunks; they are invisible beyond). ----
	if near:
		var rng := _rng_for(seed, r.coord, 1)
		var grass := PackedFloat32Array()
		var seeds := PackedFloat32Array()
		var tries := int(area * GRASS_PER_M2)
		for i in tries:
			var lx := rng.randf() * size
			var lz := rng.randf() * size
			var a := _sample_attr(grid, cells, lx, lz)
			var bw: Vector3 = a[0]
			var can: float = a[1]
			var slope: float = a[2]
			var dens := bw.x * 1.0 + bw.y * (0.45 - can * 0.35) + bw.z * 0.03
			dens *= 1.0 - smoothstep(0.55, 0.9, slope)
			if rng.randf() > dens:
				continue
			var y := height_at_grid(grid, cells, lx, lz)
			if y < WorldNoise.WATER_LEVEL + 0.15:
				continue
			var wx := r.origin.x + lx
			var wz := r.origin.z + lz
			# Patchiness: grass height varies over tens of metres.
			var patch := wn.canopy(wx * 2.7, wz * 2.7)
			var hs := lerpf(0.65, 1.4, patch) * rng.randf_range(0.8, 1.15) * (1.0 - bw.z * 0.4)
			var ws := rng.randf_range(0.8, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = basis.rotated(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.18))
			basis = basis.scaled(Vector3(ws, hs, ws))
			var dryness := clampf(bw.z * 1.2 + (1.0 - patch) * 0.25 + rng.randf() * 0.1, 0.0, 1.0)
			# custom: r = hue variation, g = dryness, b = random keep threshold
			# (used for smooth distance thinning), a = wind phase.
			_push(grass, basis, Vector3(lx, y - 0.02, lz), Color(rng.randf(), dryness, rng.randf(), rng.randf()))
			if bw.x > 0.4 and rng.randf() < SEEDHEADS_PER_M2 / GRASS_PER_M2 * bw.x * (0.4 + patch * 1.2):
				var fb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
				_push(seeds, fb, Vector3(lx + rng.randf_range(-0.3, 0.3), y - 0.02, lz),
					Color(rng.randf(), 0.0, rng.randf(), rng.randf()))
		_layer(r, "grass", grass)
		_layer(r, "seedheads", seeds)

		# ---- Ferns: forest undergrowth, denser under the canopy. ----
		var frng := _rng_for(seed, r.coord, 2)
		var ferns := PackedFloat32Array()
		for i in int(area * FERNS_PER_M2):
			var lx := frng.randf() * size
			var lz := frng.randf() * size
			var a := _sample_attr(grid, cells, lx, lz)
			var bw: Vector3 = a[0]
			var dens: float = bw.y * (0.25 + a[1] * 0.75) * (1.0 - smoothstep(0.6, 1.0, a[2]))
			if frng.randf() > dens:
				continue
			var y := height_at_grid(grid, cells, lx, lz)
			if y < WorldNoise.WATER_LEVEL + 0.3:
				continue
			var b := Basis(Vector3.UP, frng.randf() * TAU).scaled(Vector3.ONE * frng.randf_range(0.7, 1.5))
			_push(ferns, b, Vector3(lx, y - 0.05, lz), Color(frng.randf(), 0.0, frng.randf(), frng.randf()))
		_layer(r, "fern", ferns)

	# ---- Trees on a jittered grid (natural spacing, no clumping overlap). ----
	var trng := _rng_for(seed, r.coord, 3)
	var conifers := PackedFloat32Array()
	var broadleaves := PackedFloat32Array()
	var dead := PackedFloat32Array()
	var bushes := PackedFloat32Array()
	var logs := PackedFloat32Array()
	var cell := 6.5
	var tcount := int(size / cell)
	for gz in tcount:
		for gx in tcount:
			var lx := (gx + trng.randf_range(0.1, 0.9)) * cell
			var lz := (gz + trng.randf_range(0.1, 0.9)) * cell
			var a := _sample_attr(grid, cells, lx, lz)
			var bw: Vector3 = a[0]
			var can: float = a[1]
			var slope: float = a[2]
			var roll := trng.randf()
			var wx := r.origin.x + lx
			var wz := r.origin.z + lz
			var y := height_at_grid(grid, cells, lx, lz)
			if y < WorldNoise.WATER_LEVEL + 0.5 or y > WorldNoise.SNOW_LINE + 40.0 or slope > 0.85:
				continue
			# Meadows get rare lone trees and small groves.
			var grove := wn.canopy(wx * 0.6 + 500.0, wz * 0.6)
			var p_tree := bw.y * (0.15 + can * 0.8) + bw.x * smoothstep(0.86, 0.98, grove) * 0.25
			var p_dead := bw.z * 0.004 + bw.x * 0.002
			var p_bush := bw.y * 0.25 + bw.x * smoothstep(0.6, 0.9, grove) * 0.2 + bw.z * 0.05
			if roll < p_tree:
				var hscale := trng.randf_range(0.75, 1.3) * (1.0 - slope * 0.3)
				var b := Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3.ONE * hscale)
				var conifer_bias := 0.45 + 0.5 * (wn.canopy(wx * 0.3 - 900.0, wz * 0.3) - 0.5) + bw.x * -0.3
				var custom := Color(trng.randf(), bw.y * 0.8, trng.randf(), hscale)
				var origin := Vector3(lx, y - 0.25, lz)
				if trng.randf() < conifer_bias:
					_push(conifers, b, origin, custom)
					r.colliders.append([0, Transform3D(Basis(), origin), Vector3(0.38 * hscale, 6.0, 0)])
				else:
					_push(broadleaves, b, origin, custom)
					r.colliders.append([0, Transform3D(Basis(), origin), Vector3(0.36 * hscale, 6.0, 0)])
			elif roll < p_tree + p_dead:
				var hs := trng.randf_range(0.7, 1.1)
				var origin := Vector3(lx, y - 0.2, lz)
				_push(dead, Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3.ONE * hs), origin,
					Color(trng.randf(), 0.0, trng.randf(), hs))
				r.colliders.append([0, Transform3D(Basis(), origin), Vector3(0.36 * hs, 5.0, 0)])
			elif roll < p_tree + p_dead + p_bush:
				var bs := trng.randf_range(0.6, 1.5) * (1.0 - bw.z * 0.4)
				_push(bushes, Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3(bs, bs * trng.randf_range(0.7, 1.2), bs)),
					Vector3(lx, y - 0.1, lz), Color(trng.randf(), bw.z, trng.randf(), trng.randf()))
			elif bw.y > 0.5 and trng.randf() < 0.035:
				var lb := Basis(Vector3.UP, trng.randf() * TAU)
				lb = lb.rotated(lb.x, (height_at_grid(grid, cells, lx, lz + 2.0) - height_at_grid(grid, cells, lx, lz - 2.0)) * -0.2)
				var origin := Vector3(lx, y - 0.12, lz)
				_push(logs, lb, origin, Color(trng.randf(), 1.0, trng.randf(), 1.0))
				var axis := lb * Basis(Vector3.RIGHT, PI * 0.5)
				r.colliders.append([0, Transform3D(axis, origin + Vector3(0, 0.25, 0)), Vector3(0.3, 5.6, 0)])
	_layer(r, "conifer" if r.lod <= 1 else "conifer_far", conifers)
	_layer(r, "broadleaf" if r.lod <= 1 else "broadleaf_far", broadleaves)
	_layer(r, "deadtree", dead)
	_layer(r, "bush", bushes)
	_layer(r, "log", logs)

	_place_rocks(r, wn, grid, cells, seed)
	_place_ruins(r, wn, grid, cells, seed)


## Rocks are merged into one mesh per chunk (one draw call). Vertex colour
## carries (moss, sand, hue, 1) so one material covers all biomes.
static func _place_rocks(r: Result, wn: WorldNoise, grid: Dictionary, cells: int, seed: int) -> void:
	var rng := _rng_for(seed, r.coord, 4)
	var mb := MeshBuilder.new()
	var tries := 40
	for i in tries:
		var lx := rng.randf_range(2.0, r.size - 2.0)
		var lz := rng.randf_range(2.0, r.size - 2.0)
		var a := _sample_attr(grid, cells, lx, lz)
		var bw: Vector3 = a[0]
		var slope: float = a[2]
		var p := 0.05 + bw.y * 0.12 + bw.z * 0.06 + smoothstep(0.3, 0.8, slope) * 0.5
		if rng.randf() > p:
			continue
		var y := height_at_grid(grid, cells, lx, lz)
		if y < WorldNoise.WATER_LEVEL - 1.5:
			continue
		var s := rng.randf_range(0.25, 1.0)
		s = s * s * rng.randf_range(1.5, 3.6) + 0.2
		if rng.randf() < 0.05:
			s *= 2.5  # occasional big boulder
		var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		basis = basis.scaled(Vector3.ONE * s)
		var xf := Transform3D(basis, Vector3(lx, y - s * 0.12, lz))
		var moss := clampf(bw.y * 0.9 + bw.x * 0.35, 0.0, 1.0)
		var variant: MeshBuilder = WorldAssets.rock_variants[rng.randi() % WorldAssets.rock_variants.size()]
		mb.append_transformed(variant, xf, Color(moss, bw.z, rng.randf(), 1.0))
		if s > 0.5:
			r.colliders.append([1, Transform3D(Basis(), xf.origin + Vector3(0, s * 0.1, 0)), Vector3(s * 0.85, 0, 0)])
	if mb.vertex_count() > 0:
		r.rocks_arrays = mb.to_arrays()


## Ruins: rare clusters of concrete fragments in forests. Deterministic per
## chunk; the cluster is entirely contained in its chunk.
static func _place_ruins(r: Result, wn: WorldNoise, grid: Dictionary, cells: int, seed: int) -> void:
	var rng := _rng_for(seed, r.coord, 5)
	var center_a := _sample_attr(grid, cells, r.size * 0.5, r.size * 0.5)
	var bw: Vector3 = center_a[0]
	if bw.y < 0.45 or rng.randf() > 0.22:
		return
	var mb := MeshBuilder.new()
	var cx := rng.randf_range(16.0, r.size - 16.0)
	var cz := rng.randf_range(16.0, r.size - 16.0)
	var axis := rng.randf() * TAU
	var pieces := rng.randi_range(4, 9)
	for i in pieces:
		var kind := rng.randi() % WorldAssets.ruin_variants.size()
		var along := rng.randf_range(-11.0, 11.0)
		var across := rng.randf_range(-8.0, 8.0)
		var lx := cx + cos(axis) * along - sin(axis) * across
		var lz := cz + sin(axis) * along + cos(axis) * across
		var y := height_at_grid(grid, cells, lx, lz)
		if y < WorldNoise.WATER_LEVEL:
			continue
		# Walls follow the old building's axis (with decay jitter); slabs tilt.
		var yaw := axis + (PI * 0.5 if rng.randf() < 0.4 else 0.0) + rng.randf_range(-0.08, 0.08)
		var basis := Basis(Vector3.UP, yaw)
		if kind == 2:
			basis = basis.rotated(basis.x, rng.randf_range(-0.25, 0.25))
		else:
			basis = basis.rotated(basis.z, rng.randf_range(-0.05, 0.05))
		var xf := Transform3D(basis, Vector3(lx, y - 0.1, lz))
		mb.append_transformed(WorldAssets.ruin_variants[kind], xf, Color(rng.randf(), 0, rng.randf(), 1))
		var ext: Vector3 = [Vector3(3.5, 1.7, 0.2), Vector3(0.3, 2.1, 0.3), Vector3(2.5, 0.2, 1.6), Vector3(1.75, 1.3, 0.15)][kind]
		r.colliders.append([2, Transform3D(basis, xf.origin + basis.y * ext.y * 0.8), ext])
	if mb.vertex_count() > 0:
		r.ruins_arrays = mb.to_arrays()
