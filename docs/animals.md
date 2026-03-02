# Animals

This document covers animal species, AI behaviors, and the class hierarchy.

## Species

```mermaid
pie showData
    title Species Distribution (WorldPopulator defaults)
    "Deer (forager)" : 500
    "Rabbit (forager)" : 250
    "Bison (forager)" : 0
    "Wolf (hunter)" : 125
    "Bear (hunter)" : 125
```

| ID | Species | Type | Notes |
|----|---------|------|-------|
| 0 | Bison | Forager | Default base animal |
| 1 | Deer | Forager | Eats plants, flees hunters |
| 2 | Rabbit | Forager | Eats plants, flees hunters |
| 3 | Wolf | Hunter | Stalks, chases, kills prey |
| 4 | Bear | Hunter | Stalks, chases, kills prey |

Species IDs are defined in `species_constants.gd` and `AnimalBase.Species` (C#) and must match.

## Class Hierarchy

```mermaid
classDiagram
    CharacterBody3D <|-- AnimalBase
    AnimalBase <|-- ForagerAnimal
    AnimalBase <|-- HunterAnimal
    
    class CharacterBody3D {
        +Velocity
        +MoveAndSlide()
    }
    
    class AnimalBase {
        +Species species
        +State _state
        +int Health
        +float WanderSpeed
        +float PanicSpeed
        +float DetectionRange
        +float CohesionRadius
        +float ContagionRadius
        +UpdateState(delta)
        +ApplyMovement(delta)
        +ProcessFarTick(delta, ai, move)
        +TakeDamage(amount)
        +ExportStateData()
        +ApplyStateData(state)
    }
    
    class ForagerAnimal {
        +PlantDetectionRange
        +HunterDetectionRange
        +HunterSafeDistance
        +EatingDuration
        -ForagerState _foragerState
        -Node3D _currentPlant
        +UpdateState(delta)
        +ApplyMovement(delta)
    }
    
    class HunterAnimal {
        +StalkSpeed
        +ChaseSpeed
        +ChaseTriggerRange
        +KillRange
        +KillDamage
        -HunterState _hunterState
        -CharacterBody3D _currentTarget
        +UpdateState(delta)
        +ApplyMovement(delta)
    }
```

## AnimalBase States

```mermaid
stateDiagram-v2
    [*] --> Wandering
    Wandering --> Panicking: Threat detected (player/hunter)
    Panicking --> Wandering: PanicTimer expires
    Panicking --> Wandering: Contagion calm (social)
```

### Base Behaviors

- **Wandering**: Pick random target within `WanderRadius`, move toward it, pause between targets.
- **Panicking**: Move away from `_threatPosition` at `PanicSpeed`.
- **Contagion**: Nearby panicking same-species can spread panic; nearby calm same-species can shorten panic.
- **Cohesion**: In FULL LOD, apply social vector toward center of same-species in `CohesionRadius`.

## ForagerAnimal States

```mermaid
stateDiagram-v2
    [*] --> Wandering
    Wandering --> Eating: Plant in range
    Eating --> Wandering: Plant consumed/invalid
    Wandering --> Panicking: Hunter in range
    Eating --> Panicking: Hunter in range
    Panicking --> Wandering: HunterSafeDistance or panic expires
```

### Forager-Specific Behaviors

- **Eating**: Stay still, call `plant.consume()` each `EatingDuration` seconds.
- **Hunter flee**: Detect hunters via `get_hunters_in_radius()`, panic until `HunterSafeDistance` or hunter gone.
- **Plant detection**: `get_plants_in_radius()` for non-consumed plants.

## HunterAnimal States

```mermaid
stateDiagram-v2
    [*] --> Wandering
    Wandering --> Stalking: Prey in DetectionRange
    Stalking --> Chasing: Prey panics OR within ChaseTriggerRange
    Stalking --> Wandering: Prey lost
    Chasing --> Killing: Within KillRange
    Chasing --> Wandering: Prey lost
    Killing --> Wandering: Deal KillDamage to prey
```

### Hunter-Specific Behaviors

- **Stalking**: Move toward prey at `StalkSpeed` (with cohesion in FULL).
- **Chasing**: Move toward prey at `ChaseSpeed` when prey panics or is within `ChaseTriggerRange`.
- **Killing**: Stop, call `prey.take_damage(KillDamage)` (typically 999).
- **Prey selection**: `get_animals_in_radius()` excluding hunters.

## SimulationManager Integration

Animals query SimulationManager for spatial data:

```mermaid
sequenceDiagram
    participant A as Animal
    participant S as SimulationManager
    
    A->>S: get_lod_tier(pos)
    S-->>A: FULL | MEDIUM | FAR
    
    A->>S: get_same_species_in_radius(pos, radius, species, self)
    S-->>A: Array of same-species nodes
    
    A->>S: get_hunters_in_radius(pos, radius)  [Forager only]
    S-->>A: Array of hunter nodes
    
    A->>S: get_plants_in_radius(pos, radius)   [Forager only]
    S-->>A: Array of plant nodes
    
    A->>S: get_animals_in_radius(pos, radius, self)  [Hunter only]
    S-->>A: Array of animal nodes (prey)
```

## Groups

| Group | Used By |
|-------|---------|
| `animals` | All animals (base, forager, hunter) |
| `foragers` | ForagerAnimal |
| `hunters` | HunterAnimal |
| `simulation_manager` | SimulationManager (for lookup) |
| `player` | Player (for threat/raycast) |
| `plants` | Plant nodes |

## Signals

- **AnimalDefeated**: Emitted when `Health <= 0` after `TakeDamage`. Used for future XP/loot.

## Scene Structure

Each animal scene has:

- `CharacterBody3D` root (C# script)
- `Model` child (MeshInstance3D or packed scene) — PS1 effect applied in `_Ready` if `UsePs1Effect`
- Debug `Label3D` and `MeshInstance3D` added at runtime (SimulationManager debug mode)
