using Godot;
using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for PlantStateData struct.
/// </summary>
public class PlantStateDataTests
{
    [Fact]
    public void IsConsumed_WhenHealthZero_ReturnsTrue()
    {
        var plant = new PlantStateData { Health = 0, MaxHealth = 3 };
        Assert.True(plant.IsConsumed);
    }

    [Fact]
    public void IsConsumed_WhenHealthNegative_ReturnsTrue()
    {
        var plant = new PlantStateData { Health = -1, MaxHealth = 3 };
        Assert.True(plant.IsConsumed);
    }

    [Fact]
    public void IsConsumed_WhenHealthPositive_ReturnsFalse()
    {
        var plant = new PlantStateData { Health = 1, MaxHealth = 3 };
        Assert.False(plant.IsConsumed);
    }

    [Fact]
    public void AllFieldsCanBeSet()
    {
        var plant = new PlantStateData
        {
            Position = new Vector3(10, 0, 20),
            CellX = 2,
            CellZ = 4,
            Health = 2,
            MaxHealth = 3,
            SpeciesId = 1,
        };

        Assert.Equal(new Vector3(10, 0, 20), plant.Position);
        Assert.Equal(2, plant.CellX);
        Assert.Equal(4, plant.CellZ);
        Assert.Equal(2, plant.Health);
        Assert.Equal(3, plant.MaxHealth);
        Assert.Equal(1, plant.SpeciesId);
        Assert.False(plant.IsConsumed);
    }
}
