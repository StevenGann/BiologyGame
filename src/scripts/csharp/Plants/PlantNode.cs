using Godot;
using BiologyGame.Simulation;

namespace BiologyGame.Plants;

/// <summary>
/// Thin Godot wrapper for promoted plants. Applies state from SimSyncBridge.
/// No simulation logic; presentation only. Uses StaticBody3D for future collisions.
/// </summary>
public partial class PlantNode : Node3D
{
    /// <summary>
    /// Apply simulation state for display. Call from SimSyncBridge each sync.
    /// </summary>
    /// <param name="worldPosition">World position including terrain height.</param>
    /// <param name="visible">Whether the plant is visible (not consumed).</param>
    public void ApplyState(Vector3 worldPosition, bool visible = true)
    {
        GlobalPosition = worldPosition;
        Visible = visible;
    }

    /// <summary>
    /// Apply state from struct. Convenience for bridge.
    /// </summary>
    public void ApplyStateData(PlantStateData state)
    {
        ApplyState(state.Position, !state.IsConsumed);
    }
}
