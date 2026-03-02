using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pure data struct for animal state. Used by AnimalLogic (no Godot dependencies in hot path)
/// and for promote/demote round-trip between scene and async sim.
/// </summary>
public struct AnimalStateData
{
    public Vector3 Position;
    public Vector3 Velocity;
    public int State; // 0=Wander, 1=Panic
    public int Species;
    public int Health;
    public float PanicTimer;
    public float WanderTimer;
    public Vector3 WanderTarget;
    public Vector3 ThreatPosition;

    // Static params (per-animal type)
    public float WanderSpeed;
    public float PanicSpeed;
    public float SocialFactor;
    public float CohesionRadius;
    public float ContagionRadius;
    public float PanicDuration;
    public float WanderPauseMin;
    public float WanderPauseMax;
    public float WanderRadius;
}
