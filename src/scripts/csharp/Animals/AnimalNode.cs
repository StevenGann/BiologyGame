using Godot;
using BiologyGame.Simulation;

namespace BiologyGame.Animals;

/// <summary>
/// Thin Godot wrapper for promoted animals. Applies state from SimSyncBridge.
/// No simulation logic; presentation only. Optional: face movement direction.
/// </summary>
public partial class AnimalNode : Node3D
{
    /// <summary>
    /// Apply simulation state for display. Call from SimSyncBridge each sync.
    /// </summary>
    /// <param name="worldPosition">World position including terrain height.</param>
    /// <param name="velocity">Movement direction; used to orient the mesh if moving.</param>
    /// <param name="speciesId">Species ID for optional model/color variation (0=herbivore, 1=predator).</param>
    public void ApplyState(Vector3 worldPosition, Vector3 velocity, int speciesId = 0)
    {
        GlobalPosition = worldPosition;

        var flatVel = new Vector3(velocity.X, 0, velocity.Z);
        if (flatVel.LengthSquared() > 0.01f)
        {
            var lookTarget = GlobalPosition + flatVel.Normalized();
            LookAt(lookTarget, Vector3.Up);
        }
    }

    /// <summary>
    /// Apply full state from struct. Convenience for bridge.
    /// </summary>
    public void ApplyStateData(AnimalStateData state)
    {
        ApplyState(state.Position, state.Velocity, state.SpeciesId);
    }
}
