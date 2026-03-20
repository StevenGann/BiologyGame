# Visual Style

Environment, lighting, and materials.

## Scene Setup

- **WorldEnvironment**: Procedural sky, ambient light.
- **DirectionalLight3D**: Sun; shadows enabled.
- **Terrain3D**: Heightmap-based terrain with material.

## Environment

- Background mode: Sky
- Ambient light from sky
- Ambient light energy and color tuned for outdoor look

## Materials

- Terrain: Terrain3D material
- Animals/plants: Assigned in scenes (animal_base, plant_base)

## Customization

| Target | Location |
|--------|----------|
| Sky, ambient | main.tscn WorldEnvironment |
| Sun | main.tscn DirectionalLight3D |
| Terrain | world_terrain.tscn, Terrain3D |
