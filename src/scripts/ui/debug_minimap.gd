extends Control
## Debug mini-map showing all animals as dots on a 2D representation of the terrain.
## Only visible when SimulationManager.debug_mode is true.
## Color-codes dots by LOD tier: green=FULL, yellow=MEDIUM, red=FAR.

@export var map_size: float = 400.0  ## Size of the mini-map square in pixels
@export var map_margin: float = 20.0  ## Margin from top-right corner
@export var dot_size: float = 3.0  ## Size of animal dots
@export var player_dot_size: float = 5.0  ## Size of player dot
@export var border_width: float = 2.0  ## Width of the outline border
@export var redraw_interval: int = 3  ## Redraw every N frames (3 = ~20 FPS). Higher = better performance.

@export_group("Colors")
@export var border_color: Color = Color.WHITE
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var full_lod_color: Color = Color.GREEN
@export var medium_lod_color: Color = Color.YELLOW
@export var far_lod_color: Color = Color.RED
@export var player_color: Color = Color.CYAN

var _sim_manager: Node = null
var _animals_node: Node = null
var _player: Node3D = null
var _terrain: Node = null
var _terrain_size: float = 1000.0  ## Will be read from terrain if available
var _far_sim_bridge: Node = null  ## Reference to FarSimBridge for FAR animal snapshot


func _ready() -> void:
	# Position in top-right corner
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -map_size - map_margin
	offset_top = map_margin
	offset_right = -map_margin
	offset_bottom = map_size + map_margin

	# Start hidden until debug mode is enabled
	visible = false

	# Cache references
	call_deferred("_cache_references")


func _cache_references() -> void:
	_sim_manager = get_tree().get_first_node_in_group("simulation_manager")
	_player = get_tree().get_first_node_in_group("player") as Node3D

	# Find animals and terrain nodes
	var world := get_tree().get_first_node_in_group("simulation_manager")
	if world:
		var parent := world.get_parent()
		if parent:
			_animals_node = parent.get_node_or_null("Animals")
			_terrain = parent.get_node_or_null("TestTerrain")
			_far_sim_bridge = parent.get_node_or_null("FarSimBridge")

	# Get terrain size if available
	if _terrain and "terrain_size" in _terrain:
		_terrain_size = _terrain.terrain_size


func _process(_delta: float) -> void:
	# Check debug mode state
	if _sim_manager and "debug_mode" in _sim_manager:
		var should_show: bool = _sim_manager.debug_mode
		if visible != should_show:
			visible = should_show

	# Throttle redraws: minimap doesn't need 60 FPS
	if visible and Engine.get_process_frames() % maxi(1, redraw_interval) == 0:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var rect := Rect2(Vector2.ZERO, Vector2(map_size, map_size))

	# Draw semi-transparent background
	draw_rect(rect, background_color, true)

	# Draw border outline (not filled)
	draw_rect(rect, border_color, false, border_width)

	# Draw scene animals (FULL/MEDIUM LOD)
	_draw_animals()

	# Draw FAR animals from FarAnimalSim snapshot
	_draw_far_animals()

	# Draw player
	_draw_player()


func _draw_animals() -> void:
	if not _animals_node or not _sim_manager:
		return

	# Cache player position and radii once per redraw (avoids N get_lod_tier calls)
	var player_pos: Vector3 = _player.global_position if _player and is_instance_valid(_player) else Vector3.ZERO
	var full_sq: float = 0.0
	var med_sq: float = 0.0
	if "full_sim_radius" in _sim_manager and "medium_sim_radius" in _sim_manager:
		var r1: float = _sim_manager.full_sim_radius
		var r2: float = _sim_manager.medium_sim_radius
		full_sq = r1 * r1
		med_sq = r2 * r2

	for animal in _animals_node.get_children():
		if not is_instance_valid(animal) or not animal is Node3D:
			continue

		var world_pos: Vector3 = animal.global_position
		var map_pos: Vector2 = _world_to_map(world_pos)

		# Compute LOD locally (avoids per-animal GDScript get_lod_tier call)
		var color: Color = full_lod_color
		if full_sq > 0.0 and med_sq > 0.0:
			var dist_sq: float = world_pos.distance_squared_to(player_pos)
			if dist_sq < full_sq:
				color = full_lod_color
			elif dist_sq < med_sq:
				color = medium_lod_color
			else:
				color = far_lod_color

		draw_circle(map_pos, dot_size, color)


func _draw_far_animals() -> void:
	if not _far_sim_bridge:
		return

	# Get snapshot: packed float array [x0, z0, species0, x1, z1, species1, ...]
	var data: PackedFloat32Array = _far_sim_bridge.GetFarAnimalSnapshot()
	if data.is_empty():
		return

	# Iterate in strides of 3
	var count: int = data.size() / 3
	for i in range(count):
		var offset: int = i * 3
		var x: float = data[offset]
		var z: float = data[offset + 1]
		# species = data[offset + 2] - could use for different colors if needed

		var world_pos := Vector3(x, 0.0, z)
		var map_pos: Vector2 = _world_to_map(world_pos)

		# Draw FAR animals as red dots
		draw_circle(map_pos, dot_size, far_lod_color)


func _draw_player() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if not _player:
			return

	var world_pos: Vector3 = _player.global_position
	var map_pos: Vector2 = _world_to_map(world_pos)

	# Draw player as a slightly larger dot
	draw_circle(map_pos, player_dot_size, player_color)


## Convert world position (X, Z) to mini-map position (0 to map_size).
## Terrain goes from -terrain_size/2 to +terrain_size/2.
func _world_to_map(world_pos: Vector3) -> Vector2:
	var half_terrain: float = _terrain_size * 0.5

	# Normalize to 0..1 range
	var norm_x: float = (world_pos.x + half_terrain) / _terrain_size
	var norm_z: float = (world_pos.z + half_terrain) / _terrain_size

	# Clamp to map bounds
	norm_x = clampf(norm_x, 0.0, 1.0)
	norm_z = clampf(norm_z, 0.0, 1.0)

	# Convert to map pixel coordinates
	return Vector2(norm_x * map_size, norm_z * map_size)
