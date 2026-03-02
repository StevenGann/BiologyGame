extends AnimalBase
## Hunter: wanders, stalks prey (slow approach), chases and kills when close or target panics.

enum HunterState { WANDERING, STALKING, CHASING, KILLING }

@export var stalk_speed: float = 1.0
@export var chase_speed: float = 5.0
@export var chase_trigger_range: float = 3.0
@export var kill_range: float = 1.5
@export var kill_damage: int = 999

var _hunter_state := HunterState.WANDERING
var _current_target: CharacterBody3D = null


func _ready() -> void:
	super._ready()
	add_to_group("hunters")


func _update_state(delta: float) -> void:
	super._update_state(delta)

	if _hunter_state == HunterState.WANDERING:
		var prey := _get_nearest_prey()
		if prey != null:
			_current_target = prey
			_hunter_state = HunterState.STALKING
	elif _hunter_state == HunterState.STALKING:
		if _current_target == null or not is_instance_valid(_current_target):
			_clear_target()
			_hunter_state = HunterState.WANDERING
		elif not _is_target_in_range(detection_range):
			_clear_target()
			_hunter_state = HunterState.WANDERING
		elif _current_target.is_panicking() or global_position.distance_to(_current_target.global_position) < chase_trigger_range:
			_hunter_state = HunterState.CHASING
	elif _hunter_state == HunterState.CHASING:
		if _current_target == null or not is_instance_valid(_current_target):
			_clear_target()
			_hunter_state = HunterState.WANDERING
		elif not _is_target_in_range(detection_range * 1.5):
			_clear_target()
			_hunter_state = HunterState.WANDERING
		elif global_position.distance_to(_current_target.global_position) < kill_range:
			_hunter_state = HunterState.KILLING
	elif _hunter_state == HunterState.KILLING:
		if _current_target == null or not is_instance_valid(_current_target):
			_clear_target()
			_hunter_state = HunterState.WANDERING
		else:
			if _current_target.has_method("take_damage"):
				_current_target.take_damage(kill_damage)
			_clear_target()
			_hunter_state = HunterState.WANDERING


func _apply_movement(delta: float) -> void:
	if _hunter_state == HunterState.STALKING and _current_target and is_instance_valid(_current_target):
		var to_target := _current_target.global_position - global_position
		to_target.y = 0
		if to_target.length_squared() > 0.01:
			var dir := to_target.normalized()
			velocity.x = dir.x * stalk_speed
			velocity.z = dir.z * stalk_speed
			var cohesion := _get_social_cohesion_vector()
			_apply_cohesion_to_velocity(cohesion)
			look_at(global_position + dir, Vector3.UP)
	elif _hunter_state == HunterState.CHASING and _current_target and is_instance_valid(_current_target):
		var to_target := _current_target.global_position - global_position
		to_target.y = 0
		if to_target.length_squared() > 0.01:
			var dir := to_target.normalized()
			velocity.x = dir.x * chase_speed
			velocity.z = dir.z * chase_speed
			look_at(global_position + dir, Vector3.UP)
	elif _hunter_state == HunterState.KILLING:
		velocity.x = move_toward(velocity.x, 0, chase_speed * 2)
		velocity.z = move_toward(velocity.z, 0, chase_speed * 2)
	else:
		super._apply_movement(delta)


func _get_debug_state_string() -> String:
	match _hunter_state:
		HunterState.WANDERING:
			return "Wander"
		HunterState.STALKING:
			return "Stalk"
		HunterState.CHASING:
			return "Chase"
		HunterState.KILLING:
			return "Kill"
	return "?"


func _update_debug_visuals(sim: Node) -> void:
	super._update_debug_visuals(sim)
	if _debug_mesh_instance == null or sim == null or not sim.debug_mode:
		return
	var imesh: ImmediateMesh = _debug_mesh_instance.mesh
	if imesh == null:
		return
	if sim.get("debug_show_hunter_prey_line") != false and _current_target != null and is_instance_valid(_current_target):
		var mat := _make_debug_material(Color(0.9, 0.2, 0.2))  # Red
		imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		imesh.surface_add_vertex(Vector3.ZERO)
		imesh.surface_add_vertex(to_local(_current_target.global_position))
		imesh.surface_end()
	if sim.get("debug_show_detection_radii") != false:
		var chase_mat := _make_debug_material(Color(1.0, 0.5, 0.0))  # Orange
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, chase_mat)
		for i in range(25):
			var a := TAU * float(i) / 24.0
			imesh.surface_add_vertex(Vector3(cos(a) * chase_trigger_range, 0, sin(a) * chase_trigger_range))
		imesh.surface_end()
		var kill_mat := _make_debug_material(Color(1.0, 0.0, 0.0))  # Bright red
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, kill_mat)
		for i in range(25):
			var a := TAU * float(i) / 24.0
			imesh.surface_add_vertex(Vector3(cos(a) * kill_range, 0, sin(a) * kill_range))
		imesh.surface_end()
	_debug_mesh_instance.mesh = imesh


func _get_nearest_prey() -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var best_dist_sq := detection_range * detection_range
	var sim: Node = _get_sim_manager()
	if sim != null and sim.has_method("get_animals_in_radius"):
		var animals_list: Array = sim.get_animals_in_radius(global_position, detection_range, self)
		for a in animals_list:
			if not is_instance_of(a, CharacterBody3D):
				continue
			var other := a as CharacterBody3D
			if other == self:
				continue
			var d_sq := global_position.distance_squared_to(other.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = other
		return nearest
	var animals_parent := get_parent()
	if animals_parent:
		for a in animals_parent.get_children():
			if not is_instance_of(a, CharacterBody3D):
				continue
			var other := a as CharacterBody3D
			if other == self:
				continue
			var d_sq := global_position.distance_squared_to(other.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = other
	return nearest


func _is_target_in_range(rng: float) -> bool:
	if _current_target == null or not is_instance_valid(_current_target):
		return false
	return global_position.distance_to(_current_target.global_position) <= rng


func _clear_target() -> void:
	_current_target = null
