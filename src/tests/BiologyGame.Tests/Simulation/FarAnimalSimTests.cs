using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Integration tests for the FarAnimalSim class.
/// Tests thread-safe queue behavior, demote/promote lifecycle, and worker thread operations.
/// </summary>
public class FarAnimalSimTests : IDisposable
{
    private FarAnimalSim? _sim;

    public void Dispose()
    {
        _sim?.Stop();
        _sim = null;
    }

    private FarAnimalSim CreateSim(float promoteRadius = 85.0f)
    {
        // HeightmapSampler can be null (line 169 null-checks it)
        _sim = new FarAnimalSim(null!, promoteRadius);
        return _sim;
    }

    [Fact]
    public void Constructor_InitializesWithZeroCount()
    {
        // Arrange & Act
        var sim = CreateSim();

        // Assert
        Assert.Equal(0, sim.Count);
    }

    [Fact]
    public void Demote_SingleAnimal_CountIncrementsAfterTick()
    {
        // Arrange
        var sim = CreateSim();
        var animal = TestStateFactory.CreateDefault(
            position: new Vector3(1000, 0, 1000), // Far from player
            species: TestStateFactory.Species.Deer
        );

        // Act
        sim.Start();
        sim.Demote(animal);
        sim.PushInput(Vector3.Zero, 0.1f); // Player at origin

        // Wait for worker thread to process
        Thread.Sleep(200);

        // Assert
        Assert.Equal(1, sim.Count);

        // Cleanup
        sim.Stop();
    }

    [Fact]
    public void DemoteAndPromote_AnimalNearPlayer_GetsPromoted()
    {
        // Arrange
        var sim = CreateSim(promoteRadius: 100.0f); // Promote radius of 100
        var animal = TestStateFactory.CreateDefault(
            position: new Vector3(50, 0, 50), // Within promote radius of origin
            species: TestStateFactory.Species.Deer
        );

        // Act
        sim.Start();
        sim.Demote(animal);
        sim.PushInput(Vector3.Zero, 0.1f); // Player at origin

        // Wait for worker to process demote and then tick (which checks promotion)
        Thread.Sleep(300);

        // Assert - Should have been promoted
        var promoted = sim.TryGetPromote(out var index, out var state);
        Assert.True(promoted, "Animal near player should be promoted");
        Assert.Equal(TestStateFactory.Species.Deer, state.Species);
    }

    [Fact]
    public void DemoteAndPromote_AnimalFarFromPlayer_NotPromoted()
    {
        // Arrange
        var sim = CreateSim(promoteRadius: 85.0f);
        var animal = TestStateFactory.CreateDefault(
            position: new Vector3(1000, 0, 1000), // Very far from player
            species: TestStateFactory.Species.Deer
        );

        // Act
        sim.Start();
        sim.Demote(animal);
        sim.PushInput(Vector3.Zero, 0.1f); // Player at origin

        // Wait for processing
        Thread.Sleep(200);

        // Assert - Should NOT be promoted (too far)
        var promoted = sim.TryGetPromote(out _, out _);
        Assert.False(promoted, "Animal far from player should not be promoted");
        Assert.Equal(1, sim.Count); // Still in simulation
    }

    [Fact]
    public void GetSnapshot_AfterDemote_ContainsAnimalData()
    {
        // Arrange
        var sim = CreateSim();
        var animal = TestStateFactory.CreateDefault(
            position: new Vector3(100, 0, 200),
            species: TestStateFactory.Species.Wolf
        );

        // Act
        sim.Start();
        sim.Demote(animal);
        sim.PushInput(new Vector3(1000, 0, 1000), 0.1f); // Player far away

        // Wait for processing
        Thread.Sleep(200);

        var (data, count) = sim.GetSnapshot();

        // Assert
        Assert.Equal(1, count);
        Assert.True(data.Length >= 3, "Snapshot should contain position and species data");

        // Snapshot format: [x0, z0, species0, ...]
        Assert.Equal(TestStateFactory.Species.Wolf, (int)data[2]);
    }

    [Fact]
    public void StartStop_NoDeadlock()
    {
        // Arrange
        var sim = CreateSim();

        // Act & Assert - Should complete without hanging
        var task = Task.Run(() =>
        {
            sim.Start();
            Thread.Sleep(100);
            sim.Stop();
        });

        var completed = task.Wait(TimeSpan.FromSeconds(5));
        Assert.True(completed, "Start/Stop should complete without deadlock");
    }

    [Fact]
    public void ConcurrentDemotes_AllProcessed()
    {
        // Arrange
        var sim = CreateSim();
        const int animalCount = 100;

        // Act - Demote animals from multiple threads
        sim.Start();

        var tasks = new Task[10];
        for (int t = 0; t < 10; t++)
        {
            var threadId = t;
            tasks[t] = Task.Run(() =>
            {
                for (int i = 0; i < 10; i++)
                {
                    var animal = TestStateFactory.CreateDefault(
                        position: new Vector3(1000 + threadId * 100 + i, 0, 1000),
                        species: i % 5
                    );
                    sim.Demote(animal);
                }
            });
        }

        Task.WaitAll(tasks);
        sim.PushInput(Vector3.Zero, 0.1f);

        // Wait for worker to process all demotes
        Thread.Sleep(500);

        // Assert
        Assert.Equal(animalCount, sim.Count);
    }

    [Fact]
    public void TryGetPromote_WhenEmpty_ReturnsFalse()
    {
        // Arrange
        var sim = CreateSim();

        // Act
        var result = sim.TryGetPromote(out var index, out var state);

        // Assert
        Assert.False(result);
        Assert.Equal(-1, index);
    }

    [Fact]
    public void MultiplePromotes_AllRetrievable()
    {
        // Arrange
        var sim = CreateSim(promoteRadius: 200.0f); // Large promote radius

        // Act - Demote multiple animals close to player
        sim.Start();
        for (int i = 0; i < 5; i++)
        {
            var animal = TestStateFactory.CreateDefault(
                position: new Vector3(10 + i * 5, 0, 10),
                species: i
            );
            sim.Demote(animal);
        }

        sim.PushInput(Vector3.Zero, 0.1f);

        // Wait for processing
        Thread.Sleep(300);

        // Assert - All should be promoted
        var promotedCount = 0;
        while (sim.TryGetPromote(out _, out _))
        {
            promotedCount++;
        }

        Assert.Equal(5, promotedCount);
    }

    [Fact]
    public void PushInput_UpdatesPlayerPosition()
    {
        // Arrange
        var sim = CreateSim(promoteRadius: 50.0f);

        // Demote animal at a specific position
        var animal = TestStateFactory.CreateDefault(
            position: new Vector3(100, 0, 100),
            species: TestStateFactory.Species.Rabbit
        );

        // Act
        sim.Start();
        sim.Demote(animal);

        // Push player far away first
        sim.PushInput(new Vector3(1000, 0, 1000), 0.1f);
        Thread.Sleep(200);

        // Animal should not be promoted (player far)
        Assert.False(sim.TryGetPromote(out _, out _), "Should not promote when player is far");

        // Now move player close to animal
        sim.PushInput(new Vector3(100, 0, 100), 0.1f);
        Thread.Sleep(200);

        // Assert - Animal should now be promoted
        var promoted = sim.TryGetPromote(out _, out var state);
        Assert.True(promoted, "Should promote when player moves close");
        Assert.Equal(TestStateFactory.Species.Rabbit, state.Species);
    }
}
