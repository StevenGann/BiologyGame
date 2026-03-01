extends CharacterBody3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

signal animal_defeated

enum State { WANDERING, PANICKING }

@export var use_ps1_effect: bool = true
@export var max_health: int = 2
@export var wander_speed: float = 0.8
@export var panic_speed: float = 4.0
@export var wander_radius: float = 8.0
@export var detection_range: float = 6.0
@export var panic_duration: float = 3.0
@export var wander_pause_min: float = 1.0
@export var wander_pause_max: float = 4.0

var health: int
var _state := State.WANDERING
var _wander_target: Vector3
var _wander_timer: float
var _panic_timer: float
var _threat_position: Vector3


func _ready() -> void:
	health = max_health
	if use_ps1_effect:
		PS1MaterialBuilder.apply_to_node($Model)
	_pick_new_wander_target()
	_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _physics_process(delta: float) -> void:
	var gravity_vec: Vector3 = Vector3.DOWN * ProjectSettings.get_setting("physics/3d/default_gravity")
	velocity.y += gravity_vec.y * delta
	_update_state(delta)
	_apply_movement(delta)
	move_and_slide()


func take_damage(amount: int) -> void:
	health -= amount
	var player := _get_player()
	_panic_from_position(player.global_position if player else global_position + (-global_transform.basis.z * 2.0))
	if health <= 0:
		_defeat()


func _defeat() -> void:
	animal_defeated.emit()
	queue_free()


func _update_state(delta: float) -> void:
	var player := _get_player()
	if player != null:
		var dist := global_position.distance_to(player.global_position)
		if dist < detection_range:
			_panic_from_position(player.global_position)

	if _state == State.PANICKING:
		_panic_timer -= delta
		if _panic_timer <= 0:
			_state = State.WANDERING
			_pick_new_wander_target()
			_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _apply_movement(delta: float) -> void:
	if _state == State.PANICKING:
		var away := (global_position - _threat_position).normalized()
		away.y = 0
		if away.length_squared() > 0.01:
			velocity.x = away.x * panic_speed
			velocity.z = away.z * panic_speed
			look_at(global_position + away, Vector3.UP)
	elif _state == State.WANDERING:
		if _wander_timer > 0:
			_wander_timer -= delta
			velocity.x = move_toward(velocity.x, 0, wander_speed * 2)
			velocity.z = move_toward(velocity.z, 0, wander_speed * 2)
		else:
			var to_target := _wander_target - global_position
			to_target.y = 0
			if to_target.length() < 0.5:
				_pick_new_wander_target()
				_wander_timer = randf_range(wander_pause_min, wander_pause_max)
				velocity.x = 0
				velocity.z = 0
			else:
				var dir := to_target.normalized()
				velocity.x = dir.x * wander_speed
				velocity.z = dir.z * wander_speed
				look_at(global_position + dir, Vector3.UP)


func _panic_from_position(pos: Vector3) -> void:
	_state = State.PANICKING
	_threat_position = pos
	_panic_timer = panic_duration


func _pick_new_wander_target() -> void:
	var offset := Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	_wander_target = global_position + offset


func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
