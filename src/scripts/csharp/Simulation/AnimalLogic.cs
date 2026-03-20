using System;
using System.Collections.Generic;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pure C# logic for animal behavior. No Godot APIs; safe for worker thread.
/// Shared by full and simplified LOD variants. Caller applies velocity to position.
/// </summary>
public static class AnimalLogic
{
    private static readonly Random _rng = new();

    /// <summary>
    /// Update state: contagion (panic spread), panic decay, wander target refresh.
    /// No threat detection (player/hunter); animals only react to neighboring panicked animals.
    /// </summary>
    /// <param name="delta">Time step.</param>
    /// <param name="state">Animal state (modified in place).</param>
    /// <param name="neighbors">Nearby same-species (position, state 0/1).</param>
    public static void UpdateStateFar(
        float delta,
        ref AnimalStateData state,
        IReadOnlyList<(Vector3 Pos, int State)> neighbors)
    {
        ApplyContagion(delta, ref state, neighbors);
        if (state.State == 1) // Panic
        {
            state.PanicTimer -= delta;
            if (state.PanicTimer <= 0)
            {
                state.State = 0; // Wander
                PickNewWanderTarget(ref state);
                state.WanderTimer = Lerp(state.WanderPauseMin, state.WanderPauseMax);
            }
        }
    }

    /// <summary>
    /// Apply simple wander or panic movement. Writes to state.Velocity. Caller applies velocity to position.
    /// </summary>
    /// <param name="delta">Time step.</param>
    /// <param name="state">Animal state (modified in place).</param>
    /// <param name="cohesionVector">Precomputed cohesion vector (zero if none).</param>
    public static void ApplySimpleWander(
        float delta,
        ref AnimalStateData state,
        Vector3 cohesionVector)
    {
        if (state.State == 1) // Panic
        {
            var away = (state.Position - state.ThreatPosition).Normalized();
            away.Y = 0;
            if (away.LengthSquared() > 0.01f)
            {
                state.Velocity = new Vector3(
                    away.X * state.PanicSpeed * 0.5f,
                    0,
                    away.Z * state.PanicSpeed * 0.5f);
                ApplyCohesionToVelocity(ref state, cohesionVector);
            }
            return;
        }
        if (state.WanderTimer > 0)
        {
            state.WanderTimer -= delta;
            return;
        }
        var toTarget = state.WanderTarget - state.Position;
        toTarget.Y = 0;
        if (toTarget.Length() < 1.0f)
        {
            PickNewWanderTarget(ref state);
            state.WanderTimer = Lerp(state.WanderPauseMin, state.WanderPauseMax);
            return;
        }
        var dir = toTarget.Normalized();
        state.Velocity = new Vector3(
            dir.X * state.WanderSpeed * 0.5f,
            0,
            dir.Z * state.WanderSpeed * 0.5f);
        ApplyCohesionToVelocity(ref state, cohesionVector);
    }

    private static void ApplyContagion(
        float delta,
        ref AnimalStateData state,
        IReadOnlyList<(Vector3 Pos, int State)> neighbors)
    {
        if (state.SocialFactor <= 0) return;
        var panickingCount = 0;
        var nearestPanickedDistSq = state.ContagionRadius * state.ContagionRadius;
        Vector3? nearestPanickedPos = null;
        foreach (var (pos, s) in neighbors)
        {
            if (s != 1) continue; // not panicking
            panickingCount++;
            var dSq = state.Position.DistanceSquaredTo(pos);
            if (dSq < nearestPanickedDistSq)
            {
                nearestPanickedDistSq = dSq;
                nearestPanickedPos = pos;
            }
        }
        if (state.State == 0 && panickingCount > 0 && nearestPanickedPos.HasValue)
        {
            var baseChance = 0.15f * delta;
            if ((float)_rng.NextDouble() < state.SocialFactor * baseChance * panickingCount)
            {
                state.State = 1;
                state.ThreatPosition = nearestPanickedPos.Value;
                state.PanicTimer = state.PanicDuration;
            }
        }
        else if (state.State == 1 && panickingCount == 0 && neighbors.Count > 0)
        {
            var calmChance = 0.2f * delta * state.SocialFactor;
            if ((float)_rng.NextDouble() < calmChance)
                state.PanicTimer -= state.PanicDuration * 0.2f;
        }
    }

    private static void ApplyCohesionToVelocity(ref AnimalStateData state, Vector3 cohesion)
    {
        if (cohesion.LengthSquared() < 0.0001f) return;
        var v = state.Velocity;
        v.X += cohesion.X;
        v.Z += cohesion.Z;
        var flat = new Vector3(v.X, 0, v.Z);
        var speed = flat.Length();
        var maxSpeed = state.State == 1 ? state.PanicSpeed : state.WanderSpeed;
        if (speed > maxSpeed)
        {
            flat = flat.Normalized() * maxSpeed;
            v.X = flat.X;
            v.Z = flat.Z;
        }
        state.Velocity = v;
    }

    private static void PickNewWanderTarget(ref AnimalStateData state)
    {
        var r = state.WanderRadius;
        var offset = new Vector3(Lerp(-r, r), 0, Lerp(-r, r));
        state.WanderTarget = state.Position + offset;
    }

    private static float Lerp(float a, float b) =>
        a + (float)_rng.NextDouble() * (b - a);
}
