using Godot;
using Godot.Collections;
using System.Collections.Generic;

namespace BiologyGame.Simulation;

/// <summary>
/// C# accelerated versions of SimulationManager's hot GDScript loops.
///
/// Phase 4 optimization: these loops run every physics frame (60 Hz) over all animals.
/// Moving them from GDScript to C# eliminates interpreter overhead (~5–10× speedup).
///
/// Called from simulation_manager.gd via node.call() on the main thread.
/// All Godot API calls are safe here since we are on the main thread.
///
/// Add as a child of the same parent as SimulationManager (e.g. World root).
/// SimulationManager calls methods by node path.
/// </summary>
public partial class SimulationManagerBridge : Node
{
    // -------------------------------------------------------------------------
    // Grid rebuild
    // -------------------------------------------------------------------------

    /// <summary>
    /// Rebuilds the animal spatial grid.
    /// Replaces SimulationManager._rebuild_grid() in GDScript.
    ///
    /// Returns a Godot.Collections.Dictionary[Vector2I, Array] where each Array
    /// entry is a Dictionary{"n": Node3D, "s": int (species), "h": bool (is_hunter)}.
    ///
    /// Called from GDScript:
    ///   var grid = _bridge.call("rebuild_animal_grid", _animals_node, cell_size)
    /// </summary>
    public Dictionary RebuildAnimalGrid(Node animalsNode, float cellSize)
    {
        var grid = new Dictionary();
        if (animalsNode == null) return grid;

        foreach (var child in animalsNode.GetChildren())
        {
            if (child is not Node3D animal || !GodotObject.IsInstanceValid(animal)) continue;

            var pos = animal.GlobalPosition;
            var cell = CellKey(pos, cellSize);

            var species = 0;
            if (animal.Get("species").VariantType == Variant.Type.Int)
                species = (int)animal.Get("species").AsInt32();

            var isHunter = animal.IsInGroup("hunters");

            if (!grid.ContainsKey(cell))
                grid[cell] = new Array();

            var entry = new Dictionary { ["n"] = animal, ["s"] = species, ["h"] = isHunter };
            ((Array)grid[cell]).Add(entry);
        }

        return grid;
    }

    /// <summary>
    /// Rebuilds the plant spatial grid.
    /// Returns Dictionary[Vector2I, Array] where each Array entry is {"n": Node3D}.
    ///
    /// Called from GDScript:
    ///   var pgrid = _bridge.call("rebuild_plant_grid", _plants_node, cell_size)
    /// </summary>
    public Dictionary RebuildPlantGrid(Node plantsNode, float cellSize)
    {
        var grid = new Dictionary();
        if (plantsNode == null) return grid;

        foreach (var child in plantsNode.GetChildren())
        {
            if (child is not Node3D plant || !GodotObject.IsInstanceValid(plant)) continue;

            var cell = CellKey(plant.GlobalPosition, cellSize);
            if (!grid.ContainsKey(cell))
                grid[cell] = new Array();

            ((Array)grid[cell]).Add(new Dictionary { ["n"] = plant });
        }

        return grid;
    }

    // -------------------------------------------------------------------------
    // LOD classification
    // -------------------------------------------------------------------------

    /// <summary>
    /// Classifies the LOD tier for every animal in animalsNode in a single C# pass.
    /// Returns PackedInt32Array of length == animalsNode.GetChildCount(), where each entry is:
    ///   0 = FULL, 1 = MEDIUM, 2 = FAR
    ///
    /// Frustum bias: if camera is provided and frustum_bias is true, out-of-frustum animals
    /// are upgraded to FAR regardless of distance.
    ///
    /// Called from GDScript every physics frame:
    ///   var lods = _bridge.call("classify_lods", _animals_node, player_pos,
    ///                           full_sq, med_sq, camera, frustum_bias)
    /// </summary>
    public int[] ClassifyLods(
        Node animalsNode,
        Vector3 playerPos,
        float fullRadiusSq,
        float medRadiusSq,
        Camera3D camera,
        bool frustumBias)
    {
        if (animalsNode == null) return System.Array.Empty<int>();

        var children = animalsNode.GetChildren();
        var result = new int[children.Count];
        var i = 0;

        foreach (var child in children)
        {
            if (child is not Node3D animal || !GodotObject.IsInstanceValid(animal))
            {
                result[i++] = 2; // FAR for invalid
                continue;
            }

            var distSq = playerPos.DistanceSquaredTo(animal.GlobalPosition);
            int lod;
            if (distSq < fullRadiusSq)
                lod = 0; // FULL
            else if (distSq < medRadiusSq)
                lod = 1; // MEDIUM
            else
                lod = 2; // FAR

            // Frustum bias: out-of-frustum → FAR (skip if already FAR)
            if (lod != 2 && frustumBias && camera != null)
            {
                if (!camera.IsPositionInFrustum(animal.GlobalPosition))
                    lod = 2;
            }

            result[i++] = lod;
        }

        return result;
    }

    // -------------------------------------------------------------------------
    // FAR animal processing
    // -------------------------------------------------------------------------

    /// <summary>
    /// Processes FAR LOD physics management for all animals in a single C# pass.
    /// Disables physics process for FAR animals, re-enables for non-FAR.
    /// Tracks WasFarLod flag for terrain re-snap on promotion.
    ///
    /// Replaces SimulationManager._process_far_animals() for the physics management
    /// portion. Returns PackedVector3Array of animals that just left FAR (need terrain snap).
    ///
    /// int[] lodTiers must come from ClassifyLods() for the same animalsNode.
    ///
    /// Called from GDScript:
    ///   var snap_list = _bridge.call("apply_far_lod_physics", _animals_node, lod_tiers)
    /// </summary>
    public Vector3[] ApplyFarLodPhysics(Node animalsNode, int[] lodTiers)
    {
        if (animalsNode == null) return System.Array.Empty<Vector3>();

        var children = animalsNode.GetChildren();
        var needsSnap = new List<Vector3>();
        var i = 0;

        foreach (var child in children)
        {
            var lod = i < lodTiers.Length ? lodTiers[i] : 2;
            i++;

            if (child is not CharacterBody3D body || !GodotObject.IsInstanceValid(body))
                continue;

            if (lod == 2) // FAR
            {
                // Record was-FAR flag
                if (body.Get("WasFarLod").VariantType == Variant.Type.Bool)
                    body.Set("WasFarLod", true);
                else if (body.Get("_was_far_lod").VariantType == Variant.Type.Bool)
                    body.Set("_was_far_lod", true);
                body.SetPhysicsProcess(false);
            }
            else // FULL or MEDIUM
            {
                // Detect promotion from FAR (WasFarLod was true)
                var wasFar = false;
                if (body.Get("WasFarLod").VariantType == Variant.Type.Bool)
                    wasFar = body.Get("WasFarLod").AsBool();
                else if (body.Get("_was_far_lod").VariantType == Variant.Type.Bool)
                    wasFar = body.Get("_was_far_lod").AsBool();

                if (wasFar)
                {
                    // Clear flag; caller handles terrain snap
                    if (body.Get("WasFarLod").VariantType == Variant.Type.Bool)
                        body.Set("WasFarLod", false);
                    else if (body.Get("_was_far_lod").VariantType == Variant.Type.Bool)
                        body.Set("_was_far_lod", false);
                    needsSnap.Add(body.GlobalPosition);
                }
                body.SetPhysicsProcess(true);
            }
        }

        return needsSnap.ToArray();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static Vector2I CellKey(Vector3 pos, float cellSize)
    {
        return new Vector2I(
            (int)Mathf.Floor(pos.X / cellSize),
            (int)Mathf.Floor(pos.Z / cellSize)
        );
    }
}
