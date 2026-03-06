extends Node3D
## Populates the world with trees, rocks, animals, and plants.
##
## PROPS (trees, rocks):
##   No longer instantiates individual scene nodes. Instead:
##   Phase 1 — Writes transforms to PropMultimeshRenderer (GPU instancing, ~20 draw calls total).
##   Phase 2 — Writes raw position data into PropDataStore; WorldChunkManager handles streaming.
##   Both modes run simultaneously: PropDataStore is always built for streaming, and the chunk
##   manager handles all MultiMesh node creation and destruction.
##
## ANIMALS / PLANTS:
##   Still instantiated as individual scene nodes (each animal needs a CharacterBody3D for
##   physics and AI). Staggered spawning prevents frame spikes.
##
## Startup sequence:
##   1. _process_generation() — generate positions using seeded RNG, staggered over frames.
##   2. _finish_generation_phase() — when enough positions are gathered, enqueue spawns.
##   3. _process_spawning() — drain the spawn queue at spawns_per_frame rate.
##   4. When done, WorldChunkManager.set_data_store() is called to begin streaming.

const SpeciesConstants = preload("res://scripts/animals/species_constants.gd")
const PropDataStore = preload("res://scripts/world/prop_data_store.gd")

@export var tree_count: int = 100000
@export var rock_count: int = 100000
@export var animal_count: int = 0
@export var forager_count: int = 750
@export var hunter_count: int = 250
@export var plant_count: int = 1000
@export var terrain_half_size: float = 250.0
@export var spawn_seed: int = 12345
@export var clear_radius: float = 8.0
@export var spawn_height_min: float = -1000
@export var spawn_height_max: float = 1000

## Chunk size (meters). Must match WorldChunkManager.chunk_size.
@export var chunk_size: float = 128.0

## How many animal/plant nodes to add per frame.
@export var spawns_per_frame: int = 100
## How many prop position samples to generate per frame.
@export var gen_attempts_per_frame: int = 2000

## Animal scenes (props use MultiMesh, not PackedScene).
@export var animal_scene: PackedScene = preload("res://scenes/animals/animal_base.tscn")
@export var forager_scene: PackedScene = preload("res://scenes/animals/forager_animal.tscn")
@export var hunter_scene: PackedScene = preload("res://scenes/animals/hunter_animal.tscn")
@export var plant_scene: PackedScene = preload("res://scenes/plants/plant.tscn")

## Tree scale parameters (must match old random_tree.gd values for visual consistency).
const TREE_BASE_SCALE: float = 3.5
const TREE_SCALE_MIN: float = 1.5
const TREE_SCALE_MAX: float = 2.5
## Rock scale parameters (must match old random_rock.gd values).
const ROCK_BASE_SCALE: float = 2.5
const ROCK_SCALE_MIN: float = 0.5
const ROCK_SCALE_MAX: float = 1.5

## Number of tree/rock variants (must match PropMultimeshRenderer constants).
const TREE_VARIANT_COUNT: int = 9
const ROCK_VARIANT_COUNT: int = 39

var _rng: RandomNumberGenerator
var _spawn_queue: Array[Dictionary] = []
var _gen_phase: String = "props"  ## "props" | "animals" | "plants" | "spawning" | "done"
var _gen_positions: Array[Vector3] = []
var _gen_needed: int = 0
var _gen_attempts: int = 0

## The shared data store; handed to WorldChunkManager once props are done.
var _data_store: PropDataStore = null


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = spawn_seed
	_apply_terrain_bounds()
	_data_store = PropDataStore.new()
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
		if not _is_clear_of_spawn(pos):
			_gen_attempts += 1
			attempts_left -= 1
			continue
		var height := _get_terrain_height_at(pos.x, pos.z)
		if _is_valid_spawn_height(height):
			_gen_positions.append(pos)
		_gen_attempts += 1
		attempts_left -= 1

	# Fallback: allow positions inside clear_radius if struggling.
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
		_gen_needed = tree_count + rock_count
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
		_build_props_data()         ## Write to PropDataStore (no scene nodes)
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


## Write all prop positions into PropDataStore (replaces scene node instantiation).
## Uses seeded per-position RNG for deterministic variant + scale selection.
func _build_props_data() -> void:
	var prop_rng := RandomNumberGenerator.new()

	for i in tree_count:
		if i >= _gen_positions.size():
			break
		var pos := _gen_positions[i]
		pos.y = _get_terrain_height_at(pos.x, pos.z)

		# Deterministic variant + scale from position hash.
		prop_rng.seed = _pos_seed(pos)
		var variant_idx := prop_rng.randi() % TREE_VARIANT_COUNT
		var scale_mult := prop_rng.randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX)

		var chunk := _pos_to_chunk(pos)
		_data_store.add_tree(chunk, pos, variant_idx, scale_mult)

	for i in rock_count:
		var idx := tree_count + i
		if idx >= _gen_positions.size():
			break
		var pos := _gen_positions[idx]
		pos.y = _get_terrain_height_at(pos.x, pos.z)

		prop_rng.seed = _pos_seed(pos)
		var variant_idx := prop_rng.randi() % ROCK_VARIANT_COUNT
		var scale_mult := prop_rng.randf_range(ROCK_SCALE_MIN, ROCK_SCALE_MAX)

		var chunk := _pos_to_chunk(pos)
		_data_store.add_rock(chunk, pos, variant_idx, scale_mult)

	# Hand the populated store to WorldChunkManager so streaming can begin.
	var chunk_manager := get_parent().get_node_or_null("WorldChunkManager")
	if chunk_manager and chunk_manager.has_method("set_data_store"):
		chunk_manager.set_data_store(_data_store)


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


## Drain animal/plant spawn queue at spawns_per_frame rate.
func _process_spawning() -> void:
	if _spawn_queue.is_empty():
		_gen_phase = "done"
		set_process(false)
		return

	var animals := get_parent().get_node_or_null("Animals") as Node3D
	var plants := get_parent().get_node_or_null("Plants") as Node3D

	var spawned := 0
	while spawned < spawns_per_frame and not _spawn_queue.is_empty():
		var task: Dictionary = _spawn_queue.pop_front()
		var type_str: String = task.get("type", "")
		var pos: Vector3 = task.get("pos", Vector3.ZERO)
		var species: int = task.get("species", -1)

		if type_str == "animal" and animal_scene and animals:
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


func _apply_terrain_bounds() -> void:
	var terrain := get_parent().get_node_or_null("TestTerrain")
	if terrain and "terrain_size" in terrain:
		terrain_half_size = terrain.terrain_size * 0.5


func _get_random_position() -> Vector3:
	var x := _rng.randf_range(-terrain_half_size, terrain_half_size)
	var z := _rng.randf_range(-terrain_half_size, terrain_half_size)
	return Vector3(x, 0.0, z)


func _is_clear_of_spawn(pos: Vector3) -> bool:
	return pos.distance_to(Vector3.ZERO) >= clear_radius


func _is_valid_spawn_height(height: float) -> bool:
	return height >= spawn_height_min and height <= spawn_height_max


func _get_terrain_height_at(x: float, z: float) -> float:
	var terrain := get_parent().get_node_or_null("TestTerrain")
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(x, z)
	return 0.0


func _spawn_animal_at(container: Node3D, scene: PackedScene, pos: Vector3, species: int) -> void:
	var animal := scene.instantiate() as Node3D
	animal.position = pos
	if "species" in animal:
		animal.species = species
	container.add_child(animal)


## Deterministic integer seed from world position (for prop variant/scale selection).
func _pos_seed(pos: Vector3) -> int:
	return hash(Vector3i(int(pos.x), int(pos.y), int(pos.z)))


## Convert world position to chunk grid coordinate.
func _pos_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / chunk_size)), int(floor(pos.z / chunk_size)))
