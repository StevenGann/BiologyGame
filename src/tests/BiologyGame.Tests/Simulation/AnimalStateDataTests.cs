using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for AnimalStateData struct.
/// </summary>
public class AnimalStateDataTests
{
    [Fact]
    public void DefaultState_IsWandering()
    {
        var state = new AnimalStateData();
        Assert.Equal(0, state.State);
    }

    [Fact]
    public void StructCopy_IsIndependent()
    {
        var original = TestStateFactory.CreateDefault(
            position: new Vector3(10, 0, 10),
            speciesId: 0);
        original.Health = 100;
        original.State = TestStateFactory.States.Wandering;

        var copy = original;
        copy.Position = new Vector3(50, 0, 50);
        copy.Health = 50;
        copy.State = TestStateFactory.States.Panicking;
        copy.SpeciesId = 1;
        copy.CellX = 5;
        copy.CellZ = 5;

        Assert.Equal(new Vector3(10, 0, 10), original.Position);
        Assert.Equal(100, original.Health);
        Assert.Equal(TestStateFactory.States.Wandering, original.State);
        Assert.Equal(0, original.SpeciesId);
        Assert.Equal(0, original.CellX);
        Assert.Equal(0, original.CellZ);

        Assert.Equal(new Vector3(50, 0, 50), copy.Position);
        Assert.Equal(50, copy.Health);
        Assert.Equal(TestStateFactory.States.Panicking, copy.State);
        Assert.Equal(1, copy.SpeciesId);
        Assert.Equal(5, copy.CellX);
        Assert.Equal(5, copy.CellZ);
    }

    [Fact]
    public void AllFieldsCanBeSet()
    {
        var state = new AnimalStateData
        {
            Position = new Vector3(1, 2, 3),
            Velocity = new Vector3(4, 5, 6),
            State = 1,
            SpeciesId = 2,
            Health = 75,
            CellX = 3,
            CellZ = 4,
            PanicTimer = 3.5f,
            WanderTimer = 2.0f,
            WanderTarget = new Vector3(10, 0, 10),
            ThreatPosition = new Vector3(20, 0, 20),
            WanderSpeed = 3.0f,
            PanicSpeed = 10.0f,
            SocialFactor = 0.8f,
            CohesionRadius = 25.0f,
            ContagionRadius = 35.0f,
            PanicDuration = 6.0f,
            WanderPauseMin = 0.5f,
            WanderPauseMax = 4.0f,
            WanderRadius = 20.0f,
        };

        Assert.Equal(new Vector3(1, 2, 3), state.Position);
        Assert.Equal(new Vector3(4, 5, 6), state.Velocity);
        Assert.Equal(1, state.State);
        Assert.Equal(2, state.SpeciesId);
        Assert.Equal(75, state.Health);
        Assert.Equal(3, state.CellX);
        Assert.Equal(4, state.CellZ);
        Assert.Equal(3.5f, state.PanicTimer);
        Assert.Equal(2.0f, state.WanderTimer);
        Assert.Equal(new Vector3(10, 0, 10), state.WanderTarget);
        Assert.Equal(new Vector3(20, 0, 20), state.ThreatPosition);
        Assert.Equal(3.0f, state.WanderSpeed);
        Assert.Equal(10.0f, state.PanicSpeed);
        Assert.Equal(0.8f, state.SocialFactor);
        Assert.Equal(25.0f, state.CohesionRadius);
        Assert.Equal(35.0f, state.ContagionRadius);
        Assert.Equal(6.0f, state.PanicDuration);
        Assert.Equal(0.5f, state.WanderPauseMin);
        Assert.Equal(4.0f, state.WanderPauseMax);
        Assert.Equal(20.0f, state.WanderRadius);
    }
}
