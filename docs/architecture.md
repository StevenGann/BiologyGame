# Architecture Overview

High-level architecture of BiologyGame: scene hierarchy, data flow, and simulation structure.

## Scene Hierarchy

```mermaid
flowchart TB
    Main[Main Node3D]

    Main --> WorldEnv[WorldEnvironment]
    Main --> WorldTerrain[WorldTerrain]
    Main --> Animals[Animals]
    Main --> Plants[Plants]
    Main --> FPSPlayer[FPSPlayer]
    Main --> SimBridge[SimSyncBridge]
    Main --> DebugOverlay[DebugOverlay]
    Main --> DirLight[DirectionalLight3D]
```

**Key relationships:** SimSyncBridge promotes entities to Animals/Plants, reads player position from FPSPlayer, and samples terrain from WorldTerrain.

## Data Flow

```mermaid
flowchart TD
    subgraph Init[Initialization]
        Populate[WorldPopulator.Populate]
        Grid[SimulationGrid.SetData]
        Rebuild[SimulationGrid.Rebuild]
    end

    subgraph PerFrame[Per Physics Frame]
        PlayerPos[Player Position]
        PlayerPos --> CellProc[CellProcessor.Tick]
        CellProc --> AnimalLogic[AnimalLogic.UpdateStateFar]
        CellProc --> PlantLogic[PlantLogic.Tick]
        CellProc --> Transfers[ProcessTransfers]
        CellProc --> Promote[Promote tier-0 to nodes]
        CellProc --> Sync[Sync AnimalNode/PlantNode]
    end

    Populate --> Grid
    Grid --> Rebuild
    Rebuild --> CellProc
```

## Simulation Architecture

```mermaid
flowchart TB
    subgraph CSharp[Pure C# Simulation]
        SimGrid[SimulationGrid]
        CellProc[CellProcessor]
        AnimalLogic[AnimalLogic]
        PlantLogic[PlantLogic]
        SimGrid --> CellProc
        CellProc --> AnimalLogic
        CellProc --> PlantLogic
    end

    subgraph Bridge[SimSyncBridge Main Thread]
        HeightSampler[HeightmapSampler]
        Promote[Promote/Demote]
        Sync[Sync Nodes]
    end

    subgraph Godot[Godot Scene]
        AnimalNodes[AnimalNode instances]
        PlantNodes[PlantNode instances]
    end

    CellProc --> Promote
    Promote --> AnimalNodes
    Promote --> PlantNodes
    Sync --> AnimalNodes
    Sync --> PlantNodes
    HeightSampler --> Promote
```

## LOD Promotion Flow

```mermaid
stateDiagram-v2
    [*] --> InGrid: Spawn
    InGrid --> HasNode: Distance <= LOD_A
    HasNode --> InGrid: Distance > LOD_A + Hysteresis
    HasNode --> Sync: Every frame

    note right of HasNode: AnimalNode/PlantNode in scene
    note right of InGrid: State in SimulationGrid arrays only
```

## File Layout

```
src/
├── main.tscn
├── project.godot
├── scripts/
│   ├── game/           # world_constants.gd
│   ├── player/         # fps_controller.gd
│   ├── world/          # terrain_bootstrap.gd
│   ├── ui/             # debug_overlay.gd, debug_overlay_draw.gd
│   └── csharp/
│       ├── Simulation/ # SimSyncBridge, SimulationGrid, CellProcessor,
│       │               # AnimalLogic, PlantLogic, WorldPopulator,
│       │               # SimConfig, AnimalStateData, PlantStateData,
│       │               # AnimalSpeciesConfig, HeightmapSampler
│       ├── Animals/    # AnimalNode.cs
│       └── Plants/     # PlantNode.cs
├── scenes/
│   ├── world/          # world_terrain.tscn
│   ├── player/         # fps_player.tscn
│   ├── animals/        # animal_base.tscn
│   ├── plants/         # plant_base.tscn
│   └── ui/             # debug_overlay.tscn
├── terrain_data/       # Yellowstone heightmap
└── addons/terrain_3d/
```

## Key Integration Points

| Component | Role |
|-----------|------|
| **SimSyncBridge** | Main-thread bridge; owns SimulationGrid, CellProcessor; promotes/demotes entities; syncs AnimalNode/PlantNode; exposes GetSnapshotArray for debug overlay |
| **SimulationGrid** | N×N spatial grid; cell assignment; neighbor queries; GetSnapshot for overlay |
| **CellProcessor** | Drives sim per cell; calls AnimalLogic/PlantLogic; ProcessTransfers at interval |
| **AnimalNode / PlantNode** | Thin Godot wrappers; ApplyState from bridge; no simulation logic |
| **DebugOverlay** | Fetches snapshot from SimSyncBridge; draws LOD grid, dots, player |
