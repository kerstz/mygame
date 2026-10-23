class_name MeshBuilder
extends RefCounted
## Minimal triangle-list accumulator. Thread-safe as long as each thread uses
## its own instance (it only touches packed arrays). Godot's front faces are
## clockwise, so `quad(a, b, c, d)` expects a,b,c,d clockwise as seen from the
## front side.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func add(v: Vector3, n: Vector3, uv := Vector2.ZERO, c := Color.WHITE) -> int:
	verts.append(v)
	normals.append(n)
	uvs.append(uv)
	colors.append(c)
	return verts.size() - 1


func tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


func vertex_count() -> int:
	return verts.size()


## Appends another builder, transforming its geometry. Used to merge many small
## objects (rocks, ruins) into one per-chunk mesh = one draw call.
func append_transformed(other: MeshBuilder, xf: Transform3D, tint := Color.WHITE) -> void:
	var base := verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(xf * other.verts[i])
		normals.append((nb * other.normals[i]).normalized())
		uvs.append(other.uvs[i])
		colors.append(other.colors[i] * tint)
	for idx in other.indices:
		indices.append(base + idx)


func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


## Adds this builder as a new surface of `mesh` (or a new mesh).
## With `tangents`, MikkTSpace tangents are generated (needed for NORMAL_MAP).
func commit(mesh: ArrayMesh = null, material: Material = null, tangents := false) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := to_arrays()
	if tangents:
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.generate_tangents()
		arrays = st.commit_to_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Tapered, optionally curved tube along a polyline (trunks, branches, logs).
## `uv.y` runs along the tube in metres, `uv.x` around it (0..1).
func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int, color := Color.WHITE) -> void:
	var rings := points.size()
	var start := verts.size()
	var along := 0.0
	for r in rings:
		var p := points[r]
		var dir: Vector3
		if r == rings - 1:
			dir = (p - points[r - 1]).normalized()
		else:
			dir = (points[r + 1] - p).normalized()
		if r > 0:
			along += p.distance_to(points[r - 1])
		var side := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.9 else Vector3.UP
		var t1 := dir.cross(side).normalized()
		var t2 := dir.cross(t1).normalized()
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var n := (t1 * cos(a) + t2 * sin(a)).normalized()
			add(p + n * radii[r], n, Vector2(float(s) / float(sides), along), color)
	for r in rings - 1:
		for s in sides:
			var i0 := start + r * (sides + 1) + s
			var i1 := i0 + 1
			var j0 := i0 + sides + 1
			var j1 := j0 + 1
			quad(i0, j0, j1, i1)
