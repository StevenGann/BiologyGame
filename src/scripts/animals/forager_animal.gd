extends AnimalBase
## Forager: wanders, eats Plants, panics and flees when spotting a Hunter.

enum ForagerState { WANDERING, EATING, PANICKING }

@export var plant_detection_range: float = 5.0
@export var hunter_detection_range: float = 12.0
@export var hunter_safe_distance: float = 20.0
@export var eating_duration: float = 2.0

var _forager_state := ForagerState.WANDERING
var _current_plant: Node3D = null
var _eating_timer: float = 0.0
var _panicking_from_hunter: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("foragers")


func _update_state(delta: float) -> void:
	_update_threats(delta)

	if _state == State.PANICKING:
		if _panicking_from_hunter:
			var hunter := _get_nearest_hunter()
			if hunter == null or global_position.distance_to(hunter.global_position) >= hunter_safe_distance:
				_state = State.WANDERING
				_forager_state = ForagerState.WANDERING
				_panicking_from_hunter = false
				_pick_new_wander_target()
				_wander_timer = randf_range(wander_pause_min, wander_pause_max)
		else:
			_panic_timer -= delta
			if _panic_timer <= 0:
				_state = State.WANDERING
				_forager_state = ForagerState.WANDERING
				_pick_new_wander_target()
				_wander_timer = randf_range(wander_pause_min, wander_pause_max)

	_apply_contagion(delta)

	if _forager_state == ForagerState.WANDERING:
		var hunter := _get_nearest_hunter()
		if hunter != null:
			pass
		else:
			var plant := _get_nearest_plant()
			if plant != null:
				_current_plant = plant
				_forager_state = ForagerState.EATING
				_eating_timer = eating_duration
	elif _forager_state == ForagerState.EATING:
		if _get_nearest_hunter() != null:
			pass
		elif _current_plant == null or not is_instance_valid(_current_plant):
			_forager_state = ForagerState.WANDERING
			_current_plant = null
		else:
			_eating_timer -= delta
			if _eating_timer <= 0:
				if _current_plant.has_method("consume") and _current_plant.consume():
					_eating_timer = eating_duration
				else:
					_forager_state = ForagerState.WANDERING
					_current_plant = null


func _update_threats(delta: float) -> void:
	super._update_threats(delta)
	var hunter := _get_nearest_hunter()
	if hunter != null:
		_panic_from_position(hunter.global_position)
		_panicking_from_hunter = true
		_forager_state = ForagerState.PANICKING


func _apply_movement(delta: float) -> void:
	if _state == State.PANICKING:
		var away := (global_position - _threat_position).normalized()
		away.y = 0
		if away.length_squared() > 0.01:
			velocity.x = away.x * panic_speed
			velocity.z = away.z * panic_speed
			var cohesion := _get_social_cohesion_vector()
			_apply_cohesion_to_velocity(cohesion)
			look_at(global_position + Vector3(velocity.x, 0, velocity.z), Vector3.UP)
	elif _forager_state == ForagerState.EATING:
		velocity.x = move_toward(velocity.x, 0, wander_speed * 2)
		velocity.z = move_toward(velocity.z, 0, wander_speed * 2)
	else:
		super._apply_movement(delta)


func _get_nearest_hunter() -> Node3D:
	var nearest: Node3D = null
	var best_dist_sq := hunter_detection_range * hunter_detection_range
	var sim: Node = _get_sim_manager()
	if sim != null and sim.has_method("get_hunters_in_radius"):
		var hunters_list: Array = sim.get_hunters_in_radius(global_position, hunter_detection_range)
		for h in hunters_list:
			if h == self:
				continue
			var d_sq := global_position.distance_squared_to(h.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = h
		return nearest
	var animals_parent := get_parent()
	if animals_parent:
		for h in animals_parent.get_children():
			if not h.is_in_group("hunters"):
				continue
			if not is_instance_of(h, Node3D):
				continue
			var hn := h as Node3D
			if hn == self:
				continue
			var d_sq := global_position.distance_squared_to(hn.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = hn
	return nearest


func _get_debug_state_string() -> String:
	match _forager_state:
		ForagerState.WANDERING:
			return "Wander"
		ForagerState.EATING:
			return "Eat"
		ForagerState.PANICKING:
			return "Panic"
	return "?"


func _update_debug_visuals(sim: Node) -> void:
	super._update_debug_visuals(sim)
	if _debug_mesh_instance == null or sim == null or not sim.debug_mode:
		return
	var imesh: ImmediateMesh = _debug_mesh_instance.mesh
	if imesh == null:
		return
	if sim.get("debug_show_forager_plant_line") != false and _current_plant != null and is_instance_valid(_current_plant):
		var mat := _make_debug_material(Color(1.0, 0.6, 0.0))  # Orange
		imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		imesh.surface_add_vertex(Vector3.ZERO)
		imesh.surface_add_vertex(to_local(_current_plant.global_position))
		imesh.surface_end()
	if sim.get("debug_show_detection_radii") != false:
		var plant_mat := _make_debug_material(Color(0.4, 0.8, 0.2))  # Green-ish
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, plant_mat)
		for i in range(25):
			var a := TAU * float(i) / 24.0
			imesh.surface_add_vertex(Vector3(cos(a) * plant_detection_range, 0, sin(a) * plant_detection_range))
		imesh.surface_end()
		var hunter_mat := _make_debug_material(Color(0.8, 0.2, 0.2))  # Red-ish
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, hunter_mat)
		for i in range(25):
			var a := TAU * float(i) / 24.0
			imesh.surface_add_vertex(Vector3(cos(a) * hunter_detection_range, 0, sin(a) * hunter_detection_range))
		imesh.surface_end()
	_debug_mesh_instance.mesh = imesh


func _get_nearest_plant() -> Node3D:
	var nearest: Node3D = null
	var best_dist_sq := plant_detection_range * plant_detection_range
	var sim: Node = _get_sim_manager()
	if sim != null and sim.has_method("get_plants_in_radius"):
		var plants_list: Array = sim.get_plants_in_radius(global_position, plant_detection_range)
		for pn in plants_list:
			var d_sq := global_position.distance_squared_to(pn.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = pn
		return nearest
	var plants_node := get_parent().get_parent().get_node_or_null("Plants") if get_parent() and get_parent().get_parent() else null
	if plants_node:
		for p in plants_node.get_children():
			if not is_instance_of(p, Node3D):
				continue
			var pn := p as Node3D
			if not pn.has_method("is_consumed") or pn.is_consumed():
				continue
			var d_sq := global_position.distance_squared_to(pn.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				nearest = pn
	return nearest
