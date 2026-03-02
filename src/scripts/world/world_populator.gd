extends Node3D
## Spawns trees, rocks, animals, and plants across the terrain at runtime.
## Uses spawn_seed for reproducible placement. Respects clear_radius around origin.
## Reads terrain bounds and get_height_at from parent's TestTerrain.

const SpeciesConstants = preload("res://scripts/animals/species_constants.gd")

@export var tree_count: int = 100
@export var rock_count: int = 100
@export var animal_count: int = 0
@export var forager_count: int = 750
@export var hunter_count: int = 250
@export var plant_count: int = 1000
@export var terrain_half_size: float = 250.0  ## Overridden from TestTerrain.terrain_size if present
@export var spawn_seed: int = 12345
@export var clear_radius: float = 8.0  ## No spawn within this distance of (0,0,0)
@export var spawn_height_min: float = -1000  ## Valid height range for spawn
@export var spawn_height_max: float = 1000

@export var tree_scene: PackedScene = preload("res://scenes/props/random_tree.tscn")
@export var rock_scene: PackedScene = preload("res://scenes/props/random_rock.tscn")
@export var animal_scene: PackedScene = preload("res://scenes/animals/animal_base.tscn")
@export var forager_scene: PackedScene = preload("res://scenes/animals/forager_animal.tscn")
@export var hunter_scene: PackedScene = preload("res://scenes/animals/hunter_animal.tscn")
@export var plant_scene: PackedScene = preload("res://scenes/plants/plant.tscn")

var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = spawn_seed
	_apply_terrain_bounds()

	if tree_scene and rock_scene:
		_populate_props()
	_populate_animals()
	if plant_scene and plant_count > 0:
		_populate_plants()


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


func _populate_props() -> void:
	var props := get_parent().get_node_or_null("TestTerrain/Props") as Node3D
	if not props:
		push_error("WorldPopulator: Props node not found")
		return

	var positions: Array[Vector3] = []
	var needed := tree_count + rock_count
	var max_attempts := needed * 20
	for i in max_attempts:
		if positions.size() >= needed:
			break
		var pos := _get_random_position()
		if _is_clear_of_spawn(pos):
			var height := _get_terrain_height_at(pos.x, pos.z)
			if _is_valid_spawn_height(height):
				positions.append(pos)

	var fallback_attempts := 0
	while positions.size() < needed and fallback_attempts < max_attempts:
		var pos := _get_random_position()
		var height := _get_terrain_height_at(pos.x, pos.z)
		if _is_valid_spawn_height(height):
			positions.append(pos)
		fallback_attempts += 1

	var tree_positions: Array[Vector3] = []
	var rock_positions: Array[Vector3] = []
	for i in tree_count:
		if i < positions.size():
			tree_positions.append(positions[i])
	for i in rock_count:
		var idx := tree_count + i
		if idx < positions.size():
			rock_positions.append(positions[idx])

	for pos in tree_positions:
		pos.y = _get_terrain_height_at(pos.x, pos.z)
		var tree := tree_scene.instantiate() as Node3D
		tree.position = pos
		props.add_child(tree)

	for pos in rock_positions:
		pos.y = _get_terrain_height_at(pos.x, pos.z)
		var rock := rock_scene.instantiate() as Node3D
		rock.position = pos
		props.add_child(rock)


func _populate_plants() -> void:
	var plants := get_parent().get_node_or_null("Plants") as Node3D
	if not plants:
		push_error("WorldPopulator: Plants node not found")
		return

	var positions: Array[Vector3] = []
	var max_attempts := plant_count * 20
	for i in max_attempts:
		if positions.size() >= plant_count:
			break
		var pos := _get_random_position()
		if _is_clear_of_spawn(pos):
			var height := _get_terrain_height_at(pos.x, pos.z)
			if _is_valid_spawn_height(height):
				positions.append(pos)

	var fallback_attempts := 0
	while positions.size() < plant_count and fallback_attempts < max_attempts:
		var pos := _get_random_position()
		var height := _get_terrain_height_at(pos.x, pos.z)
		if _is_valid_spawn_height(height):
			positions.append(pos)
		fallback_attempts += 1

	for pos in positions:
		pos.y = _get_terrain_height_at(pos.x, pos.z)
		var plant := plant_scene.instantiate() as Node3D
		plant.position = pos
		plants.add_child(plant)


func _populate_animals() -> void:
	var animals := get_parent().get_node_or_null("Animals") as Node3D
	if not animals:
		push_error("WorldPopulator: Animals node not found")
		return

	var total := animal_count + forager_count + hunter_count
	var positions: Array[Vector3] = []
	var max_attempts := total * 20
	for i in max_attempts:
		if positions.size() >= total:
			break
		var pos := _get_random_position()
		if _is_clear_of_spawn(pos):
			var height := _get_terrain_height_at(pos.x, pos.z)
			if _is_valid_spawn_height(height):
				positions.append(pos)

	var fallback_attempts := 0
	while positions.size() < total and fallback_attempts < max_attempts:
		var pos := _get_random_position()
		var height := _get_terrain_height_at(pos.x, pos.z)
		if _is_valid_spawn_height(height):
			positions.append(pos)
		fallback_attempts += 1

	var idx := 0
	for i in animal_count:
		if idx >= positions.size():
			break
		if animal_scene:
			_spawn_animal_at(animals, animal_scene, positions[idx], SpeciesConstants.Species.BISON)
		idx += 1
	for i in forager_count:
		if idx >= positions.size():
			break
		if forager_scene:
			var sp := _rng.randi() % 3
			var forager_species: int = [SpeciesConstants.Species.DEER, SpeciesConstants.Species.RABBIT, SpeciesConstants.Species.DEER][sp]
			_spawn_animal_at(animals, forager_scene, positions[idx], forager_species)
		idx += 1
	for i in hunter_count:
		if idx >= positions.size():
			break
		if hunter_scene:
			var sp := _rng.randi() % 2
			var hunter_species: int = [SpeciesConstants.Species.WOLF, SpeciesConstants.Species.BEAR][sp]
			_spawn_animal_at(animals, hunter_scene, positions[idx], hunter_species)
		idx += 1


## Instantiate animal scene at pos (Y from terrain + 0.3), set species property, add to container.
func _spawn_animal_at(container: Node3D, scene: PackedScene, pos: Vector3, species: int) -> void:
	var animal := scene.instantiate() as Node3D
	pos.y = _get_terrain_height_at(pos.x, pos.z) + 0.3
	animal.position = pos
	if "species" in animal:
		animal.species = species
	container.add_child(animal)
