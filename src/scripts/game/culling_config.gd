extends Node
## Central config for culling, LOD, and shadow parameters.
## Tune all per-project thresholds here; referenced by PropMultimeshRenderer,
## PropPhysicsSpawner, SimulationManager, ImpostorRenderer, and WorldChunkManager.

# ---------------------------------------------------------------------------
# Prop rendering (Phase 1)
# ---------------------------------------------------------------------------

## Distance beyond which props (trees, rocks) are not rendered.
var prop_view_distance: float = 400.0
## Hysteresis margin for prop distance culling (avoids pop-in).
var prop_view_distance_margin: float = 20.0

# ---------------------------------------------------------------------------
# Impostor LOD (Phase 3)
# ---------------------------------------------------------------------------

## Trees beyond this distance switch from full 3D mesh to billboard impostor.
var impostor_near_distance: float = 150.0
## Trees beyond this distance are not rendered even as impostors.
var impostor_far_distance: float = 600.0

# ---------------------------------------------------------------------------
# Animal simulation LOD bias
# ---------------------------------------------------------------------------

## Treat animals outside camera frustum as FAR LOD.
var frustum_lod_bias_enabled: bool = true
## Treat terrain-occluded animals as FAR LOD.
var occlusion_lod_bias_enabled: bool = true
## Throttle: run occlusion check every N frames per animal.
var occlusion_check_interval_frames: int = 5

# ---------------------------------------------------------------------------
# Prop physics (Phase 1)
# ---------------------------------------------------------------------------

## Enable collision bodies when player is within this distance (meters).
var prop_physics_activate_radius: float = 60.0
## Remove collision bodies when player is beyond this (hysteresis).
var prop_physics_deactivate_radius: float = 80.0

# ---------------------------------------------------------------------------
# Shadow rendering (Phase 6)
# ---------------------------------------------------------------------------

## Maximum distance for directional shadow casting (meters).
## Lower = cheaper shadow maps; 150–200 m is typical for open-world.
## Set this on the DirectionalLight3D node in the scene (directional_shadow_max_distance).
var shadow_max_distance: float = 200.0
## Whether near-LOD MultiMesh trees (< impostor_near_distance) cast shadows.
var prop_near_cast_shadow: bool = false
## Whether impostor billboard layer casts shadows. Almost always false.
var impostor_cast_shadow: bool = false
