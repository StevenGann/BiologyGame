extends RefCounted
## Raw prop placement data, stored per chunk. No Godot scene nodes are held here.
## WorldPopulator writes to this; WorldChunkManager reads from it to build MultiMesh nodes.
##
## Data layout per chunk (Vector2i key):
##   positions: PackedVector3Array  — world positions for every prop in chunk
##   variants:  PackedInt32Array    — variant index per prop (< 0 = tree, >= 0 = rock,
##                                    encoded as: tree = variant, rock = variant + ROCK_OFFSET)
##   scales:    PackedFloat32Array  — uniform scale multiplier per prop
##
## Using packed arrays keeps memory tight and avoids GC pressure from Dictionary arrays.

const ROCK_VARIANT_OFFSET: int = 1000  ## Sentinel separating tree vs rock variants in variants array

## chunk_coord (Vector2i) -> ChunkPropData
var _chunks: Dictionary = {}


## Add a tree to a chunk.
func add_tree(chunk: Vector2i, pos: Vector3, variant_idx: int, scale_mult: float) -> void:
	_ensure_chunk(chunk)
	var d: Dictionary = _chunks[chunk]
	(d.positions as PackedVector3Array).append(pos)
	(d.variants as PackedInt32Array).append(variant_idx)
	(d.scales as PackedFloat32Array).append(scale_mult)


## Add a rock to a chunk.
func add_rock(chunk: Vector2i, pos: Vector3, variant_idx: int, scale_mult: float) -> void:
	_ensure_chunk(chunk)
	var d: Dictionary = _chunks[chunk]
	(d.positions as PackedVector3Array).append(pos)
	(d.variants as PackedInt32Array).append(variant_idx + ROCK_VARIANT_OFFSET)
	(d.scales as PackedFloat32Array).append(scale_mult)


## Returns the chunk dictionary for the given coord, or null.
func get_chunk(chunk: Vector2i) -> Dictionary:
	return _chunks.get(chunk, {})


## True if any data has been registered for this chunk.
func has_chunk(chunk: Vector2i) -> bool:
	return _chunks.has(chunk)


## Returns all chunk coords that have been populated.
func all_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for k in _chunks.keys():
		result.append(k)
	return result


## Returns true if this variants entry represents a rock (vs tree).
static func is_rock(encoded_variant: int) -> bool:
	return encoded_variant >= ROCK_VARIANT_OFFSET


## Decode a raw variant value from the store back to tree variant index.
static func decode_tree_variant(encoded: int) -> int:
	return encoded


## Decode a raw variant value from the store back to rock variant index.
static func decode_rock_variant(encoded: int) -> int:
	return encoded - ROCK_VARIANT_OFFSET


func _ensure_chunk(chunk: Vector2i) -> void:
	if not _chunks.has(chunk):
		_chunks[chunk] = {
			"positions": PackedVector3Array(),
			"variants": PackedInt32Array(),
			"scales": PackedFloat32Array(),
		}
