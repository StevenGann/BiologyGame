extends Node
## Spatial partitioning and LOD for animals/plants.
## Enables efficient nearby queries and reduced simulation for distant entities.

const CELL_SIZE: float = 24.0

enum LODTier { FULL, MEDIUM, FAR }

@export var full_sim_radius: float = 50.0  ## Distance threshold for FULL LOD
@export var medium_sim_radius: float = 200.0  ## Distance threshold for MEDIUM LOD

@export_group("Dynamic LOD")
@export var dynamic_lod_enabled: bool = true  ## Opt-in toggle for dynamic radius adjustment
@export var target_fps: float = 60.0  ## Baseline FPS for scaling
@export var min_full_sim_radius: float = 20.0  ## Minimum full LOD radius
@export var min_medium_sim_radius: float = 80.0  ## Minimum medium LOD radius
@export var radius_adjust_interval: int = 30  ## Frames between recalculations
@export var radius_smoothing: float = 0.1  ## Lerp factor (lower = smoother)

signal medium_sim_radius_changed(new_radius: float)

@export_group("LOD Update Intervals")
@export var full_ai_interval: int = 30  ## Frames between FULL AI ticks
@export var full_move_interval: int = 10  ## Frames between FULL movement ticks
@export var medium_ai_interval: int = 90
@export var medium_move_interval: int = 30
@export var far_ai_interval: int = 1500
@export var far_move_interval: int = 100

var _animal_cells: Dictionary = {}  ## cell_key -> [{n, s, h}, ...] (node, species, is_hunter)
var _plant_cells: Dictionary = {}  ## cell_key -> [{n}, ...]
var _frame_counter: int = 0
var _cached_player: Node3D = null
var _cached_player_pos: Vector3 = Vector3.ZERO
var _animals_node: Node = null
var _plants_node: Node = null

# Dynamic LOD internal state
var _smoothed_fps: float = 60.0
var _max_full_sim_radius: float = 50.0  ## Captured at _ready, used as scaling ceiling
var _max_medium_sim_radius: float = 200.0  ## Captured at _ready, used as scaling ceiling
var _last_emitted_medium_radius: float = 200.0

@export var grid_rebuild_interval: int = 4  ## Rebuild grid every N physics frames

@export_group("LOD Visibility Bias")
@export var frustum_lod_bias_enabled: bool = true  ## Treat animals outside camera frustum as FAR
@export var occlusion_lod_bias_enabled: bool = true  ## Treat terrain-occluded animals as FAR
@export var occlusion_check_interval_frames: int = 5  ## Throttle occlusion checks per animal

var debug_mode: bool = false

@export_group("Debug Visualizations")
@export var debug_close_radius: float = 15.0  ## Always show debug within this distance (meters)
@export var debug_far_radius: float = 50.0  ## Max distance for debug when in view frustum
@export var debug_show_state: bool = true
@export var debug_show_species: bool = true
@export var debug_show_panic_timer: bool = true
@export var debug_show_threat_line: bool = true
@export var debug_show_cohesion_line: bool = true
@export var debug_show_detection_radii: bool = true
@export var debug_show_hunter_prey_line: bool = true
@export var debug_show_forager_plant_line: bool = true
@export var debug_show_nearby_species: bool = true


## Toggle debug overlays (LOD labels, threat/cohesion lines, radii). Bound to backtick in main.gd.
func toggle_debug_mode() -> void:
	debug_mode = not debug_mode


func _ready() -> void:
	add_to_group("simulation_manager")
	_animals_node = get_parent().get_node_or_null("Animals")
	_plants_node = get_parent().get_node_or_null("Plants")
	set_process_priority(-100)  ## Run before FarSimBridge (-50) and animals (0)
	# Capture initial radii as max values for dynamic LOD scaling
	_max_full_sim_radius = full_sim_radius
	_max_medium_sim_radius = medium_sim_radius
	_last_emitted_medium_radius = medium_sim_radius
	_smoothed_fps = target_fps
	# Sync LOD visibility bias from CullingConfig
	var config := get_node_or_null("/root/CullingConfig")
	if config:
		frustum_lod_bias_enabled = config.get("frustum_lod_bias_enabled")
		occlusion_lod_bias_enabled = config.get("occlusion_lod_bias_enabled")
		occlusion_check_interval_frames = config.get("occlusion_check_interval_frames")


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
	_update_dynamic_lod(delta)


## For FAR LOD animals: disable physics_process, call process_far_tick. Re-enable and snap to terrain when not FAR.
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


## Rebuild _animal_cells and _plant_cells from Animals and Plants node children.
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


## Return cell keys that could contain points within radius of center.
func _cells_in_radius(center: Vector3, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cx := int(floor(center.x / CELL_SIZE))
	var cz := int(floor(center.z / CELL_SIZE))
	var cell_radius := int(ceil(radius / CELL_SIZE)) + 1
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			result.append(Vector2i(cx + dx, cz + dz))
	return result


## Returns all animals within radius. Uses spatial grid; exclude is optional (e.g. self).
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


## Returns animals in "hunters" group within radius.
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


## Returns animals of given species within radius. Used for cohesion and contagion.
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


## Returns non-consumed plants within radius (is_consumed() must be false).
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


## Returns LOD tier based on distance, optional frustum bias, and optional occlusion bias.
func get_lod_tier(node_pos: Vector3) -> LODTier:
	if _cached_player == null or not is_instance_valid(_cached_player):
		return LODTier.FULL
	var dist_sq := node_pos.distance_squared_to(_cached_player_pos)
	var full_sq := full_sim_radius * full_sim_radius
	var med_sq := medium_sim_radius * medium_sim_radius
	var lod: LODTier
	if dist_sq < full_sq:
		lod = LODTier.FULL
	elif dist_sq < med_sq:
		lod = LODTier.MEDIUM
	else:
		return LODTier.FAR

	if frustum_lod_bias_enabled:
		var cam := get_viewport().get_camera_3d()
		if cam and not cam.is_position_in_frustum(node_pos):
			return LODTier.FAR

	if occlusion_lod_bias_enabled and lod != LODTier.FAR:
		var seed_val := int(hash(Vector2i(int(node_pos.x), int(node_pos.z)))) & 0x7FFFFFFF
		if (_frame_counter + seed_val) % maxi(1, occlusion_check_interval_frames) == 0:
			var terrain := get_parent().get_node_or_null("TestTerrain")
			if terrain and terrain.has_method("get_height_at"):
				if _is_occluded_by_terrain(node_pos, terrain):
					return LODTier.FAR

	return lod


## True if target is occluded by terrain (ray from camera to target intersects terrain above ray).
func _is_occluded_by_terrain(target: Vector3, terrain: Node) -> bool:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return false
	var cam_pos := cam.global_position
	var dx := target.x - cam_pos.x
	var dz := target.z - cam_pos.z
	var dist_2d := sqrt(dx * dx + dz * dz)
	if dist_2d < 1.0:
		return false
	var steps := maxi(2, int(dist_2d / 2.0))
	var step_x := dx / float(steps)
	var step_z := dz / float(steps)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var x := cam_pos.x + step_x * float(i)
		var z := cam_pos.z + step_z * float(i)
		var ray_y := lerpf(cam_pos.y, target.y, t)
		var terrain_y: float = terrain.get_height_at(x, z)
		if terrain_y > ray_y + 0.5:
			return true
	return false


## Whether AI should tick this frame for given LOD. Uses (frame_counter + instance_id) % interval for staggering.
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


## Whether movement should tick this frame for given LOD.
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


## Update dynamic LOD radii based on framerate.
func _update_dynamic_lod(delta: float) -> void:
	if not dynamic_lod_enabled:
		return

	# Update EMA of FPS every frame (trivial cost)
	if delta > 0.0:
		_smoothed_fps = lerpf(_smoothed_fps, 1.0 / delta, 0.05)

	# Only recalculate radii every N frames
	if _frame_counter % radius_adjust_interval != 0:
		return

	# Compute scale factor: clamp(smoothed_fps / target_fps, 0.0, 1.0)
	var scale: float = clampf(_smoothed_fps / target_fps, 0.0, 1.0)

	# Compute target radii
	var target_full := maxf(min_full_sim_radius, _max_full_sim_radius * scale)
	var target_medium := maxf(min_medium_sim_radius, _max_medium_sim_radius * scale)

	# Smoothly lerp current radii toward targets
	full_sim_radius = lerpf(full_sim_radius, target_full, radius_smoothing)
	medium_sim_radius = lerpf(medium_sim_radius, target_medium, radius_smoothing)

	# Emit signal if medium radius changed significantly (>1 meter)
	if absf(medium_sim_radius - _last_emitted_medium_radius) > 1.0:
		_last_emitted_medium_radius = medium_sim_radius
		medium_sim_radius_changed.emit(medium_sim_radius)
