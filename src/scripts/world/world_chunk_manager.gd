extends Node3D
## Chunk-based streaming for props. Loads/unloads MultiMeshInstance3D nodes as the
## player moves, so only visible chunks consume GPU/CPU resources.
##
## Chunks are square cells of CHUNK_SIZE × CHUNK_SIZE meters. Each chunk independently
## holds a PropMultimeshRenderer and (optionally) an ImpostorRenderer for far-LOD trees.
##
## Flow:
##   1. WorldPopulator writes all prop placements into PropDataStore (raw data, no nodes).
##   2. WorldChunkManager._process() detects player movement and triggers load/unload.
##   3. Loading is staggered: one chunk per frame to avoid hitches.

const ChunkData = preload("res://scripts/world/chunk_data.gd")
const PropDataStore = preload("res://scripts/world/prop_data_store.gd")

## Width/height of each chunk in meters. 128 m → ~256 chunks for a 2000 m world.
@export var chunk_size: float = 128.0
## Chunks within this many meters of the player are loaded (should match view distance).
@export var load_radius: float = 650.0
## Chunks beyond this distance are unloaded (hysteresis prevents pop-in/out).
@export var unload_radius: float = 700.0
## Chunks per frame to load (stagger to avoid hitches). 1–3 is typical.
@export var load_per_frame: int = 2

## Enable impostor billboard rendering for far-LOD trees (Phase 3).
@export var use_impostors: bool = false

## The PropPhysicsSpawner node (shared across all chunks).
@export var physics_spawner: NodePath = NodePath("")

## Reference to PropDataStore populated by WorldPopulator.
var data_store: PropDataStore = null

## Currently loaded chunks: Vector2i -> ChunkData
var _loaded: Dictionary = {}
## Queue of chunk coords pending load (populated when player moves).
var _load_queue: Array[Vector2i] = []

var _player: Node3D = null
var _last_player_chunk: Vector2i = Vector2i(9999999, 9999999)
var _physics_spawner_node: Node = null


func _ready() -> void:
	if not physics_spawner.is_empty():
		_physics_spawner_node = get_node_or_null(physics_spawner)


func _process(_delta: float) -> void:
	if not data_store:
		return

	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if not _player:
			return

	var player_pos := _player.global_position
	var player_chunk := _pos_to_chunk(player_pos)

	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_enqueue_visible_chunks(player_chunk, player_pos)
		_unload_distant_chunks(player_pos)

	_process_load_queue()


## Called by WorldPopulator when data generation is complete.
func set_data_store(store: PropDataStore) -> void:
	data_store = store
	# Trigger initial load if player is already in the world.
	_last_player_chunk = Vector2i(9999999, 9999999)


func _enqueue_visible_chunks(player_chunk: Vector2i, player_pos: Vector3) -> void:
	var cell_radius := int(ceil(load_radius / chunk_size)) + 1
	var load_sq := load_radius * load_radius

	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var coord := Vector2i(player_chunk.x + dx, player_chunk.y + dz)
			if _loaded.has(coord) or not data_store.has_chunk(coord):
				continue
			# AABB check: chunk center within load radius?
			var cx := (float(coord.x) + 0.5) * chunk_size
			var cz := (float(coord.y) + 0.5) * chunk_size
			var dist_sq := player_pos.distance_squared_to(Vector3(cx, player_pos.y, cz))
			if dist_sq <= load_sq and not _load_queue.has(coord):
				_load_queue.append(coord)


func _unload_distant_chunks(player_pos: Vector3) -> void:
	var unload_sq := unload_radius * unload_radius
	var to_remove: Array[Vector2i] = []

	for coord in _loaded.keys():
		var cx := (float(coord.x) + 0.5) * chunk_size
		var cz := (float(coord.y) + 0.5) * chunk_size
		var dist_sq := player_pos.distance_squared_to(Vector3(cx, player_pos.y, cz))
		if dist_sq > unload_sq:
			to_remove.append(coord)

	for coord in to_remove:
		var cd: ChunkData = _loaded[coord]
		cd.free_chunk()
		_loaded.erase(coord)


func _process_load_queue() -> void:
	var loaded_this_frame := 0
	while not _load_queue.is_empty() and loaded_this_frame < load_per_frame:
		var coord: Vector2i = _load_queue.pop_front()
		if _loaded.has(coord):
			continue
		if not data_store.has_chunk(coord):
			continue
		_load_chunk(coord)
		loaded_this_frame += 1


func _load_chunk(coord: Vector2i) -> void:
	var cd := ChunkData.new()
	cd.build(coord, data_store, self, _physics_spawner_node, use_impostors)
	_loaded[coord] = cd


func _pos_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / chunk_size)), int(floor(pos.z / chunk_size)))
