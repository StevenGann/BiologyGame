extends Node
## Spatial partitioning and LOD for animals/plants.
## Enables efficient nearby queries and reduced simulation for distant entities.

const CELL_SIZE: float = 24.0

enum LODTier { FULL, MEDIUM, FAR }

@export var full_sim_radius: float = 30.0
@export var medium_sim_radius: float = 90.0

@export_group("LOD Update Intervals")
@export var full_ai_interval: int = 30
@export var full_move_interval: int = 10
@export var medium_ai_interval: int = 90
@export var medium_move_interval: int = 30
@export var far_ai_interval: int = 1500
@export var far_move_interval: int = 100

var _animal_cells: Dictionary = {}
var _plant_cells: Dictionary = {}
var _frame_counter: int = 0
var _cached_player: Node3D = null
var _cached_player_pos: Vector3 = Vector3.ZERO
var _animals_node: Node = null
var _plants_node: Node = null

@export var grid_rebuild_interval: int = 4

var debug_mode: bool = false

@export_group("Debug Visualizations")
@export var debug_show_state: bool = true
@export var debug_show_species: bool = true
@export var debug_show_panic_timer: bool = true
@export var debug_show_threat_line: bool = true
@export var debug_show_cohesion_line: bool = true
@export var debug_show_detection_radii: bool = true
@export var debug_show_hunter_prey_line: bool = true
@export var debug_show_forager_plant_line: bool = true
@export var debug_show_nearby_species: bool = true


func toggle_debug_mode() -> void:
	debug_mode = not debug_mode


func _ready() -> void:
	add_to_group("simulation_manager")
	_animals_node = get_parent().get_node_or_null("Animals")
	_plants_node = get_parent().get_node_or_null("Plants")
	set_process_priority(-100)


func _physics_process(delta: float) -> void:
	_frame_counter += 1
	if _cached_player and is_instance_valid(_cached_player):
		_cached_player_pos = _cached_player.global_position
	elif _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("player") as Node3D
		if _cached_player:
			_cached_player_pos = _cached_player.global_position
	if _frame_counter % grid_rebuild_interval == 0:
		_rebuild_grid()
	_process_far_animals(delta)


func _process_far_animals(delta: float) -> void:
	if not _animals_node:
		return
	var terrain := get_parent().get_node_or_null("TestTerrain")
	for a in _animals_node.get_children():
		if not is_instance_of(a, CharacterBody3D) or not is_instance_valid(a):
			continue
		var lod: LODTier = get_lod_tier(a.global_position)
		if lod == LODTier.FAR:
			if "WasFarLod" in a:
				a.set("WasFarLod", true)
			elif "_was_far_lod" in a:
				a.set("_was_far_lod", true)
			a.set_physics_process(false)
			if a.has_method("process_far_tick"):
				var instance_id: int = a.get_instance_id()
				var ai_tick: bool = should_ai_tick_this_frame(lod, instance_id)
				var move_tick: bool = should_movement_tick_this_frame(lod, instance_id)
				a.process_far_tick(delta, ai_tick, move_tick)
		else:
			if "WasFarLod" in a and a.get("WasFarLod"):
				a.set("WasFarLod", false)
			elif "_was_far_lod" in a and a.get("_was_far_lod"):
				a.set("_was_far_lod", false)
				if terrain and terrain.has_method("get_height_at"):
					var pos: Vector3 = a.global_position
					a.global_position.y = terrain.get_height_at(pos.x, pos.z) + 0.3
			a.set_physics_process(true)


func _rebuild_grid() -> void:
	_animal_cells.clear()
	_plant_cells.clear()
	if _animals_node:
		for a in _animals_node.get_children():
			if is_instance_of(a, Node3D) and is_instance_valid(a):
				var an := a as Node3D
				var species := 0
				if "species" in an:
					species = an.species
				var is_hunter := a.is_in_group("hunters")
				_register_animal_internal(an, species, is_hunter)
	if _plants_node:
		for p in _plants_node.get_children():
			if is_instance_of(p, Node3D) and is_instance_valid(p):
				_register_plant_internal(p as Node3D)


func _register_animal_internal(animal: Node3D, animal_species: int, is_hunter: bool) -> void:
	var key := _cell_key(animal.global_position)
	if not _animal_cells.has(key):
		_animal_cells[key] = []
	_animal_cells[key].append({
		"n": animal,
		"s": animal_species,
		"h": is_hunter
	})


func _register_plant_internal(plant: Node3D) -> void:
	var key := _cell_key(plant.global_position)
	if not _plant_cells.has(key):
		_plant_cells[key] = []
	_plant_cells[key].append({"n": plant})


func _cell_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))


func _cells_in_radius(center: Vector3, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cx := int(floor(center.x / CELL_SIZE))
	var cz := int(floor(center.z / CELL_SIZE))
	var cell_radius := int(ceil(radius / CELL_SIZE)) + 1
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			result.append(Vector2i(cx + dx, cz + dz))
	return result


func get_animals_in_radius(center: Vector3, radius: float, exclude: Node = null) -> Array:
	var result: Array = []
	var r_sq := radius * radius
	var cells := _cells_in_radius(center, radius)
	for ck in cells:
		if not _animal_cells.has(ck):
			continue
		for entry in _animal_cells[ck]:
			var n = entry.n
			if not is_instance_valid(n):
				continue
			if n == exclude:
				continue
			if center.distance_squared_to(n.global_position) <= r_sq:
				result.append(n)
	return result


func get_hunters_in_radius(center: Vector3, radius: float) -> Array:
	var result: Array = []
	var r_sq := radius * radius
	var cells := _cells_in_radius(center, radius)
	for ck in cells:
		if not _animal_cells.has(ck):
			continue
		for entry in _animal_cells[ck]:
			if not entry.h:
				continue
			var n = entry.n
			if not is_instance_valid(n):
				continue
			if center.distance_squared_to(n.global_position) <= r_sq:
				result.append(n)
	return result


func get_same_species_in_radius(center: Vector3, radius: float, species: int, exclude: Node = null) -> Array:
	var result: Array = []
	var r_sq := radius * radius
	var cells := _cells_in_radius(center, radius)
	for ck in cells:
		if not _animal_cells.has(ck):
			continue
		for entry in _animal_cells[ck]:
			if entry.s != species:
				continue
			var n = entry.n
			if not is_instance_valid(n):
				continue
			if n == exclude:
				continue
			if center.distance_squared_to(n.global_position) <= r_sq:
				result.append(n)
	return result


func get_plants_in_radius(center: Vector3, radius: float) -> Array:
	var result: Array = []
	var r_sq := radius * radius
	var cells := _cells_in_radius(center, radius)
	for ck in cells:
		if not _plant_cells.has(ck):
			continue
		for entry in _plant_cells[ck]:
			var n = entry.n
			if not is_instance_valid(n):
				continue
			if n.has_method("is_consumed") and n.is_consumed():
				continue
			if center.distance_squared_to(n.global_position) <= r_sq:
				result.append(n)
	return result


func get_lod_tier(node_pos: Vector3) -> LODTier:
	if _cached_player == null or not is_instance_valid(_cached_player):
		return LODTier.FULL
	var dist_sq := node_pos.distance_squared_to(_cached_player_pos)
	var full_sq := full_sim_radius * full_sim_radius
	var med_sq := medium_sim_radius * medium_sim_radius
	if dist_sq < full_sq:
		return LODTier.FULL
	if dist_sq < med_sq:
		return LODTier.MEDIUM
	return LODTier.FAR


func should_ai_tick_this_frame(lod: LODTier, instance_id: int) -> bool:
	var interval: int
	match lod:
		LODTier.FULL:
			interval = full_ai_interval
		LODTier.MEDIUM:
			interval = medium_ai_interval
		LODTier.FAR:
			interval = far_ai_interval
		_:
			return true
	return (_frame_counter + instance_id) % maxi(1, interval) == 0


func should_movement_tick_this_frame(lod: LODTier, instance_id: int) -> bool:
	var interval: int
	match lod:
		LODTier.FULL:
			interval = full_move_interval
		LODTier.MEDIUM:
			interval = medium_move_interval
		LODTier.FAR:
			interval = far_move_interval
		_:
			return true
	return (_frame_counter + instance_id) % maxi(1, interval) == 0
