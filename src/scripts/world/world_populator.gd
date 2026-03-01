extends Node3D
## Spawns trees, rocks, and animals across the terrain at runtime.
## Uses a seed for reproducible placement.

@export var tree_count: int = 3000
@export var rock_count: int = 1000
@export var animal_count: int = 100
@export var terrain_half_size: float = 250.0
@export var spawn_seed: int = 12345
@export var clear_radius: float = 8.0
@export var spawn_height_min: float = -5
@export var spawn_height_max: float = 45

@export var tree_scene: PackedScene = preload("res://scenes/props/random_tree.tscn")
@export var rock_scene: PackedScene = preload("res://scenes/props/random_rock.tscn")
@export var animal_scene: PackedScene = preload("res://scenes/animals/animal_base.tscn")

var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = spawn_seed
	_apply_terrain_bounds()

	if tree_scene and rock_scene:
		_populate_props()
	if animal_scene:
		_populate_animals()


func _apply_terrain_bounds() -> void:
	var terrain := get_parent().get_node_or_null("TestTerrain")
	if terrain and "terrain_size" in terrain:
		terrain_half_size = terrain.terrain_size * 0.5


func _get_random_position() -> Vector3:
	var x := _rng.randf_range(-terrain_half_size, terrain_half_size)
	var z := _rng.randf_range(-terrain_half_size, terrain_half_size)
	return Vector3(x, 0.0, z)


func _is_clear_of_spawn(pos: Vector3) -> bool:
	var spawn := Vector3(0.0, 0.0, 0.0)
	return pos.distance_to(spawn) >= clear_radius


func _is_valid_spawn_height(height: float) -> bool:
	return height >= spawn_height_min and height <= spawn_height_max


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
		props.add_child(tree)
		tree.global_position = pos

	for pos in rock_positions:
		pos.y = _get_terrain_height_at(pos.x, pos.z)
		var rock := rock_scene.instantiate() as Node3D
		props.add_child(rock)
		rock.global_position = pos


func _populate_animals() -> void:
	var animals := get_parent().get_node_or_null("Animals") as Node3D
	if not animals:
		push_error("WorldPopulator: Animals node not found")
		return

	for i in animal_count:
		var pos := _get_random_position()
		var attempts := 0
		while not _is_clear_of_spawn(pos) and attempts < 20:
			pos = _get_random_position()
			attempts += 1

		var animal := animal_scene.instantiate() as Node3D
		pos.y = _get_terrain_height_at(pos.x, pos.z) + 0.3
		animal.global_position = pos
		animals.add_child(animal)
