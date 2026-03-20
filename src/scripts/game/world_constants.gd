extends Node
## Single source of truth for world extent **as used by simulation and UI**.
## Keep in sync with Terrain3D: import position, `vertex_spacing`, and height scale.
##
## Default assumes Yellowstone heightmap 8192×8192 at 1 m per pixel lateral span
## and terrain centered on the world origin (symmetric -half..+half on X and Z).

## Source heightmap pixel size (informational; used for docs / tuning).
const SOURCE_HEIGHTMAP_SIZE_PX: Vector2i = Vector2i(8192, 8192)

## Lateral extent in meters along X and Z when 1 px = 1 m and the full map is imported.
const WORLD_SIZE_XZ_METERS: float = float(SOURCE_HEIGHTMAP_SIZE_PX.x)

## Half-extent from world origin (0,0) for a centered square world.
const HALF_EXTENT_XZ: float = WORLD_SIZE_XZ_METERS * 0.5

## Terrain3D data folder used by `world_terrain.tscn` (must match scene `data_directory`).
const TERRAIN_DATA_DIRECTORY: String = "res://terrain_data/yellowstone"

## Vertical range **hint** for HeightmapSampler / tools if heights are normalized or rescaled.
## Replace with values from your importer console (min/max height) after import.
const HEIGHT_MIN_HINT: float = 0.0
const HEIGHT_MAX_HINT: float = 500.0
