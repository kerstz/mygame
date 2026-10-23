class_name WaterPlane
extends MeshInstance3D
## A large plane at WorldNoise.WATER_LEVEL that follows the camera. Wherever
## the terrain dips below that level a lake appears; elsewhere the plane is
## hidden under the ground (depth test). Cheap and seamless at any distance.

var camera: Camera3D


func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(5200, 5200)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("tex_normal", WorldAssets.textures["normal"])
	pm.material = mat
	mesh = pm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if camera:
		var p := camera.global_position
		global_position = Vector3(snappedf(p.x, 8.0), WorldNoise.WATER_LEVEL, snappedf(p.z, 8.0))
