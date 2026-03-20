# Simulation System

The simulation manages spatial partitioning, LOD (Level of Detail), and efficient simulation of animals and plants across a 32×32 grid over an 8192×8192 m world.

## LOD Tiers

Cells are assigned LOD tiers based on Manhattan distance from the player cell:

```mermaid
graph LR
    subgraph LOD[LOD Tiers by Cell Distance]
        T0["Tier 0: dist ≤ 2"]
        T1["Tier 1: dist ≤ 4"]
        T2["Tier 2: dist ≤ 8"]
        T3["Tier 3: dist ≤ 16"]
    end

    Player((Player Cell))
    Player --> T0
    T0 --> T1
    T1 --> T2
    T2 --> T3
```

| Tier | Manhattan Distance | Simulation | Godot Nodes |
|------|--------------------|------------|-------------|
| **0** | ≤ 2 cells | Full, every tick | Yes (AnimalNode, PlantNode) |
| **1** | ≤ 4 cells | Full, delta ×1.0 | No |
| **2** | ≤ 8 cells | Simplified, delta ×1.5 | No |
| **3** | ≤ 16 cells | Low-res, delta ×2.0 | No |
| Beyond | > 16 cells | Not simulated | No |

## Promotion and Demotion

```mermaid
stateDiagram-v2
    [*] --> InGrid: WorldPopulator spawn
    InGrid --> HasNode: Player within LOD_A (2 cells)
    HasNode --> InGrid: Player beyond LOD_A + Hysteresis (3 cells)
```

- **Promote**: Entity within LOD_A cells of player → create AnimalNode/PlantNode, add to scene.
- **Demote**: Entity beyond LOD_A + LOD_HysteresisCells → remove node, keep state in grid.

Hysteresis prevents thrashing at the boundary.

## Spatial Grid

```mermaid
flowchart TB
    subgraph Grid[SimulationGrid 32×32]
        C00[Cell 0,0]
        C10[Cell 1,0]
        C01[Cell 0,1]
        Cnn["..."]
    end

    Animals[AnimalStateData array]
    Plants[PlantStateData array]
    Animals --> Rebuild[Rebuild]
    Plants --> Rebuild
    Rebuild --> Grid
    Grid --> NeighborQueries[GetAnimalIndicesInCell etc]
```

### Grid API

| Method | Purpose |
|--------|---------|
| `Rebuild()` | Clear and reassign all entities to cells |
| `ProcessTransfers()` | Move entities that crossed cell boundaries |
| `GetAnimalIndicesInCell(cx, cz)` | Animal indices in cell |
| `GetPlantIndicesInCell(cx, cz)` | Plant indices in cell |
| `GetSnapshot(outBuffer)` | Pack [x, z, isAnimal, speciesId, ...] for debug overlay |

### Configuration (SimConfig)

| Constant | Value | Description |
|----------|-------|-------------|
| GridN | 32 | Grid dimension |
| TransferIntervalSeconds | 3.0 | Interval for ProcessTransfers |
| LOD_A_Cells | 2 | Promote threshold |
| LOD_HysteresisCells | 1 | Demote = A + 1 |
| WorldSizeXZ | 8192 | World extent (m) |

## CellProcessor

Drives simulation by iterating cells by LOD tier:

```mermaid
flowchart LR
    Tick[CellProcessor.Tick]
    Tick --> PlayerCell[Compute player cell]
    PlayerCell --> Tier0[Process tier 0 cells]
    Tier0 --> Tier1[Process tier 1 cells]
    Tier1 --> Tier2[Process tier 2 cells]
    Tier2 --> Tier3[Process tier 3 cells]
    Tier3 --> Transfers[ProcessTransfers if interval]
```

- Tier 0: Full AnimalLogic + PlantLogic; SimSyncBridge syncs positions to nodes.
- Tiers 1–3: Same logic with delta multipliers; no Godot nodes.

## AnimalLogic

Pure C# logic; no Godot APIs. Used by CellProcessor for all tiers.

```mermaid
flowchart LR
    UpdateStateFar[UpdateStateFar]
    ApplySimpleWander[ApplySimpleWander]

    UpdateStateFar --> Contagion[Contagion: panic spread]
    UpdateStateFar --> PanicDecay[Panic decay]
    UpdateStateFar --> WanderTarget[Wander target refresh]

    ApplySimpleWander --> PanicMove[Panic: flee threat]
    ApplySimpleWander --> WanderMove[Wander: move to target + cohesion]
```

### Behaviors

- **Contagion**: Nearby panicking same-species can spread panic; nearby calm can shorten panic.
- **Panic**: Flee from `ThreatPosition`; decay timer.
- **Wander**: Move toward random target; pause; cohesion toward same-species center.

## PlantLogic

- **Regrowth**: Health < MaxHealth → increase at PlantRegrowthRate.
- **Respawn**: Health == 0 → increase at PlantRespawnRate.
- **Consumed**: IsConsumed plants excluded from spatial queries.

## Debug Overlay

Press **F1** or **`** to toggle. Shows:

- LOD grid (tier 0 green, tier 1 yellow, tier 2 orange, tier 3 red)
- Animal and plant dots (sampled, capped)
- Player position (cyan)

Optimizations: throttled redraws, SubViewport at lower resolution, snapshot buffer reuse.
