extends Node
## Distance-based physics spawner for props using a spatial grid.
## Replaces prop_physics_manager.gd.
##
## Instead of iterating all 200K+ scene nodes, this stores raw world positions in a
## grid keyed by chunk cell. When the player moves, only nearby cells are checked.
## Physics bodies use lightweight CapsuleShape3D / SphereShape3D rather than trimesh.
##
## Register all props via register_tree() and register_rock() during world population.
## PropPhysicsSpawner then manages StaticBody3D lifecycle near the player automatically.

const GRID_CELL_SIZE: float = 32.0  ## Spatial grid resolution (meters per cell)

@export var activate_radius: float = 60.0   ## Spawn physics within this distance
@export var deactivate_radius: float = 80.0  ## Remove physics beyond this (hysteresis)
@export var spawn_budget_per_frame: int = 40 ## Max physics body spawns per frame

## Tree capsule physics shape parameters.
@export var tree_capsule_radius: float = 0.35
@export var tree_capsule_height: float = 4.0
## Rock sphere physics shape parameters.
@export var rock_sphere_radius: float = 1.2

## _prop_grid maps Vector2i cell -> Array of PropEntry dictionaries.
## Each PropEntry: {"pos": Vector3, "type": int (0=tree,1=rock), "body": StaticBody3D or null}
var _prop_grid: Dictionary = {}

## Tracks cells that currently have active physics bodies (for fast unload iteration).
var _active_cells: Dictionary = {}  ## Vector2i -> true

var _player: Node3D = null
var _last_player_cell: Vector2i = Vector2i(9999999, 9999999)

const TYPE_TREE: int = 0
const TYPE_ROCK: int = 1


func _ready() -> void:
	var config := get_node_or_null("/root/CullingConfig")
	if config:
		activate_radius = config.get("prop_physics_activate_radius")
		deactivate_radius = config.get("prop_physics_deactivate_radius")


## Register a tree position for deferred physics activation.
func register_tree(pos: Vector3) -> void:
	_register_prop(pos, TYPE_TREE)


## Register a rock position for deferred physics activation.
func register_rock(pos: Vector3) -> void:
	_register_prop(pos, TYPE_ROCK)


func _register_prop(pos: Vector3, type: int) -> void:
	var cell := _cell_key(pos)
	if not _prop_grid.has(cell):
		_prop_grid[cell] = []
	_prop_grid[cell].append({"pos": pos, "type": type, "body": null})


func _physics_process(_delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if not _player:
			return

	var player_pos := _player.global_position
	var player_cell := _cell_key(player_pos)

	# Only process when player has moved to a different cell.
	if player_cell == _last_player_cell:
		return
	_last_player_cell = player_cell

	_update_physics(player_pos)


func _update_physics(player_pos: Vector3) -> void:
	var activate_sq := activate_radius * activate_radius
	var deactivate_sq := deactivate_radius * deactivate_radius
	var cell_radius := int(ceil(deactivate_radius / GRID_CELL_SIZE)) + 1
	var px := int(floor(player_pos.x / GRID_CELL_SIZE))
	var pz := int(floor(player_pos.z / GRID_CELL_SIZE))

	var spawned := 0

	# Activate props in nearby cells
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(px + dx, pz + dz)
			if not _prop_grid.has(cell):
				continue
			var entries: Array = _prop_grid[cell]
			for entry in entries:
				if entry.body != null:
					continue  # Already active
				var dist_sq := player_pos.distance_squared_to(entry.pos)
				if dist_sq <= activate_sq:
					if spawned < spawn_budget_per_frame:
						entry.body = _spawn_body(entry.pos, entry.type)
						spawned += 1
						_active_cells[cell] = true

	# Deactivate props in previously-active cells that are now out of range
	for cell in _active_cells.keys():
		if not _prop_grid.has(cell):
			continue
		var entries: Array = _prop_grid[cell]
		var any_active := false
		for entry in entries:
			if entry.body == null:
				continue
			var dist_sq := player_pos.distance_squared_to(entry.pos)
			if dist_sq > deactivate_sq:
				_despawn_body(entry)
			else:
				any_active = true
		if not any_active:
			_active_cells.erase(cell)


func _spawn_body(pos: Vector3, type: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.global_position = pos
	body.collision_layer = 2
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	if type == TYPE_TREE:
		var shape := CapsuleShape3D.new()
		shape.radius = tree_capsule_radius
		shape.height = tree_capsule_height
		col.shape = shape
		col.position = Vector3(0, tree_capsule_height * 0.5, 0)
	else:
		var shape := SphereShape3D.new()
		shape.radius = rock_sphere_radius
		col.shape = shape
		col.position = Vector3(0, rock_sphere_radius, 0)

	body.add_child(col)
	add_child(body)
	return body


func _despawn_body(entry: Dictionary) -> void:
	var body := entry.body as StaticBody3D
	if body and is_instance_valid(body):
		body.queue_free()
	entry.body = null


func _cell_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / GRID_CELL_SIZE)), int(floor(pos.z / GRID_CELL_SIZE)))
