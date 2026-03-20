using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pure data struct for plant state. Simulated separately from animals.
/// Safe for worker thread.
/// </summary>
public struct PlantStateData
{
    /// <summary>World position.</summary>
    public Vector3 Position;

    /// <summary>Grid cell X index.</summary>
    public int CellX;

    /// <summary>Grid cell Z index.</summary>
    public int CellZ;

    /// <summary>Current health. 0 = consumed.</summary>
    public int Health;

    /// <summary>Max health when fully grown.</summary>
    public int MaxHealth;

    /// <summary>Species ID for model/scene selection on promote.</summary>
    public int SpeciesId;

    /// <summary>Accumulated fractional health for regrowth. Internal to PlantLogic.</summary>
    public float RegrowthAccumulator;

    /// <summary>True when Health &lt;= 0 (no longer available for consumption).</summary>
    public readonly bool IsConsumed => Health <= 0;
}
