using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for SimulationGrid.
/// </summary>
public class SimulationGridTests
{
    [Fact]
    public void CellFromWorld_AtOrigin_ReturnsZeroCell()
    {
        var (cx, cz) = SimulationGrid.CellFromWorld(SimConfig.WorldOriginX, SimConfig.WorldOriginZ);
        Assert.Equal(0, cx);
        Assert.Equal(0, cz);
    }

    [Theory]
    [InlineData(0, 0, 0, 0, 0)]
    [InlineData(1, 0, 0, 0, 1)]
    [InlineData(0, 1, 0, 0, 1)]
    [InlineData(5, 10, 5, 10, 0)]
    [InlineData(0, 0, 3, 4, 7)]
    public void ManhattanDistance_ComputesCorrectly(int cx1, int cz1, int cx2, int cz2, int expected)
    {
        var dist = SimulationGrid.ManhattanDistance(cx1, cz1, cx2, cz2);
        Assert.Equal(expected, dist);
    }

    [Fact]
    public void Rebuild_AssignsAnimalsToCells()
    {
        var ox = SimConfig.WorldOriginX;
        var oz = SimConfig.WorldOriginZ;
        var animals = new AnimalStateData[3];
        animals[0] = TestStateFactory.CreateDefault(position: new Vector3(ox, 0, oz));
        animals[1] = TestStateFactory.CreateDefault(position: new Vector3(ox + SimConfig.CellSizeMeters * 2, 0, oz));
        animals[2] = TestStateFactory.CreateDefault(position: new Vector3(ox, 0, oz + SimConfig.CellSizeMeters * 2));

        var grid = new SimulationGrid();
        grid.SetData(animals, 3, System.Array.Empty<PlantStateData>(), 0);
        grid.Rebuild();

        var (c0x, c0z) = SimulationGrid.CellFromWorld(ox, oz);
        var (c1x, c1z) = SimulationGrid.CellFromWorld(ox + SimConfig.CellSizeMeters * 2, oz);
        var (c2x, c2z) = SimulationGrid.CellFromWorld(ox, oz + SimConfig.CellSizeMeters * 2);
        Assert.Equal(c0x, animals[0].CellX);
        Assert.Equal(c0z, animals[0].CellZ);
        Assert.Equal(c1x, animals[1].CellX);
        Assert.Equal(c1z, animals[1].CellZ);
        Assert.Equal(c2x, animals[2].CellX);
        Assert.Equal(c2z, animals[2].CellZ);
    }

    [Fact]
    public void GetSameSpeciesInRadius_ExcludesSelf()
    {
        var ox = SimConfig.WorldOriginX;
        var oz = SimConfig.WorldOriginZ;
        var animals = new AnimalStateData[2];
        animals[0] = TestStateFactory.CreateDefault(position: new Vector3(ox, 0, oz), speciesId: 0);
        animals[1] = TestStateFactory.CreateDefault(position: new Vector3(ox + 5f, 0, oz), speciesId: 0);

        var grid = new SimulationGrid();
        grid.SetData(animals, 2, System.Array.Empty<PlantStateData>(), 0);
        grid.Rebuild();

        var results = new List<int>();
        grid.GetSameSpeciesInRadius(new Vector3(ox, 0, oz), 20f, 0, 0, results);

        Assert.Single(results);
        Assert.Equal(1, results[0]);
    }

    [Fact]
    public void GetLodTierForCell_AtPlayerCell_ReturnsZero()
    {
        var tier = SimulationGrid.GetLodTierForCell(0, 0, 0, 0);
        Assert.Equal(0, tier);
    }

    [Fact]
    public void GetLodTierForCell_FarFromPlayer_ReturnsHigherTier()
    {
        var tier = SimulationGrid.GetLodTierForCell(20, 20, 0, 0);
        Assert.True(tier >= 3);
    }

    [Fact]
    public void GetSnapshot_WithNoEntities_ReturnsEmpty()
    {
        var grid = new SimulationGrid();
        grid.SetData(System.Array.Empty<AnimalStateData>(), 0, System.Array.Empty<PlantStateData>(), 0);
        grid.Rebuild();

        var buf = new List<float>();
        grid.GetSnapshot(buf);
        Assert.Empty(buf);
    }

    [Fact]
    public void GetSnapshot_WithAnimals_ReturnsPackedData()
    {
        var animals = new AnimalStateData[1];
        animals[0] = TestStateFactory.CreateDefault(position: new Vector3(10, 0, 20), speciesId: 1);

        var grid = new SimulationGrid();
        grid.SetData(animals, 1, System.Array.Empty<PlantStateData>(), 0);
        grid.Rebuild();

        var buf = new List<float>();
        grid.GetSnapshot(buf);
        Assert.Equal(4, buf.Count);
        Assert.Equal(10f, buf[0]);
        Assert.Equal(20f, buf[1]);
        Assert.Equal(1f, buf[2]);
        Assert.Equal(1f, buf[3]);
    }
}
