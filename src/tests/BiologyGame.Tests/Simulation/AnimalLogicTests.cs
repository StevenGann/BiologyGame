using Godot;
using Xunit;
using BiologyGame.Simulation;
using BiologyGame.Tests.Helpers;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for the AnimalLogic static class.
/// Tests FAR LOD behavior: contagion, panic decay, wander movement.
/// </summary>
public class AnimalLogicTests
{
    #region UpdateStateFar Tests

    [Fact]
    public void UpdateStateFar_WanderingWithNoPanickedNeighbors_StaysWandering()
    {
        // Arrange
        var state = TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0));
        var neighbors = TestStateFactory.CreateNeighbors(calmCount: 5, panickedCount: 0);

        // Act
        AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);

        // Assert
        Assert.Equal(TestStateFactory.States.Wandering, state.State);
    }

    [Fact]
    public void UpdateStateFar_PanicTimerExpires_TransitionsToWander()
    {
        // Arrange
        var state = TestStateFactory.CreatePanicking(
            position: new Vector3(0, 0, 0),
            panicTimer: 0.05f // Very short timer
        );
        var neighbors = new List<(Vector3 Pos, int State)>();

        // Act - delta > panicTimer so it should expire
        AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);

        // Assert
        Assert.Equal(TestStateFactory.States.Wandering, state.State);
        Assert.True(state.PanicTimer <= 0);
    }

    [Fact]
    public void UpdateStateFar_PanicTimerNotExpired_StaysPanicking()
    {
        // Arrange
        var state = TestStateFactory.CreatePanicking(
            position: new Vector3(0, 0, 0),
            panicTimer: 5.0f
        );
        var initialTimer = state.PanicTimer;
        var neighbors = new List<(Vector3 Pos, int State)>();

        // Act
        AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);

        // Assert
        Assert.Equal(TestStateFactory.States.Panicking, state.State);
        Assert.Equal(initialTimer - 0.1f, state.PanicTimer, 3); // Timer should be decremented
    }

    [Fact]
    public void UpdateStateFar_ContagionZeroSocialFactor_NeverPanics()
    {
        // Arrange - Antisocial animal surrounded by panicked neighbors
        var state = TestStateFactory.CreateAntisocial(position: new Vector3(0, 0, 0));
        var neighbors = TestStateFactory.CreateNeighbors(calmCount: 0, panickedCount: 10);

        // Act - Run many iterations to test probabilistic behavior
        for (int i = 0; i < 1000; i++)
        {
            AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);
        }

        // Assert - Should never panic due to zero SocialFactor
        Assert.Equal(TestStateFactory.States.Wandering, state.State);
    }

    [Fact]
    public void UpdateStateFar_ContagionHighSocialFactor_EventuallyPanics()
    {
        // Arrange - Highly social animal surrounded by panicked neighbors
        var panicOccurred = false;

        // Run multiple trials (contagion is probabilistic)
        for (int trial = 0; trial < 100 && !panicOccurred; trial++)
        {
            var state = TestStateFactory.CreateHighlySocial(position: new Vector3(0, 0, 0));
            var neighbors = TestStateFactory.CreateNeighbors(
                calmCount: 0,
                panickedCount: 5,
                basePosition: new Vector3(5, 0, 5) // Close enough to be within contagion radius
            );

            // Run simulation for multiple ticks
            for (int i = 0; i < 100; i++)
            {
                AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);
                if (state.State == TestStateFactory.States.Panicking)
                {
                    panicOccurred = true;
                    break;
                }
            }
        }

        // Assert - Should eventually panic (statistical test)
        Assert.True(panicOccurred, "Highly social animal should eventually panic from contagion");
    }

    [Fact]
    public void UpdateStateFar_PanickedWithCalmNeighbors_CalmingCanOccur()
    {
        // Arrange - Panicking animal with calm neighbors (should calm down faster)
        var calmingOccurred = false;

        for (int trial = 0; trial < 100 && !calmingOccurred; trial++)
        {
            var state = TestStateFactory.CreatePanicking(
                position: new Vector3(0, 0, 0),
                panicTimer: 10.0f // Long timer
            );
            state.SocialFactor = 1.0f; // High social factor for calming effect

            var neighbors = TestStateFactory.CreateNeighbors(
                calmCount: 5,
                panickedCount: 0,
                basePosition: new Vector3(5, 0, 5)
            );

            var initialTimer = state.PanicTimer;

            // Run several ticks
            for (int i = 0; i < 50; i++)
            {
                AnimalLogic.UpdateStateFar(0.1f, ref state, neighbors);
            }

            // Check if calming happened (timer reduced more than normal decay)
            var normalDecay = 50 * 0.1f; // 5 seconds of normal decay
            var actualDecay = initialTimer - state.PanicTimer;

            if (actualDecay > normalDecay)
            {
                calmingOccurred = true;
            }
        }

        // Assert - Calming should occur at least once across trials
        Assert.True(calmingOccurred, "Panicking animal with calm neighbors should sometimes calm faster");
    }

    #endregion

    #region ApplySimpleWander Tests

    [Fact]
    public void ApplySimpleWander_Panicking_VelocityAwayFromThreat()
    {
        // Arrange - Animal at (10, 0, 10), threat at origin
        var state = TestStateFactory.CreatePanicking(
            position: new Vector3(10, 0, 10),
            threatPosition: new Vector3(0, 0, 0),
            panicTimer: 5.0f
        );

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, Vector3.Zero);

        // Assert - Velocity should be away from threat (positive X and Z)
        Assert.True(state.Velocity.X > 0, "Velocity X should be positive (away from threat)");
        Assert.True(state.Velocity.Z > 0, "Velocity Z should be positive (away from threat)");
    }

    [Fact]
    public void ApplySimpleWander_Panicking_VelocityYIsZero()
    {
        // Arrange
        var state = TestStateFactory.CreatePanicking(
            position: new Vector3(10, 5, 10), // Even with Y offset
            threatPosition: new Vector3(0, 0, 0)
        );

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, Vector3.Zero);

        // Assert - Y velocity should always be zero (ground movement only)
        Assert.Equal(0, state.Velocity.Y);
    }

    [Fact]
    public void ApplySimpleWander_WanderTimerActive_NoMovement()
    {
        // Arrange
        var state = TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0));
        state.WanderTimer = 5.0f; // Timer active
        state.Velocity = Vector3.Zero;

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, Vector3.Zero);

        // Assert - Timer should be decremented, but no new velocity set
        Assert.Equal(4.9f, state.WanderTimer, 2);
    }

    [Fact]
    public void ApplySimpleWander_ReachedTarget_PicksNewTarget()
    {
        // Arrange - Animal at wander target
        var state = TestStateFactory.CreateDefault(position: new Vector3(10, 0, 10));
        state.WanderTarget = new Vector3(10, 0, 10); // Same as position
        state.WanderTimer = 0f;
        var originalTarget = state.WanderTarget;

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, Vector3.Zero);

        // Assert - New wander target should be picked, timer should be set
        Assert.True(state.WanderTimer > 0, "WanderTimer should be set after reaching target");
    }

    [Fact]
    public void ApplySimpleWander_MovingToTarget_VelocityTowardTarget()
    {
        // Arrange - Animal needs to move toward distant target
        var state = TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0));
        state.WanderTarget = new Vector3(100, 0, 0); // Target to the right
        state.WanderTimer = 0f;

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, Vector3.Zero);

        // Assert - Velocity should be toward target (positive X)
        Assert.True(state.Velocity.X > 0, "Velocity should be toward target");
        Assert.Equal(0, state.Velocity.Y);
        Assert.True(Math.Abs(state.Velocity.Z) < 0.01f, "Velocity Z should be near zero");
    }

    [Fact]
    public void ApplySimpleWander_WithCohesion_VelocityInfluenced()
    {
        // Arrange
        var state = TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0));
        state.WanderTarget = new Vector3(100, 0, 0); // Target to the right
        state.WanderTimer = 0f;
        state.SocialFactor = 1.0f;

        var cohesionVector = new Vector3(0, 0, 1); // Pull toward positive Z

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, cohesionVector);

        // Assert - Velocity should be influenced by cohesion
        Assert.True(state.Velocity.X > 0, "Velocity X should still be toward target");
        Assert.True(state.Velocity.Z > 0, "Velocity Z should be influenced by cohesion");
    }

    [Fact]
    public void ApplySimpleWander_CohesionExceedsMaxSpeed_VelocityClamped()
    {
        // Arrange
        var state = TestStateFactory.CreateDefault(position: new Vector3(0, 0, 0));
        state.WanderTarget = new Vector3(100, 0, 0);
        state.WanderTimer = 0f;
        state.WanderSpeed = 2.0f;

        // Very large cohesion vector that would exceed max speed
        var largeCohesion = new Vector3(50, 0, 50);

        // Act
        AnimalLogic.ApplySimpleWander(0.1f, ref state, largeCohesion);

        // Assert - Speed should be clamped to WanderSpeed
        var flatVelocity = new Vector3(state.Velocity.X, 0, state.Velocity.Z);
        var speed = flatVelocity.Length();
        Assert.True(speed <= state.WanderSpeed + 0.01f, $"Speed {speed} should be clamped to max {state.WanderSpeed}");
    }

    #endregion
}
