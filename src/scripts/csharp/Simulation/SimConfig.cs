namespace BiologyGame.Simulation;

/// <summary>
/// Simulation parameters: grid size, LOD thresholds, world bounds, thread pool hints.
/// Tune N, M, A/B/C/D for performance.
/// </summary>
public static class SimConfig
{
    /// <summary>Grid dimension N (N×N cells). Configurable for optimization.</summary>
    public const int GridN = 32;

    /// <summary>Interval (seconds) between cell-boundary checks and entity transfers.</summary>
    public const float TransferIntervalSeconds = 3.0f;

    /// <summary>Manhattan cell distance &lt; A: full sim + Godot sync every tick.</summary>
    public const int LOD_A_Cells = 2;

    /// <summary>Manhattan cell distance &lt; B: full sim async, no Godot.</summary>
    public const int LOD_B_Cells = 4;

    /// <summary>Manhattan cell distance &lt; C: simplified sim.</summary>
    public const int LOD_C_Cells = 8;

    /// <summary>Manhattan cell distance &lt; D: low-res sim (larger delta).</summary>
    public const int LOD_D_Cells = 16;

    /// <summary>Lateral world size in meters (X and Z). From WorldConstants.</summary>
    public const float WorldSizeXZ = 8192.0f;

    /// <summary>Half-extent from world origin. For centered terrain: WorldSizeXZ * 0.5.</summary>
    public const float HalfExtentXZ = WorldSizeXZ * 0.5f;

    /// <summary>World X of min corner (e.g. 0 for 0..N, or -HalfExtentXZ for centered).</summary>
    public const float WorldOriginX = 0f;

    /// <summary>World Z of min corner.</summary>
    public const float WorldOriginZ = 0f;

    /// <summary>Cell size in world units. WorldSizeXZ / GridN.</summary>
    public static readonly float CellSizeMeters = WorldSizeXZ / GridN;

    /// <summary>Thread count for cell processor pool. Use Environment.ProcessorCount or less.</summary>
    public static int ThreadPoolSize => System.Environment.ProcessorCount > 0 ? System.Environment.ProcessorCount - 1 : 4;

    /// <summary>Plant regrowth: health points per second when 0 &lt; Health &lt; MaxHealth.</summary>
    public const float PlantRegrowthRate = 0.2f;

    /// <summary>Plant respawn: health points per second when Health == 0 (slower regrowth from consumed).</summary>
    public const float PlantRespawnRate = 0.05f;

    /// <summary>Delta multiplier for tier 3 (low-res sim). Tier 2 uses 1.5, tier 1 uses 1.0.</summary>
    public const float LOD_Tier3_DeltaMultiplier = 2.0f;

    /// <summary>Delta multiplier for tier 2 (simplified sim).</summary>
    public const float LOD_Tier2_DeltaMultiplier = 1.5f;

    /// <summary>Extra cells beyond LOD_A for demote threshold. Demote when distance &gt; A + this.</summary>
    public const int LOD_HysteresisCells = 1;
}
