namespace BiologyGame.Simulation;

/// <summary>
/// Defines behavior and visuals for an animal species. Herbivore vs predator
/// is driven by IsPredator; all other fields tune the shared AnimalLogic.
/// </summary>
public struct AnimalSpeciesConfig
{
    /// <summary>Unique species ID. Must match index in species config array.</summary>
    public int Id;

    /// <summary>True = predator, false = herbivore. Affects hunting/foraging behavior.</summary>
    public bool IsPredator;

    /// <summary>Wander movement speed (m/s).</summary>
    public float WanderSpeed;

    /// <summary>Panic flee speed (m/s).</summary>
    public float PanicSpeed;

    /// <summary>0–1. Affects contagion and cohesion strength.</summary>
    public float SocialFactor;

    /// <summary>Radius for cohesion toward same-species center (m).</summary>
    public float CohesionRadius;

    /// <summary>Radius for contagion / panic spread (m).</summary>
    public float ContagionRadius;

    /// <summary>Default panic duration when triggered (s).</summary>
    public float PanicDuration;

    /// <summary>Min seconds to pause at wander target.</summary>
    public float WanderPauseMin;

    /// <summary>Max seconds to pause at wander target.</summary>
    public float WanderPauseMax;

    /// <summary>Max random offset from current position for wander target (m).</summary>
    public float WanderRadius;

    /// <summary>Path to Godot scene for instantiation when promoted (e.g. res://scenes/animals/herbivore.tscn).</summary>
    public string ScenePath;

    /// <summary>Base herbivore preset (e.g. deer-like).</summary>
    public static AnimalSpeciesConfig CreateHerbivore(int id = 0, string scenePath = "")
    {
        return new AnimalSpeciesConfig
        {
            Id = id,
            IsPredator = false,
            WanderSpeed = 1.2f,
            PanicSpeed = 6.0f,
            SocialFactor = 0.7f,
            CohesionRadius = 14.0f,
            ContagionRadius = 12.0f,
            PanicDuration = 3.0f,
            WanderPauseMin = 1.0f,
            WanderPauseMax = 4.0f,
            WanderRadius = 10.0f,
            ScenePath = scenePath
        };
    }

    /// <summary>Base predator preset (e.g. wolf-like).</summary>
    public static AnimalSpeciesConfig CreatePredator(int id = 1, string scenePath = "")
    {
        return new AnimalSpeciesConfig
        {
            Id = id,
            IsPredator = true,
            WanderSpeed = 1.8f,
            PanicSpeed = 7.0f,
            SocialFactor = 0.6f,
            CohesionRadius = 12.0f,
            ContagionRadius = 10.0f,
            PanicDuration = 2.5f,
            WanderPauseMin = 0.5f,
            WanderPauseMax = 3.0f,
            WanderRadius = 15.0f,
            ScenePath = scenePath
        };
    }
}
