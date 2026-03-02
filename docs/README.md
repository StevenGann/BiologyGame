# BiologyGame Documentation

This folder contains technical documentation for the **BiologyGame** project—an FPS with RPG elements set in an open world where the player hunts animals. Built with **Godot Engine 4.6+** using C# and GDScript.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | High-level architecture, scene hierarchy, and data flow |
| [Simulation](simulation.md) | LOD system, spatial grid, FAR simulation, and FarSimBridge |
| [Animals](animals.md) | Animal species, AI behaviors, and OOP class hierarchy |
| [World & Environment](world-and-environment.md) | Terrain, props, day/night cycle, and weather |
| [Player & Combat](player-and-combat.md) | FPS controls, shooting, and tranquilizer darts |
| [Visual Style](visual-style.md) | PS1-style graphics, shaders, and posterize effects |

## Quick Reference

- **Project Root**: `src/` (contains `project.godot`)
- **Entry Scene**: `res://main.tscn`
- **Main Scripts**: GDScript in `scripts/game/`, `scripts/player/`, `scripts/world/`, etc.
- **Animal AI**: C# in `scripts/csharp/Animals/` and `scripts/csharp/Simulation/`
- **Requirements**: Godot 4.6+, .NET 8, Windows (D3D12, Jolt Physics)
