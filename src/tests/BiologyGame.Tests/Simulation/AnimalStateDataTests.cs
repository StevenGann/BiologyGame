using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for the AnimalStateData struct.
/// Tests struct behavior, default values, and value-type semantics.
/// </summary>
public class AnimalStateDataTests
{
    [Fact]
    public void DefaultState_IsWandering()
    {
        // Arrange & Act
        var state = new AnimalStateData();

        // Assert
        Assert.Equal(0, state.State); // 0 = Wandering
    }

    [Theory]
    [InlineData(0, "Bison")]
    [InlineData(1, "Deer")]
    [InlineData(2, "Rabbit")]
    [InlineData(3, "Wolf")]
    [InlineData(4, "Bear")]
    public void SpeciesIds_MatchExpectedValues(int expectedId, string speciesName)
    {
        // Arrange
        var state = TestStateFactory.CreateDefault(species: expectedId);

        // Assert
        Assert.Equal(expectedId, state.Species);
    }

    [Fact]
    public void StructCopy_IsIndependent()
    {
        // Arrange
        var original = TestStateFactory.CreateDefault(
            position: new Vector3(10, 0, 10),
            species: TestStateFactory.Species.Deer
        );
        original.Health = 100;
        original.State = TestStateFactory.States.Wandering;

        // Act - Create a copy and modify it
        var copy = original;
        copy.Position = new Vector3(50, 0, 50);
        copy.Health = 50;
        copy.State = TestStateFactory.States.Panicking;
        copy.Species = TestStateFactory.Species.Wolf;

        // Assert - Original should be unchanged (value-type semantics)
        Assert.Equal(new Vector3(10, 0, 10), original.Position);
        Assert.Equal(100, original.Health);
        Assert.Equal(TestStateFactory.States.Wandering, original.State);
        Assert.Equal(TestStateFactory.Species.Deer, original.Species);

        // And copy should have the new values
        Assert.Equal(new Vector3(50, 0, 50), copy.Position);
        Assert.Equal(50, copy.Health);
        Assert.Equal(TestStateFactory.States.Panicking, copy.State);
        Assert.Equal(TestStateFactory.Species.Wolf, copy.Species);
    }

    [Fact]
    public void AllFieldsCanBeSet()
    {
        // Arrange & Act
        var state = new AnimalStateData
        {
            Position = new Vector3(1, 2, 3),
            Velocity = new Vector3(4, 5, 6),
            State = 1,
            Species = 2,
            Health = 75,
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

        // Assert - All fields should have their assigned values
        Assert.Equal(new Vector3(1, 2, 3), state.Position);
        Assert.Equal(new Vector3(4, 5, 6), state.Velocity);
        Assert.Equal(1, state.State);
        Assert.Equal(2, state.Species);
        Assert.Equal(75, state.Health);
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
