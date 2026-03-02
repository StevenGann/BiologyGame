# Player & Combat

This document covers the FPS player controller and combat (shooting, tranq darts).

## Player Controller

```mermaid
flowchart TD
    Input[Input Events]
    Input --> Movement[WASD Movement]
    Input --> Jump[Jump Space]
    Input --> MouseLook[Mouse Look]
    Input --> Shoot[Shoot LMB]
    Input --> Escape[Escape - Toggle Mouse]
    
    Movement --> _physics_process
    Jump --> _physics_process
    MouseLook --> _input
    Shoot --> _input
    Escape --> _input
    
    _physics_process --> MoveAndSlide[move_and_slide]
```

### Controls

| Action | Input |
|--------|-------|
| Move | W A S D |
| Jump | Space |
| Shoot | Left mouse button |
| Toggle mouse capture | Escape |

### Movement Parameters

| Constant | Value | Description |
|----------|-------|-------------|
| SPEED | 5.0 | Normal walk |
| SPEED_BOOST | 10.0 | When Shift held (testing) |
| JUMP_VELOCITY | 4.5 | Jump strength |
| MOUSE_SENSITIVITY | 0.002 | Look sensitivity |
| CAMERA_PITCH_LIMIT | 89° | Vertical look limit |

### Input Flow

1. `main.gd` pushes input to `GameViewport` SubViewport.
2. Player receives input inside the viewport.
3. Backtick (`) toggles SimulationManager debug mode (handled in main before viewport push).

## Shooting

```mermaid
sequenceDiagram
    participant P as Player
    participant R as RayCast3D
    participant C as Collider
    participant A as Animal
    
    P->>P: shoot()
    P->>R: force_raycast_update()
    R-->>P: is_colliding, hit_point, collider
    P->>P: _place_tranq_dart(...)
    P->>C: take_damage(1) if has method
    C->>A: TakeDamage(1)
```

### Raycast

- Attached to `Player/Camera3D/RayCast3D`.
- Fires from camera center on shoot action.
- Returns `collision_point`, `collision_normal`, `collider`.

### Damage

- If collider has `take_damage(amount)` (e.g. animals), it is called with 1 damage.
- Animals: `TakeDamage()` reduces health, triggers panic from player position; if health <= 0, emits `animal_defeated` and `QueueFree()`.

## Tranq Dart

```mermaid
flowchart TD
    Hit[Hit Result]
    Hit --> IsAnimal{Has take_damage?}
    IsAnimal -->|Yes| ParentToAnimal[Parent dart to animal]
    IsAnimal -->|No| ParentToWorld[Parent to World/TranqDarts]
    
    ParentToAnimal --> Stick[Stick to animal]
    ParentToWorld --> StickTerrain[Stick to terrain]
    
    Stick --> FreeWithAnimal[Dart freed when animal removed]
```

### Placement

- Instantiated from `res://scenes/weapons/tranq_dart.tscn`.
- Position: `hit_point + dir_toward_player * DART_OFFSET` (0.08) to avoid z-fighting.
- Orientation: `Basis.looking_at(dir_toward_player, up_hint)`.
- **Parent**: If hit object has `take_damage` (animal), parent to animal so dart disappears when animal is removed; otherwise parent to `World/TranqDarts`.

## Scene Hierarchy

```
Player (CharacterBody3D)
├── Camera3D
│   └── RayCast3D
└── (collision shape, etc.)
```

Player is a sibling of World under GameViewport; raycast hits world geometry and animals in the same viewport.
