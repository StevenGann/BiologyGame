# Architecture Overview

This document describes the high-level architecture of BiologyGame, including the scene hierarchy, data flow, and cross-language integration.

## Scene Hierarchy

```mermaid
graph TB
    Main[Main Node]
    Main --> GameViewport[GameViewport SubViewport]
    Main --> PosterizeLayer[PosterizeLayer CanvasLayer]
    Main --> GameUI[GameUI]
    
    GameViewport --> WorldEnv[WorldEnvironment]
    GameViewport --> DirLight[DirectionalLight3D]
    GameViewport --> World[World Node3D]
    GameViewport --> Player[Player CharacterBody3D]
    GameViewport --> DayNight[DayNightWeatherManager]
    
    World --> TranqDarts[TranqDarts]
    World --> TestTerrain[TestTerrain HeightmapTerrain]
    World --> Animals[Animals Node3D]
    World --> Plants[Plants Node3D]
    World --> SimMgr[SimulationManager]
    World --> FarBridge[FarSimBridge]
    World --> WorldPopulator[WorldPopulator]
    
    TestTerrain --> Props[Props trees, rocks]
    
    style Main fill:#e1f5ff
    style GameViewport fill:#fff4e1
    style World fill:#e8f5e9
```

## System Architecture Diagram

```mermaid
flowchart LR
    subgraph MainThread[Main Thread]
        Main[Main.gd]
        SimMgr[SimulationManager]
        FarBridge[FarSimBridge]
        Player[Player]
        Animals[Animals in Scene]
    end
    
    subgraph WorkerThread[Worker Thread]
        FarSim[FarAnimalSim]
    end
    
    Main --> SimMgr
    Main --> FarBridge
    SimMgr --> Animals
    FarBridge <--> FarSim
    FarBridge --> Animals
```

## Data Flow Overview

```mermaid
flowchart TD
    Input[Player Input]
    Input --> Main
    Main --> GameViewport
    GameViewport --> Player
    GameViewport --> World
    
    Player --> Shoot[Shoot Raycast]
    Shoot --> Hit[Hit Animal/Terrain]
    Hit --> TakeDamage[take_damage]
    Hit --> TranqDart[Tranq Dart Visual]
    
    World --> SimMgr
    SimMgr --> LOD[LOD Tier per Animal]
    LOD --> Full[FULL AI]
    LOD --> Medium[MEDIUM AI]
    LOD --> Far[FAR Tick or Demote]
    
    Far --> FarBridge
    FarBridge --> Demote[Demote to FarAnimalSim]
    FarBridge --> Promote[Promote back to Scene]
    Demote --> FarSim
    FarSim --> Promote
```

## Cross-Language Integration

BiologyGame uses **GDScript** for game logic, world setup, and simulation orchestration, and **C#** for animal AI and high-performance FAR simulation.

```mermaid
sequenceDiagram
    participant SimMgr as SimulationManager (GDScript)
    participant Animal as AnimalBase (C#)
    participant Bridge as FarSimBridge (C#)
    participant FarSim as FarAnimalSim (C#)
    
    SimMgr->>Animal: get_lod_tier(pos)
    SimMgr->>Animal: should_ai_tick_this_frame(lod, id)
    Animal->>SimMgr: Call("get_same_species_in_radius", pos, radius, species)
    Animal->>SimMgr: Call("get_hunters_in_radius", ...)
    Animal->>SimMgr: Call("get_plants_in_radius", ...)
    
    Bridge->>Animal: ExportStateData()
    Bridge->>FarSim: Demote(state)
    FarSim-->>Bridge: TryGetPromote()
    Bridge->>Animal: ApplyStateData(state)
```

### Key Integration Points

| From | To | Mechanism |
|------|-----|-----------|
| C# Animal | SimulationManager | `GetTree().GetFirstNodeInGroup("simulation_manager")` + `Call("method_name", ...)` |
| FarSimBridge | Terrain | `_terrainNode.Call("get_height_at", x, z)` via HeightmapSampler (main thread only) |
| FarSimBridge | Animals | `scene.Instantiate()`, `AddChild()`, `ApplyStateData()` |
| AnimalLogic | AnimalBase | Shared `AnimalStateData` struct, no Godot APIs |

## Process Order

SimulationManager and FarSimBridge use `set_process_priority()` to control execution order:

| Priority | Component | Purpose |
|----------|-----------|---------|
| -100 | SimulationManager | Runs first: rebuilds grid, processes FAR animals in scene |
| -50 | FarSimBridge | Runs after: demotes/promotes animals to/from async sim |
| 0 (default) | Animals | Full/Medium LOD `_physics_process` |

## File Layout

```
src/
├── main.tscn, project.godot
├── scripts/
│   ├── game/           # main.gd, simulation_manager.gd, day_night_weather_manager.gd
│   ├── player/         # player.gd
│   ├── animals/        # species_constants.gd
│   ├── plants/         # plant.gd
│   ├── world/          # world_populator.gd, heightmap_terrain.gd
│   ├── props/          # ps1_material_builder.gd, random_tree.gd, random_rock.gd
│   ├── weapons/        # tranq_dart.gd
│   └── csharp/         # Animals/*.cs, Simulation/*.cs
├── scenes/
│   ├── world/          # world.tscn, test_terrain.tscn
│   ├── player/         # player.tscn
│   ├── animals/        # animal_base.tscn, forager_animal.tscn, hunter_animal.tscn
│   ├── plants/         # plant.tscn
│   ├── props/          # random_tree.tscn, random_rock.tscn
│   └── weapons/        # tranq_dart.tscn
├── shaders/            # ps1_style.gdshader, posterize.gdshader, terrain_heightmap.gdshader
├── materials/          # terrain, ps1 ground
├── environments/       # ps1_environment.tres
└── ui/                 # game_ui.tscn, crosshair, health bar
```
