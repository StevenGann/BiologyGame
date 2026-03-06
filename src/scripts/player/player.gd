extends CharacterBody3D
## FPS player controller. WASD movement, mouse look, jump, shoot raycast.
## - Shoot: raycast from camera; hit objects with take_damage receive 1 damage; tranq dart placed at hit point
## - Mouse capture toggled with Escape
## - When debug mode is active, gravity is disabled and Space/Ctrl move up/down

const SPEED := 5.0
const SPEED_BOOST := 10.0  ## Speed multiplier when Shift held (testing)
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.002
const CAMERA_PITCH_LIMIT := deg_to_rad(89.0)
const DART_OFFSET := 0.08  ## Offset from hit point for tranq dart to avoid z-fighting
const DEBUG_FLY_SPEED := 5.0  ## Vertical fly speed in debug mode

@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D

var gravity: float
var _tranq_dart_scene: PackedScene
var _sim_manager: Node = null


func _ready() -> void:
	add_to_group("player")
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_tranq_dart_scene = preload("res://scenes/weapons/tranq_dart.tscn")


func _physics_process(delta: float) -> void:
	var debug_mode := _is_debug_mode()
	if debug_mode:
		_handle_debug_fly()
	else:
		_apply_gravity(delta)
		_handle_jump()
	_handle_movement()
	move_and_slide()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_look(event.relative)
	if event.is_action_pressed("shoot"):
		shoot()
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _is_debug_mode() -> bool:
	if _sim_manager == null or not is_instance_valid(_sim_manager):
		_sim_manager = get_tree().get_first_node_in_group("simulation_manager")
	if _sim_manager and "debug_mode" in _sim_manager:
		return _sim_manager.debug_mode
	return false


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func _handle_debug_fly() -> void:
	var fly_input := 0.0
	if Input.is_action_pressed("jump"):
		fly_input += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		fly_input -= 1.0
	velocity.y = fly_input * DEBUG_FLY_SPEED * (SPEED_BOOST if Input.is_key_pressed(KEY_SHIFT) else 1.0)


func _handle_movement() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := SPEED * (SPEED_BOOST if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY


func _handle_mouse_look(relative: Vector2) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	rotate_y(-relative.x * MOUSE_SENSITIVITY)
	if camera:
		camera.rotate_x(-relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)


## Raycast from camera; apply damage to collider if has take_damage; place tranq dart.
func shoot() -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return

	var hit_point := raycast.get_collision_point()
	var hit_normal := raycast.get_collision_normal()
	var collider = raycast.get_collider()

	_place_tranq_dart(hit_point, hit_normal, collider)

	if collider != null and collider.has_method("take_damage"):
		collider.take_damage(1)


## Instantiate tranq dart at hit point. Parent to collider if animal (so dart follows), else World/TranqDarts.
func _place_tranq_dart(hit_point: Vector3, _hit_normal: Vector3, collider: Node) -> void:
	var dart := _tranq_dart_scene.instantiate() as Node3D
	var dart_parent: Node3D

	# Stick to animal so dart disappears when animal is removed; use TranqDarts for terrain
	if collider != null and collider.has_method("take_damage"):
		dart_parent = collider as Node3D
	else:
		dart_parent = get_parent().get_node_or_null("World/TranqDarts")
		if dart_parent == null:
			dart_parent = get_tree().current_scene as Node3D

	dart_parent.add_child(dart)
	var ray_origin := raycast.global_position
	var dir_toward_player := (ray_origin - hit_point).normalized()
	dart.global_position = hit_point + dir_toward_player * DART_OFFSET
	var up_hint: Vector3
	if abs(dir_toward_player.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.FORWARD if abs(dir_toward_player.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	else:
		up_hint = Vector3.UP
	dart.global_transform = Transform3D(Basis.looking_at(dir_toward_player, up_hint), dart.global_position)
