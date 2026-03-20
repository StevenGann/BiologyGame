using Godot;
using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for PlantLogic.
/// </summary>
public class PlantLogicTests
{
    [Fact]
    public void Update_FullyGrown_NoChange()
    {
        var plant = new PlantStateData
        {
            Health = 3,
            MaxHealth = 3,
            RegrowthAccumulator = 0f,
        };

        PlantLogic.Update(1f, ref plant);

        Assert.Equal(3, plant.Health);
        Assert.Equal(0f, plant.RegrowthAccumulator);
    }

    [Fact]
    public void Update_Damaged_RegrowsOverTime()
    {
        var plant = new PlantStateData
        {
            Health = 1,
            MaxHealth = 3,
            RegrowthAccumulator = 0f,
        };

        // 0.2 health/sec: 5 seconds to gain 1 health
        for (var i = 0; i < 5; i++)
            PlantLogic.Update(1f, ref plant);

        Assert.Equal(2, plant.Health);
    }

    [Fact]
    public void Update_Consumed_RespawnsOverTime()
    {
        var plant = new PlantStateData
        {
            Health = 0,
            MaxHealth = 3,
            RegrowthAccumulator = 0f,
        };

        // 0.05 health/sec: 20 seconds to respawn from 0 to 1
        for (var i = 0; i < 20; i++)
            PlantLogic.Update(1f, ref plant);

        Assert.Equal(1, plant.Health);
    }

    [Fact]
    public void Update_StopsAtMaxHealth()
    {
        var plant = new PlantStateData
        {
            Health = 2,
            MaxHealth = 3,
            RegrowthAccumulator = 0.9f, // Almost 1 full point
        };

        PlantLogic.Update(1f, ref plant);

        Assert.Equal(3, plant.Health);
        Assert.True(plant.RegrowthAccumulator < 1f);
    }
}
