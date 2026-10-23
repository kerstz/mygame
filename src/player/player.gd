class_name Player
extends CharacterBody3D
## Invisible first-person walker. No jump, no sprint: a person strolling.
##
## Ground following: CharacterBody3D floor snapping keeps the body on slopes;
## the camera height is additionally smoothed so uneven ground (rocks, small
## steps) does not jolt the view. Head motion is a very small, optional bob.

const EYE_HEIGHT := 1.65
const BODY_HEIGHT := 1.75
const RADIUS := 0.3

var camera: Camera3D
var world: WorldStreamer
var frozen := true  # until the ground under the player has collision
## Scripted input for benchmarks / automated captures (x = strafe, y = back).
var auto_walk := Vector2.ZERO

var _yaw := 0.0
var _pitch := 0.0
var _step_phase := 0.0
var _cam_y_smooth := 0.0
var _bob_amount := 0.0
var _gravity := 9.8


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = BODY_HEIGHT
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = BODY_HEIGHT * 0.5
	add_child(cs)
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.02

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.near = 0.08
	camera.far = 6000.0
	add_child(camera)
	camera.current = true
	_apply_settings()
	GameSettings.changed.connect(func(_k): _apply_settings())
	_cam_y_smooth = global_position.y


func _apply_settings() -> void:
	camera.fov = GameSettings.get_value("fov")


func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = _yaw
	camera.rotation.x = _pitch


func teleport(p: Vector3, yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_cam_y_smooth = p.y
	set_look(yaw, -0.02)
	frozen = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameSettings.get_value("mouse_sensitivity") * 0.01
		var inv := -1.0 if GameSettings.get_value("invert_y") else 1.0
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens * inv, deg_to_rad(-85), deg_to_rad(85))
		rotation.y = _yaw
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if frozen:
		if world and world.is_ground_ready(global_position):
			# Drop onto the ground from just above the terrain height.
			var h := world.noise.height(global_position.x, global_position.z)
			if global_position.y < h + 0.2 or global_position.y > h + 5.0:
				global_position.y = h + 0.3
			_cam_y_smooth = global_position.y
			frozen = false
		return

	var input := Vector2.ZERO
	if auto_walk != Vector2.ZERO:
		input = auto_walk
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0 else Vector3.ZERO
	var speed: float = GameSettings.get_value("walk_speed")
	var target := dir * speed

	# Do not wade into deep water: block horizontal motion toward it.
	if dir != Vector3.ZERO and world:
		var ahead := global_position + dir * 0.8
		if world.noise.height(ahead.x, ahead.z) < WorldNoise.WATER_LEVEL - 0.9:
			target = Vector3.ZERO

	# Gentle acceleration (~0.5 s to full speed), slightly faster stopping.
	var accel := 3.2 if target.length() > 0.01 else 4.5
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	# Safety net: never fall through the world if collision is late.
	if world:
		var h := world.noise.height(global_position.x, global_position.z)
		if global_position.y < h - 2.0:
			global_position.y = h + 0.2
			velocity.y = 0.0

	_update_camera(delta, hv.length())


func _update_camera(delta: float, speed: float) -> void:
	# Smooth vertical motion of the eye over bumps (critically damped-ish).
	_cam_y_smooth = lerpf(_cam_y_smooth, global_position.y, 1.0 - exp(-delta * 12.0))
	var amount: float = GameSettings.get_value("head_motion")
	var walking := clampf(speed / 1.4, 0.0, 1.0)
	_bob_amount = lerpf(_bob_amount, walking, 1.0 - exp(-delta * 4.0))
	# ~1.8 steps per second at walking speed.
	_step_phase += delta * TAU * 0.9 * clampf(speed / 1.4, 0.3, 1.3)
	var bob_y := sin(_step_phase * 2.0) * 0.018 * amount * _bob_amount
	var sway_x := sin(_step_phase) * 0.010 * amount * _bob_amount
	camera.position = Vector3(sway_x, EYE_HEIGHT + bob_y + (_cam_y_smooth - global_position.y), 0)
	camera.rotation.z = -sin(_step_phase) * 0.0025 * amount * _bob_amount
