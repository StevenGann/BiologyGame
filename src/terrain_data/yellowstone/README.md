# Yellowstone Terrain3D data

Save the **Terrain3D importer** output here so the `WorldTerrain` scene can load it.

**Debugging**: Run the game with the **Godot console** open (e.g. `Godot_v4*_console.exe` or run from terminal). The `TerrainBootstrap` script logs whether region files were found. If it reports `Region files: 0`, the `data_directory` on the Terrain3D node does not point at a folder containing `terrain3d*.res` files.

## Expected contents

After import, this folder should contain:

- One or more region files named like `terrain3d_XX_XX.res` (or `terrain3d-XX_XX.res` depending on version)
- Optionally other Terrain3D data files written by the importer

Set the importer’s **Data Directory** to:

`res://terrain_data/yellowstone`

If you saved elsewhere, either copy those files into this folder or change `data_directory` on the `Terrain3D` node in `res://scenes/world/world_terrain.tscn`.

## Source maps (reference)

- Height: `res://assets/heightmaps/yellowstone_height.png` (8192×8192 px — use as **lateral scale hint** if 1 px = 1 m)
- Color: `res://assets/heightmaps/yellowstone_color.png`

Adjust `WorldConstants` in `res://scripts/game/world_constants.gd` if your import scale, offset, or `vertex_spacing` differs.

## Textures / `Terrain3DAssets`

`world_terrain.tscn` currently uses `res://demo/data/assets.tres` (demo grass + cliff) for the auto-shader. That is only for **material** setup; your **heights and colormap** still come from the region files in this folder.

If you created a dedicated `Terrain3DAssets` when importing, open `res://scenes/world/world_terrain.tscn` and set the `Terrain3D` node’s **assets** to that resource instead.

## Physics

The scene uses the same **collision_mask = 3** as the official Terrain3D demo so characters on layer **2** collide with the terrain. If your FPS controller uses **layer 1** only, set the `Terrain3D` node’s collision settings to include layer 1 (see [Terrain3D collision docs](https://terrain3d.readthedocs.io/en/stable/docs/collision.html)) or put the player on layer 2.
