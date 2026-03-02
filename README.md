# BiologyGame

An FPS with RPG elements set in an open world where the player hunts animals. Built with **Godot Engine 4.6+** using C# and GDScript. Features PS1-style graphics, a full LOD simulation system, and diverse animal AI (foragers and hunters).

## Features

- **PS1-style graphics**: Vertex jitter shader, posterize color filter, heavy fog, low-poly aesthetic
- **FPS controls**: WASD movement, mouse look, jump
- **Open world**: Heightmap terrain (1000 m), props (trees, rocks), and populated wildlife
- **Animal hunting**: Tranquilizer darts to capture animals; foragers (Deer, Rabbit, Bison) and hunters (Wolf, Bear) with distinct AI behaviors
- **LOD simulation**: Spatial grid, three LOD tiers (FULL / MEDIUM / FAR), and async FarAnimalSim for distant animals
- **Day/night & weather**: Cyclical day phases, dynamic sun/sky, snow, wind, and fog
- **Plants**: Consumable plants for foragers to eat

## Requirements

- Godot Engine 4.6+
- .NET 8
- Windows (D3D12, Jolt Physics)

## Running the Game

1. Open the project in Godot (use `src/` as the project root, or open the folder containing `project.godot`).
2. Press F5 or click **Project > Run** to play.

## Controls

| Action | Input |
|--------|-------|
| Move | W A S D |
| Jump | Space |
| Shoot (tranq dart) | Left mouse button |
| Toggle mouse capture | Escape |
| Toggle debug overlay | Backtick (`) |

Arrow keys step time and adjust wind/snowfall when debugging (see [World & Environment](docs/world-and-environment.md)).

## Project Structure

```
src/
├── main.tscn              # Entry scene
├── scripts/
│   ├── game/              # main.gd, simulation_manager.gd, day_night_weather_manager.gd
│   ├── player/            # FPS controller
│   ├── animals/           # species_constants.gd
│   ├── plants/            # plant.gd
│   ├── world/             # heightmap_terrain.gd, world_populator.gd
│   ├── props/             # random_tree.gd, random_rock.gd, ps1_material_builder.gd
│   ├── weapons/           # tranq_dart.gd
│   └── csharp/            # AnimalBase, ForagerAnimal, HunterAnimal, FarSimBridge, etc.
├── scenes/
│   ├── player/            # FPS controller
│   ├── world/             # Terrain, TestTerrain
│   ├── animals/           # animal_base, forager_animal, hunter_animal
│   ├── plants/            # plant
│   ├── props/             # random_tree, random_rock
│   └── weapons/           # tranq_dart
├── shaders/               # ps1_style.gdshader, posterize.gdshader, terrain_heightmap.gdshader
├── materials/             # Terrain, PS1 ground
├── environments/          # Fog, sky, lighting
└── ui/                    # Crosshair, health bar
```

## Documentation

Technical docs are in [`docs/`](docs/):

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Scene hierarchy, data flow, GDScript/C# integration |
| [Simulation](docs/simulation.md) | LOD tiers, spatial grid, FarSimBridge, AnimalLogic |
| [Animals](docs/animals.md) | Species, ForagerAnimal/HunterAnimal AI, states |
| [World & Environment](docs/world-and-environment.md) | Terrain, WorldPopulator, day/night, weather, plants |
| [Player & Combat](docs/player-and-combat.md) | FPS controls, raycast shooting, tranq darts |
| [Visual Style](docs/visual-style.md) | PS1 shaders, posterize, environment |

## Extending the Prototype

### Adding Animals

- Use `ForagerAnimal` for plant-eating, hunter-fleeing species; use `HunterAnimal` for predators.
- Instance `scenes/animals/forager_animal.tscn` or `hunter_animal.tscn` in the world.
- Configure species in `species_constants.gd` and `AnimalBase.Species` (C#).
- Connect to `animal_defeated` for XP/loot logic.

### Adjusting PS1 Aesthetic

- **Shader** (`shaders/ps1_style.gdshader`): Tweak `jitter`, `resolution`, `affine_mapping`.
- **Posterize** (`shaders/posterize.gdshader`): Color levels and film grain.
- **Environment** (`environments/ps1_environment.tres`): Fog density and draw distance.
- **Materials**: Override `albedo_color` for surface colors.

See [Visual Style](docs/visual-style.md) for details.

## Input Mapping

If inputs do not work, add them in **Project > Project Settings > Input Map**:

- `move_forward` → W
- `move_back` → S
- `move_left` → A
- `move_right` → D
- `jump` → Space
- `shoot` → Left mouse button

## License

See project license file.
