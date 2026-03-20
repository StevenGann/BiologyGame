using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for AnimalSpeciesConfig.
/// </summary>
public class AnimalSpeciesConfigTests
{
    [Fact]
    public void CreateHerbivore_IsNotPredator()
    {
        var config = AnimalSpeciesConfig.CreateHerbivore(id: 0);
        Assert.False(config.IsPredator);
        Assert.Equal(0, config.Id);
    }

    [Fact]
    public void CreatePredator_IsPredator()
    {
        var config = AnimalSpeciesConfig.CreatePredator(id: 1);
        Assert.True(config.IsPredator);
        Assert.Equal(1, config.Id);
    }

    [Fact]
    public void CreateHerbivore_HasReasonableSpeeds()
    {
        var config = AnimalSpeciesConfig.CreateHerbivore();
        Assert.True(config.WanderSpeed > 0);
        Assert.True(config.PanicSpeed > config.WanderSpeed);
    }

    [Fact]
    public void CreatePredator_HasReasonableSpeeds()
    {
        var config = AnimalSpeciesConfig.CreatePredator();
        Assert.True(config.WanderSpeed > 0);
        Assert.True(config.PanicSpeed > config.WanderSpeed);
    }

    [Fact]
    public void CreateHerbivore_WithScenePath_PreservesPath()
    {
        var path = "res://scenes/animals/herbivore.tscn";
        var config = AnimalSpeciesConfig.CreateHerbivore(id: 0, scenePath: path);
        Assert.Equal(path, config.ScenePath);
    }

    [Fact]
    public void CreatePredator_WithScenePath_PreservesPath()
    {
        var path = "res://scenes/animals/predator.tscn";
        var config = AnimalSpeciesConfig.CreatePredator(id: 1, scenePath: path);
        Assert.Equal(path, config.ScenePath);
    }

    [Fact]
    public void HerbivoreAndPredator_HaveDifferentPresets()
    {
        var herb = AnimalSpeciesConfig.CreateHerbivore(id: 0);
        var pred = AnimalSpeciesConfig.CreatePredator(id: 1);
        Assert.NotEqual(herb.WanderSpeed, pred.WanderSpeed);
        Assert.NotEqual(herb.PanicSpeed, pred.PanicSpeed);
    }
}
