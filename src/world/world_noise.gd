class_name WorldNoise
extends RefCounted
## Deterministic world functions: terrain height and biome weights.
##
## Everything here is a pure function of (seed, x, z) so any chunk can be
## generated in any order, on any thread, and still match its neighbours
## exactly along shared edges (no seams by construction).
##
## Each worker thread builds its own WorldNoise instance; FastNoiseLite is
## cheap to construct and this avoids sharing mutable state between threads.

const WATER_LEVEL := -4.0
const SNOW_LINE := 230.0

enum Biome { MEADOW, FOREST, DESERT }
const BIOME_NAMES := ["meadow", "forest", "desert"]

var seed: int
var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _micro: FastNoiseLite
var _ridge: FastNoiseLite
var _mountain_mask: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _dunes: FastNoiseLite
var _dunes_large: FastNoiseLite
var _canopy: FastNoiseLite

# Dune crests run perpendicular to the dominant desert wind.
const _DUNE_ANGLE := 0.62
var _dune_cos := cos(_DUNE_ANGLE)
var _dune_sin := sin(_DUNE_ANGLE)


func _init(p_seed: int) -> void:
	seed = p_seed
	_continent = _make(1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 6000.0, 3)
	_hills = _make(2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 650.0, 5)
	# Domain warping breaks the "blobby" look of plain fBm hills.
	_hills.domain_warp_enabled = true
	_hills.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_hills.domain_warp_amplitude = 140.0
	_hills.domain_warp_frequency = 1.0 / 900.0
	_hills.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	_hills.domain_warp_fractal_octaves = 2
	_detail = _make(3, FastNoiseLite.TYPE_SIMPLEX, 1.0 / 70.0, 3)
	_micro = _make(4, FastNoiseLite.TYPE_SIMPLEX, 1.0 / 9.0, 2)
	_ridge = _make(5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 1900.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	_mountain_mask = _make(6, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 7000.0, 2)
	_temperature = _make(7, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 5200.0, 3)
	_temperature.domain_warp_enabled = true
	_temperature.domain_warp_amplitude = 900.0
	_temperature.domain_warp_frequency = 1.0 / 3000.0
	_moisture = _make(8, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 3900.0, 3)
	_dunes = _make(9, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 90.0, 3, FastNoiseLite.FRACTAL_RIDGED)
	_dunes_large = _make(10, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 420.0, 2, FastNoiseLite.FRACTAL_RIDGED)
	_canopy = _make(11, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 160.0, 2)


func _make(offset: int, type: int, freq: float, octaves: int,
		fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed * 31 + offset * 7919
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


## Returns Vector3(meadow, forest, desert) weights, summing to 1.
## Biomes come from two very low frequency climate fields so regions are
## kilometres wide and transitions span a few hundred metres.
func biome_weights(x: float, z: float) -> Vector3:
	var t := _temperature.get_noise_2d(x, z)
	var m := _moisture.get_noise_2d(x, z)
	var desert := _smooth(0.06, 0.30, t - m * 0.55)
	var forest := _smooth(-0.02, 0.24, m - maxf(t, 0.0) * 0.6) * (1.0 - desert)
	var meadow := maxf(0.0, 1.0 - desert - forest)
	return Vector3(meadow, forest, desert)


## Terrain height in metres. `w` must be biome_weights(x, z).
func height_with(x: float, z: float, w: Vector3) -> float:
	var c := _continent.get_noise_2d(x, z)
	var hills := _hills.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)
	var micro := _micro.get_noise_2d(x, z)
	var h := 6.0 + c * 26.0

	# Mountains: ridged noise raised to a power gives sharp crests and wide
	# valleys; a separate mask keeps ranges sparse so most land is walkable.
	var mask := _smooth(0.12, 0.55, _mountain_mask.get_noise_2d(x, z))
	if mask > 0.0:
		var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
		h += r * r * r * 420.0 * mask + mask * 20.0

	if w.x > 0.0:
		h += w.x * (hills * 20.0 + detail * 1.4 + micro * 0.18)
	if w.y > 0.0:
		h += w.y * (hills * 30.0 + detail * 3.2 + micro * 0.3 + 3.0)
	if w.z > 0.0:
		# Rotate into the dune frame and stretch along the crest direction.
		var u := x * _dune_cos - z * _dune_sin
		var v := x * _dune_sin + z * _dune_cos
		var small := _dunes.get_noise_2d(u, v * 0.33) * 0.5 + 0.5
		var large := _dunes_large.get_noise_2d(u * 0.8, v * 0.3) * 0.5 + 0.5
		h += w.z * (14.0 + hills * 9.0 + large * large * 26.0 + small * small * 6.5)
	return h


func height(x: float, z: float) -> float:
	return height_with(x, z, biome_weights(x, z))


## 0..1 "canopy" factor: where forests are dense vs open glades.
func canopy(x: float, z: float) -> float:
	return clampf(_canopy.get_noise_2d(x, z) * 0.9 + 0.55, 0.0, 1.0)


func dominant_biome(x: float, z: float) -> int:
	var w := biome_weights(x, z)
	if w.y >= w.x and w.y >= w.z:
		return Biome.FOREST
	if w.z >= w.x:
		return Biome.DESERT
	return Biome.MEADOW


## Spiral search for a pleasant spawn point inside `biome`.
func find_spawn(biome: int, origin: Vector2, max_radius := 40000.0) -> Vector2:
	var step := 192.0
	var angle := 0.0
	var radius := 0.0
	while radius <= max_radius:
		var p := origin + Vector2(cos(angle), sin(angle)) * radius
		var w := biome_weights(p.x, p.y)
		if w[biome] > 0.9:
			var h := height_with(p.x, p.y, w)
			var hx := height(p.x + 4.0, p.y)
			var hz := height(p.x, p.y + 4.0)
			var slope := Vector2(hx - h, hz - h).length() / 4.0
			if h > WATER_LEVEL + 3.0 and h < SNOW_LINE - 60.0 and slope < 0.18:
				return p
		# Archimedean spiral with roughly constant arc length between samples.
		angle += step / maxf(radius, step)
		radius = step * angle / TAU * 1.5
	return origin


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
