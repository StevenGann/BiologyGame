using Godot;
using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

public class WorldPopulatorTests
{
    [Fact]
    public void Populate_WithSeed_Reproducible()
    {
        var animals1 = new AnimalStateData[10];
        var plants1 = new PlantStateData[5];
        var animals2 = new AnimalStateData[10];
        var plants2 = new PlantStateData[5];
        var config = new WorldPopulatorConfig
        {
            AnimalCount = 10,
            HerbivoreRatio = 0.5f,
            PlantCount = 5,
            SpawnCenterX = 100,
            SpawnCenterZ = 100,
            SpawnRadius = 50,
            Seed = 42,
            PlantMaxHealth = 3,
        };
        var herb = AnimalSpeciesConfig.CreateHerbivore(0);
        var pred = AnimalSpeciesConfig.CreatePredator(1);

        WorldPopulator.Populate(animals1, 10, plants1, 5, config, herb, pred);
        WorldPopulator.Populate(animals2, 10, plants2, 5, config, herb, pred);

        Assert.Equal(animals1[0].Position.X, animals2[0].Position.X);
        Assert.Equal(animals1[0].Position.Z, animals2[0].Position.Z);
        Assert.Equal(plants1[0].Position.X, plants2[0].Position.X);
    }

    [Fact]
    public void Populate_RespectsHerbivoreRatio()
    {
        var animals = new AnimalStateData[100];
        var plants = new PlantStateData[10];
        var config = new WorldPopulatorConfig
        {
            AnimalCount = 100,
            HerbivoreRatio = 1f,
            PlantCount = 10,
            SpawnCenterX = 0,
            SpawnCenterZ = 0,
            SpawnRadius = 100,
            Seed = 123,
            PlantMaxHealth = 3,
        };
        var herb = AnimalSpeciesConfig.CreateHerbivore(0);
        var pred = AnimalSpeciesConfig.CreatePredator(1);

        WorldPopulator.Populate(animals, 100, plants, 10, config, herb, pred);

        var herbivoreCount = 0;
        for (var i = 0; i < 100; i++)
            if (animals[i].SpeciesId == 0) herbivoreCount++;
        Assert.Equal(100, herbivoreCount);
    }

    [Fact]
    public void Populate_SpawnWholeMap_DistributesAcrossWorld()
    {
        var animals = new AnimalStateData[50];
        var plants = new PlantStateData[20];
        var config = new WorldPopulatorConfig
        {
            AnimalCount = 50,
            HerbivoreRatio = 0.5f,
            PlantCount = 20,
            SpawnWholeMap = true,
            SpawnCenterX = 0,
            SpawnCenterZ = 0,
            SpawnRadius = 100,
            Seed = 777,
            PlantMaxHealth = 3,
        };
        var herb = AnimalSpeciesConfig.CreateHerbivore(0);
        var pred = AnimalSpeciesConfig.CreatePredator(1);

        WorldPopulator.Populate(animals, 50, plants, 20, config, herb, pred);

        var minX = float.MaxValue;
        var maxX = float.MinValue;
        var minZ = float.MaxValue;
        var maxZ = float.MinValue;
        for (var i = 0; i < 50; i++)
        {
            minX = Math.Min(minX, animals[i].Position.X);
            maxX = Math.Max(maxX, animals[i].Position.X);
            minZ = Math.Min(minZ, animals[i].Position.Z);
            maxZ = Math.Max(maxZ, animals[i].Position.Z);
        }
        Assert.True(minX < SimConfig.WorldOriginX + 1000, "Animals should span across map");
        Assert.True(maxX > SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1000, "Animals should span across map");
    }

    [Fact]
    public void Populate_ClampsToWorldBounds()
    {
        var animals = new AnimalStateData[20];
        var plants = new PlantStateData[5];
        var config = new WorldPopulatorConfig
        {
            AnimalCount = 20,
            HerbivoreRatio = 0.5f,
            PlantCount = 5,
            SpawnCenterX = 0,
            SpawnCenterZ = 0,
            SpawnRadius = 50000f,
            Seed = 999,
            PlantMaxHealth = 3,
        };
        var herb = AnimalSpeciesConfig.CreateHerbivore(0);
        var pred = AnimalSpeciesConfig.CreatePredator(1);

        WorldPopulator.Populate(animals, 20, plants, 5, config, herb, pred);

        for (var i = 0; i < 20; i++)
        {
            Assert.InRange(animals[i].Position.X, SimConfig.WorldOriginX, SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1);
            Assert.InRange(animals[i].Position.Z, SimConfig.WorldOriginZ, SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 1);
        }
    }
}
