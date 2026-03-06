extends Node
## Central config for culling parameters. Tune here for all props and simulation LOD.
## Used by random_tree, random_rock, plant (view distance) and SimulationManager (LOD bias).

## Distance beyond which props are not rendered.
var prop_view_distance: float = 400.0
## Hysteresis margin for prop distance culling (avoids pop-in).
var prop_view_distance_margin: float = 20.0

## Treat animals outside camera frustum as FAR LOD.
var frustum_lod_bias_enabled: bool = true
## Treat terrain-occluded animals as FAR LOD.
var occlusion_lod_bias_enabled: bool = true
## Throttle: run occlusion check every N frames per animal.
var occlusion_check_interval_frames: int = 5

## Prop physics: enable collision when player within this distance (meters).
var prop_physics_activate_radius: float = 60.0
## Prop physics: disable collision when player beyond this (hysteresis).
var prop_physics_deactivate_radius: float = 80.0
