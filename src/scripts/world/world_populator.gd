extends Node3D
## Spawns trees, rocks, and animals across the terrain at runtime.
## Uses a seed for reproducible placement.

@export var tree_count: int = 1000
@export var rock_count: int = 250
@export var animal_count: int = 20
@export var terrain_half_size: float = 50.0
@export var spawn_seed: int = 12345
@export var clear_radius: float = 8.0

@export var tree_scene: PackedScene = preload("res://scenes/props/random_tree.tscn")
@export var rock_scene: PackedScene = preload("res://scenes/props/random_rock.tscn")
@export var animal_scene: PackedScene = preload("res://scenes/animals/animal_base.tscn")

var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = spawn_seed

	if tree_scene and rock_scene:
		_populate_props()
	if animal_scene:
		_populate_animals()


func _get_random_position() -> Vector3:
	var x := _rng.randf_range(-terrain_half_size, terrain_half_size)
	var z := _rng.randf_range(-terrain_half_size, terrain_half_size)
	return Vector3(x, 0.0, z)


func _is_clear_of_spawn(pos: Vector3) -> bool:
	var spawn := Vector3(0.0, 0.0, 0.0)
	return pos.distance_to(spawn) >= clear_radius


func _populate_props() -> void:
	var props := get_parent().get_node_or_null("TestTerrain/Props") as Node3D
	if not props:
		push_error("WorldPopulator: Props node not found")
		return

	var positions: Array[Vector3] = []
	var needed := tree_count + rock_count
	var max_attempts := needed * 10
	for i in max_attempts:
		if positions.size() >= needed:
			break
		var pos := _get_random_position()
		if _is_clear_of_spawn(pos):
			positions.append(pos)

	while positions.size() < needed:
		positions.append(_get_random_position())

	var tree_positions: Array[Vector3] = []
	var rock_positions: Array[Vector3] = []
	for i in tree_count:
		tree_positions.append(positions[i])
	for i in rock_count:
		rock_positions.append(positions[tree_count + i])

	for pos in tree_positions:
		var tree := tree_scene.instantiate() as Node3D
		tree.global_position = pos
		props.add_child(tree)

	for pos in rock_positions:
		var rock := rock_scene.instantiate() as Node3D
		rock.global_position = pos
		props.add_child(rock)


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
		pos.y = 0.3
		animal.global_position = pos
		animals.add_child(animal)
