# BiologyGame

A rough prototype for an FPS with RPG elements, set in an open world where the player hunts animals. Built with Godot Engine 4 (.NET) using primarily GDScript.

## Features

- **PS1-style graphics**: Vertex jitter shader, heavy fog, low-poly aesthetic
- **FPS controls**: WASD movement, mouse look, jump
- **Minimal open world**: Flat terrain with placeholder props (trees, rocks)
- **Animal hunting**: Placeholder animals that can be hit and removed via raycast

## Requirements

- Godot Engine 4.6+
- Windows (PC only)

## Running the Game

1. Open the project in Godot (use `src/` as the project root, or open the folder containing `project.godot`).
2. Press F5 or click **Project > Run** to play.

## Controls

| Action | Input |
|--------|-------|
| Move | W A S D |
| Jump | Space |
| Shoot | Left mouse button |
| Toggle mouse capture | Escape |

## Project Structure

```
src/
├── main.tscn              # Entry scene
├── scenes/
│   ├── player/            # FPS controller
│   ├── world/             # Terrain, props, animals
│   └── animals/           # Animal base scene
├── scripts/
│   ├── player/
│   ├── animals/
│   └── game/
├── shaders/               # PS1-style vertex shader
├── materials/             # ShaderMaterial instances
├── environments/          # Fog, sky, lighting
└── ui/                    # Crosshair, health bar
```

## Extending the Prototype

### Adding Animals

1. Instance `scenes/animals/animal_base.tscn` in the world.
2. Set `max_health` in the inspector for tougher animals.
3. Connect to the `animal_defeated` signal for future XP/loot logic.

### Adjusting PS1 Aesthetic

- **Shader** (`shaders/ps1_style.gdshader`): Tweak `jitter`, `resolution`, and `affine_mapping` uniforms.
- **Environment** (`environments/ps1_environment.tres`): Adjust `volumetric_fog_density` and `volumetric_fog_length` for fog strength and draw distance.
- **Materials**: Override `albedo_color` for different surface colors.

### RPG Systems

The health bar in `ui/game_ui.tscn` is a placeholder. Connect it to a future player health system via signals. The `animal_defeated` signal on animals can feed into XP, drops, or quest logic.

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
