extends Node3D
## Spawns trees, rocks, animals, and plants across the terrain at runtime.
## Uses spawn_seed for reproducible placement. Respects clear_radius around origin.
## Reads terrain bounds and get_height_at from parent's TestTerrain.
## Populates incrementally to avoid freezing the game on startup.

const SpeciesConstants = preload("res://scripts/animals/species_constants.gd")

@export var tree_count: int = 100000
@export var rock_count: int = 100000
@export var animal_count: int = 0
@export var forager_count: int = 750
@export var hunter_count: int = 250
@export var plant_count: int = 1000
@export var terrain_half_size: float = 250.0  ## Overridden from TestTerrain.terrain_size if present
@export var spawn_seed: int = 12345
@export var clear_radius: float = 8.0  ## No spawn within this distance of (0,0,0)
@export var spawn_height_min: float = -1000  ## Valid height range for spawn
@export var spawn_height_max: float = 1000

## How many objects to spawn per frame. Lower = smoother, higher = faster population.
@export var spawns_per_frame: int = 100
## How many position samples to try per frame during generation. Lower = smoother startup.
@export var gen_attempts_per_frame: int = 2000

@export var tree_scene: PackedScene = preload("res://scenes/props/random_tree.tscn")
@export var rock_scene: PackedScene = preload("res://scenes/props/random_rock.tscn")
@export var animal_scene: PackedScene = preload("res://scenes/animals/animal_base.tscn")
@export var forager_scene: PackedScene = preload("res://scenes/animals/forager_animal.tscn")
@export var hunter_scene: PackedScene = preload("res://scenes/animals/hunter_animal.tscn")
@export var plant_scene: PackedScene = preload("res://scenes/plants/plant.tscn")

var _rng: RandomNumberGenerator
var _spawn_queue: Array[Dictionary] = []  ## { "type": String, "pos": Vector3, "species": int }
var _gen_phase: String = "props"  ## "props" | "animals" | "plants" | "spawning" | "done"
var _gen_positions: Array[Vector3] = []
var _gen_needed: int = 0
var _gen_attempts: int = 0


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = spawn_seed
	_apply_terrain_bounds()
	set_process(true)


func _process(_delta: float) -> void:
	if _gen_phase != "spawning" and _gen_phase != "done":
		_process_generation()
	else:
		_process_spawning()


## One frame of position generation for current phase.
func _process_generation() -> void:
	if _gen_phase == "props":
		_start_gen_props()
	if _gen_phase == "animals":
		_start_gen_animals()
	if _gen_phase == "plants":
		_start_gen_plants()

	var attempts_left := gen_attempts_per_frame
	var max_attempts_total := _gen_needed * 20

	while attempts_left > 0 and _gen_attempts < max_attempts_total and _gen_positions.size() < _gen_needed:
		var pos := _get_random_position()
		if _gen_phase == "props" and not _is_clear_of_spawn(pos):
			_gen_attempts += 1
			attempts_left -= 1
			continue
		if _gen_phase == "animals" and not _is_clear_of_spawn(pos):
			_gen_attempts += 1
			attempts_left -= 1
			continue
		if _gen_phase == "plants" and not _is_clear_of_spawn(pos):
			_gen_attempts += 1
			attempts_left -= 1
			continue

		var height := _get_terrain_height_at(pos.x, pos.z)
		if _is_valid_spawn_height(height):
			_gen_positions.append(pos)
		_gen_attempts += 1
		attempts_left -= 1

	# Fallback: allow positions inside clear_radius if we're struggling
	if _gen_positions.size() < _gen_needed and _gen_attempts >= max_attempts_total:
		var fallback := 0
		while _gen_positions.size() < _gen_needed and fallback < max_attempts_total:
			var pos := _get_random_position()
			var height := _get_terrain_height_at(pos.x, pos.z)
			if _is_valid_spawn_height(height):
				_gen_positions.append(pos)
			fallback += 1

	if _gen_positions.size() >= _gen_needed:
		_finish_generation_phase()


func _start_gen_props() -> void:
	if _gen_needed == 0:
		_gen_needed = tree_count + rock_count if (tree_scene and rock_scene) else 0
		_gen_attempts = 0
		_gen_positions.clear()
		if _gen_needed == 0:
			_gen_phase = "animals"
			_gen_needed = 0


func _start_gen_animals() -> void:
	if _gen_phase != "animals":
		return
	if _gen_needed == 0:
		_gen_needed = animal_count + forager_count + hunter_count
		_gen_attempts = 0
		_gen_positions.clear()
		if _gen_needed == 0:
			_gen_phase = "plants"
			_gen_needed = 0


func _start_gen_plants() -> void:
	if _gen_phase != "plants":
		return
	if _gen_needed == 0:
		_gen_needed = plant_count if (plant_scene and plant_count > 0) else 0
		_gen_attempts = 0
		_gen_positions.clear()
		if _gen_needed == 0:
			_gen_phase = "spawning"
			return


func _finish_generation_phase() -> void:
	if _gen_phase == "props":
		_build_props_spawn_queue()
		_gen_phase = "animals"
		_gen_needed = 0
		_gen_positions.clear()
		_gen_attempts = 0
	elif _gen_phase == "animals":
		_build_animals_spawn_queue()
		_gen_phase = "plants"
		_gen_needed = 0
		_gen_positions.clear()
		_gen_attempts = 0
	elif _gen_phase == "plants":
		_build_plants_spawn_queue()
		_gen_phase = "spawning"
		_gen_needed = 0
		_gen_positions.clear()


func _build_props_spawn_queue() -> void:
	var props := get_parent().get_node_or_null("TestTerrain/Props") as Node3D
	if not props or not tree_scene or not rock_scene:
		return

	for i in tree_count:
		if i < _gen_positions.size():
			var pos := _gen_positions[i]
			pos.y = _get_terrain_height_at(pos.x, pos.z)
			_spawn_queue.append({"type": "tree", "pos": pos})
	for i in rock_count:
		var idx := tree_count + i
		if idx < _gen_positions.size():
			var pos := _gen_positions[idx]
			pos.y = _get_terrain_height_at(pos.x, pos.z)
			_spawn_queue.append({"type": "rock", "pos": pos})


func _build_animals_spawn_queue() -> void:
	var animals := get_parent().get_node_or_null("Animals") as Node3D
	if not animals:
		return

	var idx := 0
	for i in animal_count:
		if idx >= _gen_positions.size():
			break
		if animal_scene:
			var pos := _gen_positions[idx]
			pos.y = _get_terrain_height_at(pos.x, pos.z) + 0.3
			_spawn_queue.append({"type": "animal", "pos": pos, "species": SpeciesConstants.Species.BISON})
		idx += 1
	for i in forager_count:
		if idx >= _gen_positions.size():
			break
		if forager_scene:
			var sp := _rng.randi() % 3
			var species: int = [SpeciesConstants.Species.DEER, SpeciesConstants.Species.RABBIT, SpeciesConstants.Species.DEER][sp]
			var pos := _gen_positions[idx]
			pos.y = _get_terrain_height_at(pos.x, pos.z) + 0.3
			_spawn_queue.append({"type": "forager", "pos": pos, "species": species})
		idx += 1
	for i in hunter_count:
		if idx >= _gen_positions.size():
			break
		if hunter_scene:
			var sp := _rng.randi() % 2
			var species: int = [SpeciesConstants.Species.WOLF, SpeciesConstants.Species.BEAR][sp]
			var pos := _gen_positions[idx]
			pos.y = _get_terrain_height_at(pos.x, pos.z) + 0.3
			_spawn_queue.append({"type": "hunter", "pos": pos, "species": species})
		idx += 1


func _build_plants_spawn_queue() -> void:
	if not plant_scene or plant_count <= 0:
		return

	for i in _gen_positions.size():
		if i >= plant_count:
			break
		var pos := _gen_positions[i]
		pos.y = _get_terrain_height_at(pos.x, pos.z)
		_spawn_queue.append({"type": "plant", "pos": pos})


func _process_spawning() -> void:
	if _spawn_queue.is_empty():
		_gen_phase = "done"
		set_process(false)
		return

	var props := get_parent().get_node_or_null("TestTerrain/Props") as Node3D
	var animals := get_parent().get_node_or_null("Animals") as Node3D
	var plants := get_parent().get_node_or_null("Plants") as Node3D

	var spawned := 0
	while spawned < spawns_per_frame and not _spawn_queue.is_empty():
		var task: Dictionary = _spawn_queue.pop_front()
		var type_str: String = task.get("type", "")
		var pos: Vector3 = task.get("pos", Vector3.ZERO)
		var species: int = task.get("species", -1)

		if type_str == "tree" and tree_scene and props:
			var tree := tree_scene.instantiate() as Node3D
			tree.position = pos
			props.add_child(tree)
			spawned += 1
		elif type_str == "rock" and rock_scene and props:
			var rock := rock_scene.instantiate() as Node3D
			rock.position = pos
			props.add_child(rock)
			spawned += 1
		elif type_str == "animal" and animal_scene and animals:
			_spawn_animal_at(animals, animal_scene, pos, species)
			spawned += 1
		elif type_str == "forager" and forager_scene and animals:
			_spawn_animal_at(animals, forager_scene, pos, species)
			spawned += 1
		elif type_str == "hunter" and hunter_scene and animals:
			_spawn_animal_at(animals, hunter_scene, pos, species)
			spawned += 1
		elif type_str == "plant" and plant_scene and plants:
			var plant := plant_scene.instantiate() as Node3D
			plant.position = pos
			plants.add_child(plant)
			spawned += 1

	if _spawn_queue.is_empty():
		_gen_phase = "done"
		set_process(false)


## Set terrain_half_size from TestTerrain.terrain_size if available.
func _apply_terrain_bounds() -> void:
	var terrain := get_parent().get_node_or_null("TestTerrain")
	if terrain and "terrain_size" in terrain:
		terrain_half_size = terrain.terrain_size * 0.5


## Random X,Z within terrain bounds; Y=0 (height applied later).
func _get_random_position() -> Vector3:
	var x := _rng.randf_range(-terrain_half_size, terrain_half_size)
	var z := _rng.randf_range(-terrain_half_size, terrain_half_size)
	return Vector3(x, 0.0, z)


## True if pos is outside clear_radius from origin.
func _is_clear_of_spawn(pos: Vector3) -> bool:
	var spawn := Vector3(0.0, 0.0, 0.0)
	return pos.distance_to(spawn) >= clear_radius


func _is_valid_spawn_height(height: float) -> bool:
	return height >= spawn_height_min and height <= spawn_height_max


## Get height from TestTerrain.get_height_at or 0 if unavailable.
func _get_terrain_height_at(x: float, z: float) -> float:
	var terrain := get_parent().get_node_or_null("TestTerrain")
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(x, z)
	return 0.0


## Instantiate animal scene at pos, set species property, add to container.
func _spawn_animal_at(container: Node3D, scene: PackedScene, pos: Vector3, species: int) -> void:
	var animal := scene.instantiate() as Node3D
	animal.position = pos
	if "species" in animal:
		animal.species = species
	container.add_child(animal)
