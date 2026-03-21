using System;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Populates animal and plant arrays for simulation. Spawns into sim only (no Godot nodes).
/// Call before grid Rebuild. Optional seed for reproducible debugging.
/// </summary>
public static class WorldPopulator
{
    /// <summary>
    /// Fill animals and plants arrays according to config. Arrays must be pre-allocated with correct size.
    /// </summary>
    public static void Populate(
        AnimalStateData[] animals,
        int animalCount,
        PlantStateData[] plants,
        int plantCount,
        in WorldPopulatorConfig config,
        AnimalSpeciesConfig herbivoreConfig,
        AnimalSpeciesConfig predatorConfig,
        ref Random rng)
    {
        for (var i = 0; i < animalCount && i < animals.Length; i++)
            SpawnAnimalAt(i, animals, ref rng, config, herbivoreConfig, predatorConfig);

        for (var i = 0; i < plantCount && i < plants.Length; i++)
            SpawnPlantAt(i, plants, ref rng, config);
    }

    /// <summary>Spawn a single animal at <paramref name="index"/>. Caller must register it on the grid (RegisterAnimal).</summary>
    public static void SpawnAnimalAt(
        int index,
        AnimalStateData[] animals,
        ref Random rng,
        in WorldPopulatorConfig config,
        AnimalSpeciesConfig herbivoreConfig,
        AnimalSpeciesConfig predatorConfig)
    {
        if (index < 0 || index >= animals.Length) return;

        var worldMinX = SimConfig.WorldOriginX;
        var worldMaxX = SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1f;
        var worldMinZ = SimConfig.WorldOriginZ;
        var worldMaxZ = SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 1f;

        var speciesId = (float)rng.NextDouble() < config.HerbivoreRatio ? 0 : 1;
        var cfg = speciesId == 0 ? herbivoreConfig : predatorConfig;
        var (x, z) = config.SpawnWholeMap
            ? RandomPointInRect(rng, worldMinX, worldMinZ, worldMaxX, worldMaxZ)
            : RandomPointInCircle(rng, config.SpawnCenterX, config.SpawnCenterZ, config.SpawnRadius);
        x = Mathf.Clamp(x, worldMinX, worldMaxX);
        z = Mathf.Clamp(z, worldMinZ, worldMaxZ);

        animals[index] = new AnimalStateData
        {
            Position = new Vector3(x, 0, z),
            Velocity = Vector3.Zero,
            State = 0,
            SpeciesId = (int)speciesId,
            Health = 100,
            CellX = 0,
            CellZ = 0,
            PanicTimer = 0,
            WanderTimer = 0,
            WanderTarget = new Vector3(x, 0, z),
            ThreatPosition = Vector3.Zero,
            WanderSpeed = cfg.WanderSpeed,
            PanicSpeed = cfg.PanicSpeed,
            SocialFactor = cfg.SocialFactor,
            CohesionRadius = cfg.CohesionRadius,
            ContagionRadius = cfg.ContagionRadius,
            PanicDuration = cfg.PanicDuration,
            WanderPauseMin = cfg.WanderPauseMin,
            WanderPauseMax = cfg.WanderPauseMax,
            WanderRadius = cfg.WanderRadius,
        };
    }

    /// <summary>Spawn a single plant at <paramref name="index"/>. Caller must register it on the grid (RegisterPlant).</summary>
    public static void SpawnPlantAt(int index, PlantStateData[] plants, ref Random rng, in WorldPopulatorConfig config)
    {
        if (index < 0 || index >= plants.Length) return;

        var worldMinX = SimConfig.WorldOriginX;
        var worldMaxX = SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1f;
        var worldMinZ = SimConfig.WorldOriginZ;
        var worldMaxZ = SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 1f;

        var (x, z) = config.SpawnWholeMap
            ? RandomPointInRect(rng, worldMinX, worldMinZ, worldMaxX, worldMaxZ)
            : RandomPointInCircle(rng, config.SpawnCenterX, config.SpawnCenterZ, config.SpawnRadius);
        x = Mathf.Clamp(x, worldMinX, worldMaxX);
        z = Mathf.Clamp(z, worldMinZ, worldMaxZ);

        plants[index] = new PlantStateData
        {
            Position = new Vector3(x, 0, z),
            CellX = 0,
            CellZ = 0,
            Health = config.PlantMaxHealth,
            MaxHealth = config.PlantMaxHealth,
            SpeciesId = 0,
        };
    }

    private static (float X, float Z) RandomPointInCircle(Random rng, float centerX, float centerZ, float radius)
    {
        var r = MathF.Sqrt((float)rng.NextDouble()) * radius;
        var theta = (float)(rng.NextDouble() * Math.PI * 2);
        var x = centerX + r * MathF.Cos(theta);
        var z = centerZ + r * MathF.Sin(theta);
        return (x, z);
    }

    private static (float X, float Z) RandomPointInRect(Random rng, float minX, float minZ, float maxX, float maxZ)
    {
        var x = minX + (float)rng.NextDouble() * (maxX - minX);
        var z = minZ + (float)rng.NextDouble() * (maxZ - minZ);
        return (x, z);
    }
}
