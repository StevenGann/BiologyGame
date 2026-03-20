# BiologyGame

An FPS prototype set in an open world with a large-scale animal and plant simulation. Built with **Godot Engine 4.6+** using C# and GDScript. Features Terrain3D heightmap terrain, a grid-based LOD simulation system, and herbivore/predator AI.

## Features

- **FPS controls**: WASD movement, mouse look, jump, sprint (Shift)
- **Open world**: 8192×8192 m Terrain3D terrain (Yellowstone heightmap), props
- **Large-scale simulation**: Millions of animals and plants via C# simulation
- **LOD system**: 4-tier spatial grid; tier 0 entities get Godot nodes; distant entities simulated in arrays only
- **Animal AI**: Herbivores and predators with wander, panic, contagion, and cohesion behaviors
- **Plants**: Consumable plants for herbivores; regrowth and respawn
- **Debug overlay**: Minimap with LOD grid, entity dots, player position (F1 or `)

## Requirements

- Godot Engine 4.6+
- .NET 8
- Windows (D3D12, Jolt Physics)

## Running the Game

1. Open the project in Godot (use `src/` as the project root).
2. Press F5 or click **Project > Run** to play.

## Controls

| Action | Input |
|--------|-------|
| Move | W A S D |
| Sprint | Shift |
| Jump | Space |
| Toggle mouse capture | Escape |
| Toggle debug overlay | F1 or Backtick (`) |

## Project Structure

```
src/
├── main.tscn              # Entry scene
├── scripts/
│   ├── game/              # world_constants.gd
│   ├── player/            # fps_controller.gd
│   ├── world/             # terrain_bootstrap.gd
│   ├── ui/                # debug_overlay.gd, debug_overlay_draw.gd
│   └── csharp/            # Simulation/, Animals/, Plants/
├── scenes/
│   ├── world/             # world_terrain.tscn
│   ├── player/            # fps_player.tscn
│   ├── animals/           # animal_base.tscn
│   ├── plants/            # plant_base.tscn
│   └── ui/                # debug_overlay.tscn
├── terrain_data/          # Yellowstone heightmap
└── addons/terrain_3d/     # Terrain3D addon
```

## Documentation

Technical docs are in [`docs/`](docs/):

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Scene hierarchy, data flow, SimSyncBridge |
| [Simulation](docs/simulation.md) | SimulationGrid, CellProcessor, LOD tiers, AnimalLogic |
| [Animals](docs/animals.md) | Species config, AnimalNode, PlantNode |
| [World & Environment](docs/world-and-environment.md) | Terrain, WorldPopulator, world bounds |
| [Player](docs/player-and-combat.md) | FPS controller |
| [Visual Style](docs/visual-style.md) | Environment, materials |

## Input Mapping

If inputs do not work, add them in **Project > Project Settings > Input Map**:

- `move_forward` → W
- `move_back` → S
- `move_left` → A
- `move_right` → D
- `jump` → Space
- `debug_overlay` → Backtick (`), F1

## Configuration

- **World size**: `world_constants.gd` (WORLD_SIZE_XZ_METERS) and `SimConfig.cs` (WorldSizeXZ)
- **Animal/plant counts**: `SimSyncBridge` exports (AnimalCount, PlantCount; default 2M / 4M)
- **LOD thresholds**: `SimConfig.cs` (LOD_A_Cells through LOD_D_Cells)

## License

See project license file.
