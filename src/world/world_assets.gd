class_name WorldAssets
extends RefCounted
## Shared procedural meshes, materials and noise textures.
##
## Built once on the main thread, then shared by every chunk: one material per
## vegetation type means the renderer can batch all instances of a type and
## no per-chunk shader variants are compiled. All geometry here is original
## procedural content (see ASSET_LICENSES.md).

## Per-layer render settings. `range` is a visibility range end in metres
## (0 = unlimited); chunks beyond it are culled by the renderer itself.
const LAYERS := {
	"grass": {"range": 0.0, "shadow": false},
	"seedheads": {"range": 95.0, "shadow": false},
	"fern": {"range": 95.0, "shadow": true},
	"bush": {"range": 260.0, "shadow": true},
	"conifer": {"range": 0.0, "shadow": true},
	"broadleaf": {"range": 0.0, "shadow": true},
	"deadtree": {"range": 0.0, "shadow": true},
	"conifer_far": {"range": 0.0, "shadow": false},
	"broadleaf_far": {"range": 0.0, "shadow": false},
	"log": {"range": 200.0, "shadow": true},
}

static var is_ready := false
static var meshes := {}
static var materials := {}
static var rock_variants: Array[MeshBuilder] = []
static var ruin_variants: Array[MeshBuilder] = []
static var textures := {}


static func init() -> void:
	if is_ready:
		return
	_make_textures()
	_make_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	meshes["grass"] = _grass_clump(rng).commit(null, materials["grass"])
	meshes["seedheads"] = _seed_stalks(rng).commit(null, materials["seedheads"])
	meshes["fern"] = _fern(rng).commit(null, materials["fern"])
	meshes["bush"] = _bush(rng).commit(null, materials["bush"])
	meshes["conifer"] = _conifer(rng)
	meshes["broadleaf"] = _broadleaf(rng, true)
	meshes["deadtree"] = _broadleaf(rng, false)
	meshes["conifer_far"] = _conifer_impostor().commit(null, materials["impostor"])
	meshes["broadleaf_far"] = _broadleaf_impostor(rng).commit(null, materials["impostor"])
	meshes["log"] = _log(rng).commit(null, materials["log"], true)
	for i in 5:
		rock_variants.append(_rock(rng, i))
	ruin_variants = _ruins(rng)
	is_ready = true


# --------------------------------------------------------------------------
# Textures & materials

static func _noise_tex(seed: int, freq: float, size: int, normal := false, octaves := 5,
		type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, bump := 6.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	return t


static func _make_textures() -> void:
	# Low frequency mottling, fine grain and a tangent-space style normal map.
	# 512² seamless textures tile every few metres, but are always sampled at
	# 2-3 incommensurate scales in the shaders so repetition is not visible.
	textures["macro"] = _noise_tex(11, 0.004, 512, false, 5)
	textures["detail"] = _noise_tex(12, 0.03, 512, false, 4)
	textures["cells"] = _noise_tex(13, 0.02, 256, false, 2, FastNoiseLite.TYPE_CELLULAR)
	textures["normal"] = _noise_tex(14, 0.025, 512, true, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 8.0)
	textures["normal_fine"] = _noise_tex(15, 0.09, 256, true, 3, FastNoiseLite.TYPE_SIMPLEX, 4.0)
	textures["wind"] = _noise_tex(16, 0.012, 256, false, 3)


static func _shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _make_materials() -> void:
	var tex := {
		"tex_macro": textures["macro"], "tex_detail": textures["detail"],
		"tex_normal": textures["normal"], "tex_normal_fine": textures["normal_fine"],
		"tex_cells": textures["cells"],
	}
	var terrain_params := tex.duplicate()
	materials["terrain"] = _shader_mat("res://shaders/terrain.gdshader", terrain_params)
	var far_params := tex.duplicate()
	far_params["is_far"] = true
	materials["terrain_far"] = _shader_mat("res://shaders/terrain.gdshader", far_params)

	materials["grass"] = _shader_mat("res://shaders/grass.gdshader",
		{"wind_noise": textures["wind"], "tex_macro": textures["macro"]})
	materials["seedheads"] = _shader_mat("res://shaders/grass.gdshader",
		{"wind_noise": textures["wind"], "tex_macro": textures["macro"], "is_seedhead": true})

	var fol := {"wind_noise": textures["wind"], "tex_detail": textures["detail"]}
	var needles := fol.duplicate()
	needles.merge({"pattern": 0, "color_a": Color(0.06, 0.10, 0.05), "color_b": Color(0.11, 0.15, 0.07)})
	materials["needles"] = _shader_mat("res://shaders/foliage.gdshader", needles)
	var leaves := fol.duplicate()
	leaves.merge({"pattern": 1, "color_a": Color(0.10, 0.16, 0.05), "color_b": Color(0.22, 0.27, 0.08)})
	materials["leaves"] = _shader_mat("res://shaders/foliage.gdshader", leaves)
	var fern := fol.duplicate()
	fern.merge({"sway_height": 1.4, "pattern": 2, "color_a": Color(0.09, 0.16, 0.05), "color_b": Color(0.20, 0.28, 0.08)})
	materials["fern"] = _shader_mat("res://shaders/foliage.gdshader", fern)
	var bush := fol.duplicate()
	bush.merge({"sway_height": 2.5, "pattern": 1, "color_a": Color(0.08, 0.13, 0.05), "color_b": Color(0.17, 0.22, 0.07)})
	materials["bush"] = _shader_mat("res://shaders/foliage.gdshader", bush)
	var imp := fol.duplicate()
	imp.merge({"pattern": 3, "color_a": Color(0.05, 0.08, 0.04), "color_b": Color(0.10, 0.13, 0.06)})
	materials["impostor"] = _shader_mat("res://shaders/foliage.gdshader", imp)

	var bark := {"tex_detail": textures["detail"], "tex_normal": textures["normal"], "wind_noise": textures["wind"]}
	materials["bark"] = _shader_mat("res://shaders/bark.gdshader", bark)
	var logp := bark.duplicate()
	logp["static_object"] = true
	logp["moss_bias"] = 0.35
	materials["log"] = _shader_mat("res://shaders/bark.gdshader", logp)

	var rock := tex.duplicate()
	materials["rock"] = _shader_mat("res://shaders/rock.gdshader", rock)
	var concrete := tex.duplicate()
	concrete["concrete"] = true
	materials["ruins"] = _shader_mat("res://shaders/rock.gdshader", concrete)


# --------------------------------------------------------------------------
# Vegetation meshes

## A clump of curved, tapering blades. UV.y = 0 at the root and 1 at the tip
## (used for wind bending and colour gradient); COLOR.r = per-blade random.
static func _grass_clump(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var blades := 8
	var segs := 4
	for b in blades:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.2)
		var root := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var h := rng.randf_range(0.45, 1.05)
		var w := rng.randf_range(0.018, 0.034)
		var facing := rng.randf() * TAU
		var lean_dir := Vector3(cos(ang), 0, sin(ang)) * 0.6 + Vector3(cos(facing), 0, sin(facing)) * 0.4
		var lean := rng.randf_range(0.05, 0.3) * h
		var side := Vector3(cos(facing + PI * 0.5), 0, sin(facing + PI * 0.5))
		var n := Vector3(cos(facing), 0.25, sin(facing)).normalized()
		var col := Color(rng.randf(), 0, 0)
		var prev_l := -1
		var prev_r := -1
		for s in segs + 1:
			var t := float(s) / float(segs)
			var p := root + Vector3(0, t * h, 0) + lean_dir * lean * t * t
			var half := w * (1.0 - pow(t, 1.6)) * 0.5
			if s == segs:
				var tip := mb.add(p, n, Vector2(0.5, 1.0), col)
				mb.tri(prev_l, tip, prev_r)
			else:
				var l := mb.add(p - side * half, n, Vector2(0.0, t), col)
				var rr := mb.add(p + side * half, n, Vector2(1.0, t), col)
				if prev_l >= 0:
					mb.quad(prev_l, l, rr, prev_r)
				prev_l = l
				prev_r = rr
	return mb


## Seeding grass stalks: tall thin stems topped by loose panicles of tiny
## spikelet cards — the pale, delicate seed heads that catch diffuse light in
## the reference. UV.y > 0.7 marks the head for the shader.
static func _seed_stalks(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	for f in 3:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.1)
		var h := rng.randf_range(0.85, 1.35)
		var lean := Vector3(cos(a + 0.4), 0, sin(a + 0.4)) * rng.randf_range(0.05, 0.22)
		var side := Vector3(cos(a + 1.3), 0, sin(a + 1.3))
		var n := Vector3(cos(a), 0.4, sin(a)).normalized()
		var segs := 4
		var prev := PackedInt32Array()
		for s in segs + 1:
			var t := float(s) / segs
			var p := root + Vector3(0, t * h, 0) + lean * t * t
			var w := 0.006 * (1.0 - t * 0.6)
			var l := mb.add(p - side * w, n, Vector2(0, t * 0.7))
			var r := mb.add(p + side * w, n, Vector2(1, t * 0.7))
			if s > 0:
				mb.quad(prev[0], l, r, prev[1])
			prev = PackedInt32Array([l, r])
		# Panicle: small spikelets hanging off the top quarter of the stem.
		for k in 9:
			var t := rng.randf_range(0.72, 1.0)
			var at := root + Vector3(0, t * h, 0) + lean * t * t
			var ka := rng.randf() * TAU
			var out := Vector3(cos(ka), rng.randf_range(-0.6, 0.1), sin(ka)).normalized()
			var spike := rng.randf_range(0.03, 0.07)
			var tip := at + out * spike
			var sw := Vector3(-out.z, 0, out.x) * 0.006
			var i0 := mb.add(at - sw, n, Vector2(0, 0.75))
			var i1 := mb.add(tip - sw, n, Vector2(0, 1.0))
			var i2 := mb.add(tip + sw, n, Vector2(1, 1.0))
			var i3 := mb.add(at + sw, n, Vector2(1, 0.75))
			mb.quad(i0, i1, i2, i3)
	return mb


## Fern: arching fronds; leaflets are cut out by the foliage shader.
static func _fern(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var fronds := 9
	for f in fronds:
		var a := TAU * float(f) / fronds + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(0.7, 1.15)
		var rise := rng.randf_range(0.5, 0.9)
		var segs := 6
		var prev := PackedInt32Array()
		for s in segs + 1:
			var t := float(s) / segs
			# Parabolic arch: up then drooping.
			var p := dir * t * length + Vector3(0, (t - t * t * 1.15) * rise * length, 0)
			var half := 0.17 * length * sin(PI * minf(t * 1.1, 1.0)) + 0.01
			var tangent := (dir + Vector3(0, (1.0 - 2.3 * t) * rise, 0)).normalized()
			var n := side.cross(tangent).normalized()
			if n.y < 0:
				n = -n
			n = (n + Vector3.UP * 0.6).normalized()
			var l := mb.add(p - side * half, n, Vector2(0, t))
			var r := mb.add(p + side * half, n, Vector2(1, t))
			if s > 0:
				mb.quad(prev[0], l, r, prev[1])
			prev = PackedInt32Array([l, r])
	return mb


## Bush: leafy cards scattered on an ellipsoid with spherical normals, which
## gives the soft, volumetric shading foliage needs instead of flat cards.
static func _bush(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var center := Vector3(0, 0.55, 0)
	for i in 34:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		var p := center + Vector3(dir.x * 0.75, dir.y * 0.5, dir.z * 0.75) * rng.randf_range(0.5, 1.0)
		_card(mb, p, dir, rng.randf_range(0.45, 0.7), rng, center)
	return mb


static func _card(mb: MeshBuilder, p: Vector3, outward: Vector3, size: float,
		rng: RandomNumberGenerator, center: Vector3, col := Color.WHITE) -> void:
	var t1 := outward.cross(Vector3(rng.randf_range(-1, 1), 1, rng.randf_range(-1, 1)).normalized()).normalized()
	if t1.length_squared() < 0.01:
		t1 = Vector3.RIGHT
	var t2 := outward.cross(t1).normalized()
	var h := size * 0.5
	var corners := [p - t1 * h - t2 * h, p - t1 * h + t2 * h, p + t1 * h + t2 * h, p + t1 * h - t2 * h]
	var uv := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var ids := []
	for k in 4:
		var n: Vector3 = (corners[k] - center).normalized()
		ids.append(mb.add(corners[k], n, uv[k], col))
	mb.quad(ids[0], ids[1], ids[2], ids[3])


## Conifer (spruce-like): tapered trunk plus whorls of drooping branch cards.
## Needles are an alpha-tested procedural pattern in foliage.gdshader.
static func _conifer(rng: RandomNumberGenerator) -> ArrayMesh:
	var height := 19.0
	var trunk := MeshBuilder.new()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 7:
		var t := float(i) / 6.0
		pts.append(Vector3(sin(t * 5.0) * 0.06, t * height, cos(t * 4.0) * 0.06))
		radii.append(lerpf(0.36, 0.03, pow(t, 0.8)))
	# Flared root.
	radii[0] = 0.5
	trunk.tube(pts, radii, 9)

	var crown := MeshBuilder.new()
	var whorls := 17
	var base_h := 2.6
	for w in whorls:
		var t := float(w) / float(whorls - 1)
		var y := lerpf(base_h, height - 0.6, t) + rng.randf_range(-0.2, 0.2)
		var length := lerpf(4.1, 0.55, pow(t, 0.85)) * rng.randf_range(0.85, 1.1)
		var count := 7 if t < 0.7 else 5
		var off := rng.randf() * TAU
		for b in count:
			var a := off + TAU * b / count + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0, sin(a))
			_branch_card(crown, Vector3(0, y, 0), dir, length, lerpf(0.55, 0.85, t), rng, Vector3(0, y + 1.0, 0))
	# Leader at the top.
	_branch_card(crown, Vector3(0, height - 1.6, 0), Vector3(0.05, 1, 0).normalized(), 1.8, 0.0, rng, Vector3(0, height - 2.5, 0))
	var mesh := trunk.commit(null, materials["bark"], true)
	crown.commit(mesh, materials["needles"])
	return mesh


## One drooping branch made of two crossed curved strips.
static func _branch_card(mb: MeshBuilder, root: Vector3, dir: Vector3, length: float,
		droop: float, rng: RandomNumberGenerator, normal_center: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	for plane in 2:
		var spread := side if plane == 0 else (up * 0.8 + side * 0.2).normalized()
		var segs := 3
		var prev := PackedInt32Array()
		for s in segs + 1:
			var t := float(s) / segs
			var p := root + dir * length * t + Vector3(0, (0.25 * t - droop * t * t) * length * 0.5, 0)
			var half := length * 0.34 * (1.0 - t * 0.55) * (0.6 if plane == 1 else 1.0)
			var n0 := (p - normal_center).normalized()
			var l := mb.add(p - spread * half, n0, Vector2(0, t))
			var r := mb.add(p + spread * half, n0, Vector2(1, t))
			if s > 0:
				mb.quad(prev[0], l, r, prev[1])
			prev = PackedInt32Array([l, r])


## Broadleaf tree: forked trunk and leaf-card clusters. With `leaves = false`
## it becomes a dead, bare tree (used in deserts and open meadows).
static func _broadleaf(rng: RandomNumberGenerator, leaves: bool) -> ArrayMesh:
	var bark := MeshBuilder.new()
	var foliage := MeshBuilder.new()
	var trunk_h := 4.2 if leaves else 3.2
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.1, trunk_h * 0.5, 0.05), Vector3(0.0, trunk_h, 0.15)])
	bark.tube(pts, PackedFloat32Array([0.42, 0.3, 0.24]), 9)
	var crown_center := Vector3(0, trunk_h + 3.6, 0)
	var limbs := 6 if leaves else 5
	for l in limbs:
		var a := TAU * l / limbs + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var rise := rng.randf_range(0.8, 1.6)
		var limb_len := rng.randf_range(3.0, 4.6) * (1.0 if leaves else 0.8)
		var p0 := Vector3(0.0, trunk_h * rng.randf_range(0.85, 1.0), 0.15)
		var p1 := p0 + (out * 0.55 + Vector3(0, rise * 0.6, 0)) * limb_len * 0.5
		var p2 := p1 + (out * 0.75 + Vector3(0, rise * 0.4, 0)) * limb_len * 0.5
		bark.tube(PackedVector3Array([p0, p1, p2]), PackedFloat32Array([0.19, 0.11, 0.03]), 6)
		# Twigs from the limb end.
		for k in 3:
			var ta := a + rng.randf_range(-1.0, 1.0)
			var tw := p2 + Vector3(cos(ta), rng.randf_range(0.2, 0.8), sin(ta)) * rng.randf_range(0.8, 1.6)
			bark.tube(PackedVector3Array([p1.lerp(p2, 0.6), tw]), PackedFloat32Array([0.05, 0.012]), 4)
		if leaves:
			# Leaf clusters around the limb ends.
			for c in 34:
				var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
				var p := p2 + off * rng.randf_range(0.2, 1.9)
				_card(foliage, p, (p - crown_center).normalized(), rng.randf_range(0.9, 1.4), rng, crown_center)
	if leaves:
		# Fill the crown interior so it does not look hollow from below.
		for c in 70:
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.8), rng.randf_range(-1, 1))
			var p := crown_center + Vector3(off.x * 3.6, off.y * 2.6, off.z * 3.6)
			_card(foliage, p, (p - crown_center).normalized(), rng.randf_range(1.0, 1.5), rng, crown_center)
	var mesh := bark.commit(null, materials["bark"], true)
	if leaves:
		foliage.commit(mesh, materials["leaves"])
	return mesh


## Far LOD: an opaque cone with a fake trunk. Shading only, no alpha test.
static func _conifer_impostor() -> MeshBuilder:
	var mb := MeshBuilder.new()
	var sides := 10
	var tip := Vector3(0, 19.0, 0)
	var base_y := 2.4
	var ring := []
	for s in sides + 1:
		var a := TAU * s / sides
		var p := Vector3(cos(a) * 3.9, base_y, sin(a) * 3.9)
		ring.append(mb.add(p, Vector3(cos(a), 0.5, sin(a)).normalized(), Vector2(float(s) / sides, 0)))
	var t := mb.add(tip, Vector3.UP, Vector2(0.5, 1))
	for s in sides:
		mb.tri(ring[s], t, ring[s + 1])
	return mb


static func _broadleaf_impostor(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := _sphere(2, Vector3(3.8, 3.0, 3.8), rng, 0.25)
	for i in mb.verts.size():
		mb.verts[i] += Vector3(0, 7.6, 0)
	return mb


static func _log(rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 6:
		var t := float(i) / 5.0
		pts.append(Vector3(0, 0.25 + sin(t * 3.0) * 0.04, (t - 0.5) * 6.0))
		radii.append(lerpf(0.34, 0.24, t) + rng.randf_range(-0.02, 0.02))
	mb.tube(pts, radii, 10)
	return mb


## Icosphere, optionally displaced by noise for organic shapes.
static func _sphere(subdiv: int, scale: Vector3, rng: RandomNumberGenerator, displace: float,
		noise: FastNoiseLite = null) -> MeshBuilder:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
		2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in subdiv:
		var cache := {}
		var nf := PackedInt32Array()
		for i in range(0, f.size(), 3):
			var a := f[i]
			var b := f[i + 1]
			var c := f[i + 2]
			var ab := _midpoint(v, cache, a, b)
			var bc := _midpoint(v, cache, b, c)
			var ca := _midpoint(v, cache, c, a)
			nf.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		f = nf
	if noise == null:
		noise = FastNoiseLite.new()
		noise.seed = rng.randi()
		noise.frequency = 1.3
		noise.fractal_octaves = 3
	var mb := MeshBuilder.new()
	for p in v:
		var d := 1.0 + noise.get_noise_3dv(p * 1.0) * displace
		mb.add(p * d * scale, p, Vector2(p.x, p.z) * 0.5 + Vector2(0.5, 0.5))
	# Icosphere faces are counter-clockwise from outside; flip to clockwise.
	for i in range(0, f.size(), 3):
		mb.tri(f[i], f[i + 2], f[i + 1])
	_recompute_normals(mb)
	return mb


static func _midpoint(v: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	cache[key] = v.size() - 1
	return v.size() - 1


static func _recompute_normals(mb: MeshBuilder) -> void:
	var acc := PackedVector3Array()
	acc.resize(mb.verts.size())
	for i in range(0, mb.indices.size(), 3):
		var a := mb.indices[i]
		var b := mb.indices[i + 1]
		var c := mb.indices[i + 2]
		# Clockwise winding: (c-a) x (b-a) points outward.
		var n := (mb.verts[c] - mb.verts[a]).cross(mb.verts[b] - mb.verts[a])
		acc[a] += n
		acc[b] += n
		acc[c] += n
	for i in acc.size():
		mb.normals[i] = acc[i].normalized()


## Boulders: noise-displaced icospheres flattened at the bottom, with sharper
## ridged displacement for a fractured look.
static func _rock(rng: RandomNumberGenerator, variant: int) -> MeshBuilder:
	var n := FastNoiseLite.new()
	n.seed = 100 + variant
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n.frequency = 0.9
	n.fractal_octaves = 4
	var sc := Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.55, 0.9), rng.randf_range(0.8, 1.2))
	var mb := _sphere(3, sc, rng, 0.32, n)
	for i in mb.verts.size():
		var p := mb.verts[i]
		if p.y < -0.15:
			p.y = -0.15 + (p.y + 0.15) * 0.25
		mb.verts[i] = p
	_recompute_normals(mb)
	return mb


## Concrete ruins: a broken wall, a pillar, a collapsed slab, a curb segment.
## Built from boxes with jagged, noise-displaced tops.
static func _ruins(rng: RandomNumberGenerator) -> Array[MeshBuilder]:
	var out: Array[MeshBuilder] = []
	out.append(_broken_box(Vector3(7.0, 3.4, 0.35), 14, 1.6, rng))
	out.append(_broken_box(Vector3(0.6, 4.2, 0.6), 2, 1.0, rng))
	out.append(_broken_box(Vector3(5.0, 0.3, 3.2), 8, 0.12, rng))
	out.append(_broken_box(Vector3(3.5, 2.6, 0.3), 8, 1.2, rng))
	return out


static func _broken_box(size: Vector3, cols: int, break_depth: float, rng: RandomNumberGenerator) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	# Top edge heights along x.
	var tops := PackedFloat32Array()
	for c in cols + 1:
		var edge := 1.0 if c == 0 or c == cols else 0.0
		tops.append(size.y - rng.randf() * break_depth * (1.0 - edge * 0.5) - (break_depth * 0.6 if rng.randf() < 0.3 else 0.0))
	var below := -0.6
	for c in cols:
		var x0 := -hx + size.x * c / cols
		var x1 := -hx + size.x * (c + 1) / cols
		var t0 := tops[c]
		var t1 := tops[c + 1]
		# Front (-z) and back (+z) faces.
		_face(mb, Vector3(x0, below, -hz), Vector3(x0, t0, -hz), Vector3(x1, t1, -hz), Vector3(x1, below, -hz), Vector3(0, 0, -1))
		_face(mb, Vector3(x1, below, hz), Vector3(x1, t1, hz), Vector3(x0, t0, hz), Vector3(x0, below, hz), Vector3(0, 0, 1))
		# Jagged top.
		_face(mb, Vector3(x0, t0, -hz), Vector3(x0, t0, hz), Vector3(x1, t1, hz), Vector3(x1, t1, -hz), Vector3(0, 1, 0))
	_face(mb, Vector3(-hx, below, hz), Vector3(-hx, tops[0], hz), Vector3(-hx, tops[0], -hz), Vector3(-hx, below, -hz), Vector3(-1, 0, 0))
	_face(mb, Vector3(hx, below, -hz), Vector3(hx, tops[cols], -hz), Vector3(hx, tops[cols], hz), Vector3(hx, below, hz), Vector3(1, 0, 0))
	return mb


static func _face(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var ia := mb.add(a, n, Vector2(a.x + a.z, a.y))
	var ib := mb.add(b, n, Vector2(b.x + b.z, b.y))
	var ic := mb.add(c, n, Vector2(c.x + c.z, c.y))
	var id := mb.add(d, n, Vector2(d.x + d.z, d.y))
	# Clockwise-from-outside means (c-a)x(b-a) points along the outward normal.
	if (c - a).cross(b - a).dot(n) >= 0.0:
		mb.quad(ia, ib, ic, id)
	else:
		mb.quad(ia, id, ic, ib)
