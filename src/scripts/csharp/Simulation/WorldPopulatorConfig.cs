using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Configuration for WorldPopulator. Spawn counts, distribution, and optional seed.
/// </summary>
public struct WorldPopulatorConfig
{
    /// <summary>Total animals to spawn.</summary>
    public int AnimalCount;

    /// <summary>Fraction of animals that are herbivores (0–1). Rest are predators.</summary>
    public float HerbivoreRatio;

    /// <summary>Total plants to spawn.</summary>
    public int PlantCount;

    /// <summary>World X of spawn center (e.g. near player start).</summary>
    public float SpawnCenterX;

    /// <summary>World Z of spawn center.</summary>
    public float SpawnCenterZ;

    /// <summary>Radius around center for spawn distribution (meters). Ignored if SpawnWholeMap.</summary>
    public float SpawnRadius;

    /// <summary>If true, spawn evenly across entire world. Ignores SpawnCenter and SpawnRadius.</summary>
    public bool SpawnWholeMap;

    /// <summary>Optional RNG seed for reproducible runs. Null = random.</summary>
    public int? Seed;

    /// <summary>Plant max health (all plants).</summary>
    public int PlantMaxHealth;

    /// <summary>Default playtest config: cluster near origin, good mix for testing.</summary>
    public static WorldPopulatorConfig DefaultPlaytest()
    {
        return new WorldPopulatorConfig
        {
            AnimalCount = 80,
            HerbivoreRatio = 0.7f,
            PlantCount = 200,
            SpawnCenterX = SimConfig.WorldOriginX + 400f,
            SpawnCenterZ = SimConfig.WorldOriginZ + 400f,
            SpawnRadius = 600f,
            Seed = null,
            PlantMaxHealth = 3,
        };
    }
}
