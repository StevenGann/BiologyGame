using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for the FarSpatialGrid class.
/// Tests spatial partitioning and neighbor queries.
/// </summary>
public class FarSpatialGridTests
{
    [Fact]
    public void CellSize_Is24()
    {
        // Assert - Cell size should match SimulationManager.CELL_SIZE
        Assert.Equal(24.0f, FarSpatialGrid.CellSize);
    }

    [Fact]
    public void Rebuild_EmptyArray_NoExceptions()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = Array.Empty<AnimalStateData>();

        // Act & Assert - Should not throw
        var exception = Record.Exception(() => grid.Rebuild(animals, 0));
        Assert.Null(exception);
    }

    [Fact]
    public void Rebuild_SingleAnimal_NoExceptions()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0))
        };

        // Act & Assert - Should not throw
        var exception = Record.Exception(() => grid.Rebuild(animals, 1));
        Assert.Null(exception);
    }

    [Fact]
    public void GetSameSpeciesInRadius_ExactMatch_ReturnsNeighbor()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Deer),
            TestStateFactory.CreateDefault(position: new Vector3(10, 0, 0), species: TestStateFactory.Species.Deer),
        };
        grid.Rebuild(animals, 2);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(0, 0, 0),
            radius: 15.0f,
            species: TestStateFactory.Species.Deer,
            excludeId: 0,
            outIndices: results
        );

        // Assert - Should find the neighbor deer
        Assert.Single(results);
        Assert.Equal(1, results[0]);
    }

    [Fact]
    public void GetSameSpeciesInRadius_DifferentSpecies_NotReturned()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Deer),
            TestStateFactory.CreateDefault(position: new Vector3(5, 0, 0), species: TestStateFactory.Species.Wolf), // Different species, very close
        };
        grid.Rebuild(animals, 2);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(0, 0, 0),
            radius: 50.0f, // Large radius
            species: TestStateFactory.Species.Deer,
            excludeId: 0,
            outIndices: results
        );

        // Assert - Wolf should not be returned (different species)
        Assert.Empty(results);
    }

    [Fact]
    public void GetSameSpeciesInRadius_BeyondRadius_NotReturned()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Deer),
            TestStateFactory.CreateDefault(position: new Vector3(50, 0, 0), species: TestStateFactory.Species.Deer), // Same species, far away
        };
        grid.Rebuild(animals, 2);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(0, 0, 0),
            radius: 15.0f, // Radius doesn't reach the other deer
            species: TestStateFactory.Species.Deer,
            excludeId: 0,
            outIndices: results
        );

        // Assert - Other deer is beyond radius
        Assert.Empty(results);
    }

    [Fact]
    public void GetSameSpeciesInRadius_ExcludesSelf()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Deer),
        };
        grid.Rebuild(animals, 1);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(0, 0, 0),
            radius: 50.0f,
            species: TestStateFactory.Species.Deer,
            excludeId: 0, // Exclude self
            outIndices: results
        );

        // Assert - Should not include self
        Assert.Empty(results);
    }

    [Fact]
    public void GetSameSpeciesInRadius_AcrossCellBoundary_StillFound()
    {
        // Arrange - Animals in different cells (cell size is 24)
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(23, 0, 0), species: TestStateFactory.Species.Deer), // Cell (0, 0)
            TestStateFactory.CreateDefault(position: new Vector3(25, 0, 0), species: TestStateFactory.Species.Deer), // Cell (1, 0)
        };
        grid.Rebuild(animals, 2);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(23, 0, 0),
            radius: 5.0f, // Small radius, but should still find neighbor across cell boundary
            species: TestStateFactory.Species.Deer,
            excludeId: 0,
            outIndices: results
        );

        // Assert - Should find neighbor even though in different cell
        Assert.Single(results);
        Assert.Equal(1, results[0]);
    }

    [Fact]
    public void GetSameSpeciesInRadius_MultipleNeighbors_ReturnsAll()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Bison),
            TestStateFactory.CreateDefault(position: new Vector3(5, 0, 0), species: TestStateFactory.Species.Bison),
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 5), species: TestStateFactory.Species.Bison),
            TestStateFactory.CreateDefault(position: new Vector3(5, 0, 5), species: TestStateFactory.Species.Bison),
            TestStateFactory.CreateDefault(position: new Vector3(100, 0, 100), species: TestStateFactory.Species.Bison), // Far away
        };
        grid.Rebuild(animals, 5);

        // Act
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: new Vector3(0, 0, 0),
            radius: 20.0f,
            species: TestStateFactory.Species.Bison,
            excludeId: 0,
            outIndices: results
        );

        // Assert - Should find 3 nearby neighbors (excluding self and far away one)
        Assert.Equal(3, results.Count);
        Assert.Contains(1, results);
        Assert.Contains(2, results);
        Assert.Contains(3, results);
        Assert.DoesNotContain(4, results);
    }

    [Fact]
    public void GetSameSpeciesInRadius_LargeDataset_CorrectResults()
    {
        // Arrange - Create 1000 animals spread across the world
        var grid = new FarSpatialGrid();
        var animals = new AnimalStateData[1000];
        var rng = new Random(42); // Fixed seed for reproducibility

        for (int i = 0; i < 1000; i++)
        {
            var pos = new Vector3(
                (float)rng.NextDouble() * 1000 - 500,
                0,
                (float)rng.NextDouble() * 1000 - 500
            );
            animals[i] = TestStateFactory.CreateDefault(
                position: pos,
                species: i % 5 // Distribute across 5 species
            );
        }
        grid.Rebuild(animals, 1000);

        // Act - Query for species 0 (Bison) near origin
        var results = new List<int>();
        grid.GetSameSpeciesInRadius(
            center: Vector3.Zero,
            radius: 100.0f,
            species: TestStateFactory.Species.Bison,
            excludeId: -1, // Don't exclude anyone
            outIndices: results
        );

        // Assert - Verify correctness by brute force comparison
        var expected = new List<int>();
        for (int i = 0; i < 1000; i++)
        {
            if (animals[i].Species == TestStateFactory.Species.Bison &&
                Vector3.Zero.DistanceTo(animals[i].Position) <= 100.0f)
            {
                expected.Add(i);
            }
        }

        Assert.Equal(expected.Count, results.Count);
        foreach (var idx in expected)
        {
            Assert.Contains(idx, results);
        }
    }

    [Fact]
    public void GetSameSpeciesInRadius_ClearsOutputList()
    {
        // Arrange
        var grid = new FarSpatialGrid();
        var animals = new[]
        {
            TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0), species: TestStateFactory.Species.Deer),
        };
        grid.Rebuild(animals, 1);

        var results = new List<int> { 999, 998, 997 }; // Pre-populated list

        // Act
        grid.GetSameSpeciesInRadius(
            center: new Vector3(1000, 0, 1000), // Far from all animals
            radius: 5.0f,
            species: TestStateFactory.Species.Deer,
            excludeId: -1,
            outIndices: results
        );

        // Assert - List should be cleared even if no results found
        Assert.Empty(results);
    }
}
