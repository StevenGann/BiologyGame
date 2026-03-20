# BiologyGame Documentation

Technical documentation for **BiologyGame**—an FPS prototype with a large-scale animal and plant simulation. Built with **Godot Engine 4.6+** using C# and GDScript.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | Scene hierarchy, data flow, SimSyncBridge |
| [Simulation](simulation.md) | SimulationGrid, CellProcessor, LOD tiers, AnimalLogic |
| [Animals](animals.md) | Species config, AnimalNode, PlantNode |
| [World & Environment](world-and-environment.md) | Terrain, WorldPopulator, world bounds |
| [Player](player-and-combat.md) | FPS controller |
| [Visual Style](visual-style.md) | Environment, materials |

## Quick Reference

- **Project Root**: `src/` (contains `project.godot`)
- **Entry Scene**: `res://main.tscn`
- **Simulation**: C# in `scripts/csharp/Simulation/`
- **UI / World**: GDScript in `scripts/game/`, `scripts/player/`, `scripts/world/`, `scripts/ui/`
- **Requirements**: Godot 4.6+, .NET 8, Windows (D3D12, Jolt Physics)
