extends RefCounted
## Holds the live Godot rendering nodes for a single loaded world chunk.
## Created by WorldChunkManager when a chunk enters view range; freed when it leaves.
##
## Each chunk has:
##   - One PropMultimeshRenderer node for near-LOD 3D tree/rock geometry
##   - One ImpostorRenderer node for far-LOD billboard trees (Phase 3)
##   PropPhysicsSpawner is shared across all chunks and managed externally.

const PropMultimeshRenderer = preload("res://scripts/world/prop_multimesh_renderer.gd")
const ImpostorRenderer = preload("res://scripts/world/impostor_renderer.gd")
const PropDataStore = preload("res://scripts/world/prop_data_store.gd")

## Tree base scale (matches world_populator.gd TREE_BASE_SCALE).
const TREE_BASE_SCALE: float = 3.5
## Rock base scale (matches world_populator.gd ROCK_BASE_SCALE).
const ROCK_BASE_SCALE: float = 2.5

var chunk_coord: Vector2i
var renderer: PropMultimeshRenderer = null
var impostor: ImpostorRenderer = null

var _parent: Node3D = null


## Build rendering nodes from PropDataStore for this chunk.
## physics_spawner receives tree/rock positions via register_*().
## use_impostors: also build an ImpostorRenderer for far-LOD trees.
func build(
	coord: Vector2i,
	store: PropDataStore,
	parent: Node3D,
	physics_spawner: Node,
	use_impostors: bool = false
) -> void:
	chunk_coord = coord
	_parent = parent

	var chunk_d := store.get_chunk(coord)
	if chunk_d.is_empty():
		return

	var positions: PackedVector3Array = chunk_d.positions
	var variants: PackedInt32Array = chunk_d.variants
	var scales: PackedFloat32Array = chunk_d.scales
	var total := positions.size()

	# Pre-count trees for impostor capacity.
	var tree_count := 0
	if use_impostors:
		for i in total:
			if not PropDataStore.is_rock(variants[i]):
				tree_count += 1

	# --- Near-LOD 3D renderer ---
	renderer = PropMultimeshRenderer.new()
	renderer.tree_capacity = total
	renderer.rock_capacity = total
	parent.add_child(renderer)

	# --- Far-LOD impostor renderer (optional) ---
	if use_impostors and tree_count > 0:
		impostor = ImpostorRenderer.new()
		impostor.init_capacity(tree_count)
		parent.add_child(impostor)

	# Fill renderers and register physics positions.
	for i in total:
		var pos := positions[i]
		var encoded := variants[i]
		var sc := scales[i]

		if PropDataStore.is_rock(encoded):
			var variant_idx := PropDataStore.decode_rock_variant(encoded)
			var xform := Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * ROCK_BASE_SCALE * sc),
				pos
			)
			renderer.add_rock_instance(variant_idx, xform)
			if physics_spawner and physics_spawner.has_method("register_rock"):
				physics_spawner.register_rock(pos)
		else:
			var variant_idx := PropDataStore.decode_tree_variant(encoded)
			var xform := Transform3D(
				Basis.from_euler(Vector3(0, _yaw_from_pos(pos), 0)).scaled(
					Vector3.ONE * TREE_BASE_SCALE * sc
				),
				pos
			)
			renderer.add_tree_instance(variant_idx, xform)
			if impostor:
				impostor.add_tree(pos, TREE_BASE_SCALE * sc, variant_idx)
			if physics_spawner and physics_spawner.has_method("register_tree"):
				physics_spawner.register_tree(pos)

	renderer.finalize()
	if impostor:
		impostor.finalize()


## Free all rendering nodes owned by this chunk.
func free_chunk() -> void:
	if renderer:
		renderer.queue_free()
		renderer = null
	if impostor:
		impostor.queue_free()
		impostor = null


## Deterministic yaw rotation from XZ position hash (visual variety without extra RNG).
static func _yaw_from_pos(pos: Vector3) -> float:
	return fmod(float(int(pos.x * 7.0 + pos.z * 13.0)), TAU)
