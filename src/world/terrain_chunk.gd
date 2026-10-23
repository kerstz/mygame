class_name TerrainChunk
extends Node3D
## Main-thread side of a chunk: turns a ChunkBuilder.Result into render
## instances and (optionally) physics. Physics uses the PhysicsServer3D
## directly: no nodes per tree/rock, and collision exists only for the
## chunks around the player.

var coord := Vector2i.ZERO
var lod := 0
var is_far := false
var data: ChunkBuilder.Result

var _body := RID()
var _shapes: Array[RID] = []
var _grass: MultiMeshInstance3D
var _seedheads: MultiMeshInstance3D
var _grass_count := 0


func setup(r: ChunkBuilder.Result) -> void:
	data = r
	coord = r.coord
	lod = r.lod
	is_far = r.is_far
	position = r.origin
	name = ("Far_%d_%d" if is_far else "Chunk_%d_%d") % [coord.x, coord.y]

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.mesh_arrays)
	mesh.surface_set_material(0, WorldAssets.materials["terrain_far" if is_far else "terrain"])
	mesh.custom_aabb = r.aabb
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_far or lod >= 3 \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# The mesh arrays are no longer needed on the CPU once uploaded.
	r.mesh_arrays = []

	for layer_name in r.layers:
		var info: Dictionary = r.layers[layer_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = WorldAssets.meshes[layer_name]
		mm.instance_count = info["count"]
		mm.buffer = info["buffer"]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var cfg: Dictionary = WorldAssets.LAYERS[layer_name]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg["shadow"] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cfg["range"] > 0.0:
			mmi.visibility_range_end = cfg["range"]
			mmi.visibility_range_end_margin = 10.0
		# Wind moves vertices outside the static instance bounds.
		mmi.extra_cull_margin = 2.0
		add_child(mmi)
		if layer_name == "grass":
			_grass = mmi
			_grass_count = info["count"]
		elif layer_name == "seedheads":
			_seedheads = mmi
	r.layers = {}

	for pair in [[r.rocks_arrays, "rock"], [r.ruins_arrays, "ruins"]]:
		if pair[0].is_empty():
			continue
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[0])
		m.surface_set_material(0, WorldAssets.materials[pair[1]])
		var rmi := MeshInstance3D.new()
		rmi.mesh = m
		if lod >= 3:
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rmi)
	r.rocks_arrays = []
	r.ruins_arrays = []


## Grass is generated at maximum density with instances in random order, so
## drawing only the first N instances is an unbiased uniform thinning.
func apply_grass_density(density: float, grass_shadows: bool) -> void:
	var f := density * (1.0 if lod == 0 else 0.55)
	if _grass:
		_grass.multimesh.visible_instance_count = int(_grass_count * clampf(f, 0.0, 1.0))
		_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if grass_shadows and lod == 0 \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _seedheads:
		_seedheads.visible = density > 0.3


func has_collision() -> bool:
	return _body.is_valid()


func set_collision(active: bool, space: RID) -> void:
	if active == _body.is_valid():
		return
	if not active:
		_free_physics()
		return
	if data == null or data.collision_heights.is_empty():
		return
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_body, space)
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), position))

	var res := data.collision_res + 1
	var hs := PhysicsServer3D.heightmap_shape_create()
	var hmin := INF
	var hmax := -INF
	for h in data.collision_heights:
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
	PhysicsServer3D.shape_set_data(hs, {
		"width": res, "depth": res, "heights": data.collision_heights,
		"min_height": hmin, "max_height": hmax})
	# Height map shapes are centred on their origin, with 1 m cell spacing.
	var half := data.size * 0.5
	_add_shape(hs, Transform3D(Basis(), Vector3(half, 0, half)))

	for c in data.colliders:
		var kind: int = c[0]
		var xf: Transform3D = c[1]
		var p: Vector3 = c[2]
		var shape: RID
		match kind:
			0:  # vertical (or rotated) cylinder: p.x radius, p.y height
				shape = PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(shape, {"radius": p.x, "height": p.y})
				if xf.basis.is_equal_approx(Basis()):
					xf.origin.y += p.y * 0.5
			1:
				shape = PhysicsServer3D.sphere_shape_create()
				PhysicsServer3D.shape_set_data(shape, p.x)
			_:
				shape = PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape, p)
		_add_shape(shape, xf)


func _add_shape(shape: RID, xf: Transform3D) -> void:
	PhysicsServer3D.body_add_shape(_body, shape, xf)
	_shapes.append(shape)


func _free_physics() -> void:
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for s in _shapes:
		PhysicsServer3D.free_rid(s)
	_shapes.clear()


func _exit_tree() -> void:
	_free_physics()
