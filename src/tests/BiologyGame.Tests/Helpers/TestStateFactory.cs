using Godot;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Helpers;

/// <summary>
/// Factory methods for creating AnimalStateData instances with sensible defaults for testing.
/// </summary>
public static class TestStateFactory
{
    /// <summary>Species IDs matching the game's enum values.</summary>
    public static class Species
    {
        public const int Bison = 0;
        public const int Deer = 1;
        public const int Rabbit = 2;
        public const int Wolf = 3;
        public const int Bear = 4;
    }

    /// <summary>State IDs matching the game's state machine.</summary>
    public static class States
    {
        public const int Wandering = 0;
        public const int Panicking = 1;
    }

    /// <summary>
    /// Creates an AnimalStateData with sensible defaults for a wandering herbivore.
    /// </summary>
    public static AnimalStateData CreateDefault(
        Vector3? position = null,
        int species = 0,
        int state = 0)
    {
        return new AnimalStateData
        {
            Position = position ?? Vector3.Zero,
            Velocity = Vector3.Zero,
            State = state,
            Species = species,
            Health = 100,
            PanicTimer = 0f,
            WanderTimer = 0f,
            WanderTarget = position ?? Vector3.Zero,
            ThreatPosition = Vector3.Zero,
            WanderSpeed = 2.0f,
            PanicSpeed = 8.0f,
            SocialFactor = 0.5f,
            CohesionRadius = 20.0f,
            ContagionRadius = 30.0f,
            PanicDuration = 5.0f,
            WanderPauseMin = 1.0f,
            WanderPauseMax = 3.0f,
            WanderRadius = 15.0f,
        };
    }

    /// <summary>
    /// Creates an AnimalStateData for a panicking animal.
    /// </summary>
    public static AnimalStateData CreatePanicking(
        Vector3? position = null,
        Vector3? threatPosition = null,
        float panicTimer = 5.0f,
        int species = 0)
    {
        var state = CreateDefault(position, species, States.Panicking);
        state.PanicTimer = panicTimer;
        state.ThreatPosition = threatPosition ?? new Vector3(100, 0, 100);
        return state;
    }

    /// <summary>
    /// Creates an AnimalStateData with zero social factor (won't be affected by contagion).
    /// </summary>
    public static AnimalStateData CreateAntisocial(Vector3? position = null, int species = 0)
    {
        var state = CreateDefault(position, species);
        state.SocialFactor = 0f;
        return state;
    }

    /// <summary>
    /// Creates an AnimalStateData with maximum social factor (highly susceptible to contagion).
    /// </summary>
    public static AnimalStateData CreateHighlySocial(Vector3? position = null, int species = 0)
    {
        var state = CreateDefault(position, species);
        state.SocialFactor = 1.0f;
        return state;
    }

    /// <summary>
    /// Creates a list of neighbor data for testing contagion logic.
    /// </summary>
    public static List<(Vector3 Pos, int State)> CreateNeighbors(
        int calmCount = 0,
        int panickedCount = 0,
        Vector3? basePosition = null)
    {
        var neighbors = new List<(Vector3 Pos, int State)>();
        var basePos = basePosition ?? Vector3.Zero;

        for (int i = 0; i < calmCount; i++)
        {
            neighbors.Add((basePos + new Vector3(i * 5, 0, 0), States.Wandering));
        }

        for (int i = 0; i < panickedCount; i++)
        {
            neighbors.Add((basePos + new Vector3(0, 0, i * 5), States.Panicking));
        }

        return neighbors;
    }
}
