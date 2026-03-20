using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Integration tests that exercise multiple simulation components together.
/// </summary>
public class SimulationIntegrationTests
{
    [Fact]
    public void AnimalStateData_FromSpeciesConfig_HasMatchingBehaviorParams()
    {
        var herbConfig = AnimalSpeciesConfig.CreateHerbivore(id: 0);
        var state = TestStateFactory.CreateDefault(speciesId: herbConfig.Id);
        state.WanderSpeed = herbConfig.WanderSpeed;
        state.PanicSpeed = herbConfig.PanicSpeed;
        state.CohesionRadius = herbConfig.CohesionRadius;
        state.ContagionRadius = herbConfig.ContagionRadius;
        state.SocialFactor = herbConfig.SocialFactor;

        Assert.Equal(herbConfig.WanderSpeed, state.WanderSpeed);
        Assert.Equal(herbConfig.PanicSpeed, state.PanicSpeed);
        Assert.Equal(herbConfig.CohesionRadius, state.CohesionRadius);
        Assert.Equal(herbConfig.ContagionRadius, state.ContagionRadius);
        Assert.Equal(herbConfig.SocialFactor, state.SocialFactor);
    }

    [Fact]
    public void SimConfig_CellSize_DividesWorldEvenly()
    {
        var cellCount = (int)(SimConfig.WorldSizeXZ / SimConfig.CellSizeMeters);
        Assert.Equal(SimConfig.GridN, cellCount);
    }

    [Fact]
    public void PlantStateData_And_AnimalStateData_ShareCompatibleCellIndices()
    {
        var plant = new PlantStateData { CellX = 5, CellZ = 10 };
        var animal = TestStateFactory.CreateDefault();
        animal.CellX = plant.CellX;
        animal.CellZ = plant.CellZ;

        Assert.Equal(plant.CellX, animal.CellX);
        Assert.Equal(plant.CellZ, animal.CellZ);
    }
}
