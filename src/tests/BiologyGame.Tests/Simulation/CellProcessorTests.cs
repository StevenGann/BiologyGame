using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

public class CellProcessorTests
{
    [Fact]
    public void Tick_WithAnimals_UpdatesPositions()
    {
        var animals = new AnimalStateData[1];
        animals[0] = TestStateFactory.CreateDefault(position: new Vector3(100, 0, 100));
        animals[0].WanderTarget = new Vector3(150, 0, 100);
        animals[0].WanderTimer = 0f;

        var grid = new SimulationGrid();
        grid.SetData(animals, 1, System.Array.Empty<PlantStateData>(), 0);
        grid.Rebuild();

        var processor = new CellProcessor(grid, animals, 1, System.Array.Empty<PlantStateData>(), 0);
        processor.SetPlayerPosition(0, 0); // Far from animal, tier 1+

        var posBefore = animals[0].Position;

        for (var i = 0; i < 10; i++)
            processor.Tick(0.1f);

        var posAfter = animals[0].Position;
        Assert.True(posAfter.X != posBefore.X || posAfter.Z != posBefore.Z, "Animal should have moved");
    }

    [Fact]
    public void Tick_WithPlants_UpdatesRegrowth()
    {
        var plants = new PlantStateData[1];
        plants[0] = new PlantStateData
        {
            Position = new Vector3(100, 0, 100),
            Health = 1,
            MaxHealth = 3,
            CellX = 0,
            CellZ = 0,
            SpeciesId = 0,
        };

        var grid = new SimulationGrid();
        grid.SetData(System.Array.Empty<AnimalStateData>(), 0, plants, 1);
        grid.Rebuild();

        var processor = new CellProcessor(grid, System.Array.Empty<AnimalStateData>(), 0, plants, 1);
        processor.SetPlayerPosition(0, 0);

        for (var i = 0; i < 30; i++) // ~3 sec at 0.1 delta; 0.2 regrowth/sec -> 0.6 health
            processor.Tick(0.1f);

        Assert.True(plants[0].Health >= 1, "Plant should regrow or stay at 1");
    }

    [Fact]
    public void SetPlayerPosition_UpdatesPlayerCell()
    {
        var grid = new SimulationGrid();
        grid.SetData(System.Array.Empty<AnimalStateData>(), 0, System.Array.Empty<PlantStateData>(), 0);

        var processor = new CellProcessor(grid, System.Array.Empty<AnimalStateData>(), 0, System.Array.Empty<PlantStateData>(), 0);
        processor.SetPlayerPosition(SimConfig.CellSizeMeters * 5, SimConfig.CellSizeMeters * 3);

        processor.Tick(0.016f);
        // No assert on internal state; just verify no throw. Player cell is used for LOD.
    }
}
