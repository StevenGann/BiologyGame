extends CharacterBody3D
## First-person controller: WASD movement, mouse look, gravity, jump, sprint.
##
## Uses project input actions: move_forward, move_back, move_left, move_right, jump.
## Must be in group "player" for SimSyncBridge and DebugOverlay to find it.

@export var move_speed: float = 8.0  ## Walk speed (m/s)
@export var sprint_speed: float = 14.0  ## Sprint speed when Shift held
@export var jump_velocity: float = 6.0  ## Initial upward velocity on jump
@export var mouse_sensitivity: float = 0.002  ## Radians per pixel
@export var pitch_limit: float = 89.0  ## Vertical look clamp (degrees)

var _camera: Camera3D
var _pitch: float = 0.0  ## radians


func _ready() -> void:
	add_to_group("player")
	_camera = get_node_or_null("Camera3D")
	if not _camera:
		push_error("FPSController: Camera3D child not found")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var rel: Vector2 = event.relative
		rotate_y(-rel.x * mouse_sensitivity)
		_pitch = clampf(_pitch - rel.y * mouse_sensitivity, deg_to_rad(-pitch_limit), deg_to_rad(pitch_limit))
		if _camera:
			_camera.rotation.x = _pitch

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
