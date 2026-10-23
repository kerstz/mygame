class_name RainSystem
extends Node3D
## Camera-following rain. Particles live in world space (so walking does not
## drag the rain along) and die when they hit the terrain, using a height
## field collider that follows the camera.

var camera: Camera3D
var particles: GPUParticles3D
var collider: GPUParticlesCollisionHeightField3D
var _process_mat: ParticleProcessMaterial
var _max_amount := 9000


func _ready() -> void:
	particles = GPUParticles3D.new()
	particles.local_coords = false
	particles.lifetime = 2.6
	particles.preprocess = 2.6
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.visibility_aabb = AABB(Vector3(-45, -45, -45), Vector3(90, 90, 90))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.collision_base_size = 0.02

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(24, 1, 24)
	_process_mat.direction = Vector3(0, -1, 0)
	_process_mat.spread = 2.0
	_process_mat.initial_velocity_min = 8.5
	_process_mat.initial_velocity_max = 10.5
	_process_mat.gravity = Vector3(0, -3.0, 0)
	_process_mat.particle_flag_align_y = true
	_process_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_process_mat.scale_min = 0.7
	_process_mat.scale_max = 1.2
	particles.process_material = _process_mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rain.gdshader")
	quad.material = mat
	particles.draw_pass_1 = quad
	add_child(particles)

	collider = GPUParticlesCollisionHeightField3D.new()
	collider.size = Vector3(60, 80, 60)
	collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	collider.follow_camera_enabled = true
	collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(collider)
	apply_quality()
	GameSettings.changed.connect(func(_k): apply_quality())


func apply_quality() -> void:
	_max_amount = int(9000 * float(GameSettings.get_value("rain_density")))
	if particles.amount != max(_max_amount, 1):
		particles.amount = max(_max_amount, 1)


## intensity 0..1; wind is a world-space XZ vector scaled by strength.
func update_rain(intensity: float, wind: Vector2) -> void:
	particles.emitting = intensity > 0.02
	particles.amount_ratio = clampf(intensity, 0.0, 1.0)
	_process_mat.direction = Vector3(wind.x * 0.35, -1.0, wind.y * 0.35).normalized()
	if camera:
		var cp := camera.global_position
		# Emit above and slightly upwind so slanted rain covers the view.
		particles.global_position = cp + Vector3(-wind.x * 4.0, 16.0, -wind.y * 4.0)
		collider.global_position = Vector3(cp.x, cp.y, cp.z)
