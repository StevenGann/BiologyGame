using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pure data struct for animal state. No Godot types in hot path; safe for worker thread.
/// Used by AnimalLogic, FarAnimalSim, and FarSimBridge for promote/demote round-trip.
/// </summary>
public struct AnimalStateData
{
    /// <summary>World position (X,Z used for movement; Y from HeightmapSampler on promote).</summary>
    public Vector3 Position;
    /// <summary>Horizontal velocity (Y ignored in FAR movement).</summary>
    public Vector3 Velocity;
    /// <summary>0 = Wandering, 1 = Panicking.</summary>
    public int State;
    /// <summary>Species ID (Bison=0, Deer=1, Rabbit=2, Wolf=3, Bear=4).</summary>
    public int Species;
    /// <summary>Current health. Restored on promote.</summary>
    public int Health;
    /// <summary>Seconds until panic ends.</summary>
    public float PanicTimer;
    /// <summary>Seconds until next wander target.</summary>
    public float WanderTimer;
    /// <summary>Target position for wandering.</summary>
    public Vector3 WanderTarget;
    /// <summary>Threat position when panicking.</summary>
    public Vector3 ThreatPosition;

    /// <summary>Wander movement speed.</summary>
    public float WanderSpeed;
    /// <summary>Panic flee speed.</summary>
    public float PanicSpeed;
    /// <summary>0–1. Affects contagion and cohesion.</summary>
    public float SocialFactor;
    /// <summary>Radius for cohesion toward same-species center.</summary>
    public float CohesionRadius;
    /// <summary>Radius for contagion (panic spread).</summary>
    public float ContagionRadius;
    /// <summary>Default panic duration when triggered.</summary>
    public float PanicDuration;
    /// <summary>Min seconds to pause at wander target.</summary>
    public float WanderPauseMin;
    /// <summary>Max seconds to pause at wander target.</summary>
    public float WanderPauseMax;
    /// <summary>Max random offset from current position for wander target.</summary>
    public float WanderRadius;
}
