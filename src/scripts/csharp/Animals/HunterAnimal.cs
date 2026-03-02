using Godot;

namespace BiologyGame.Animals;

/// <summary>
/// Hunter animal: wanders, stalks prey (foragers), chases when prey panics or is close,
/// and kills when within KillRange. Uses SimulationManager.get_animals_in_radius (excluding hunters).
/// </summary>
public partial class HunterAnimal : AnimalBase
{
    /// <summary>Speed while stalking prey.</summary>
    [Export] public float StalkSpeed { get; set; } = 1.0f;
    /// <summary>Speed while chasing prey.</summary>
    [Export] public float ChaseSpeed { get; set; } = 5.0f;
    /// <summary>Distance to prey that triggers chase (or prey panicking).</summary>
    [Export] public float ChaseTriggerRange { get; set; } = 3.0f;
    /// <summary>Distance at which kill is applied.</summary>
    [Export] public float KillRange { get; set; } = 1.5f;
    /// <summary>Damage dealt on kill (effectively lethal).</summary>
    [Export] public int KillDamage { get; set; } = 999;

    private enum HunterState
    {
        Wandering,
        Stalking,
        Chasing,
        Killing
    }

    private HunterState _hunterState = HunterState.Wandering;
    private CharacterBody3D _currentTarget;

    public override void _Ready()
    {
        base._Ready();
        AddToGroup("hunters");
    }

    protected override void UpdateState(float delta)
    {
        base.UpdateState(delta);

        if (_hunterState == HunterState.Wandering)
        {
            var prey = GetNearestPrey();
            if (prey != null)
            {
                _currentTarget = prey;
                _hunterState = HunterState.Stalking;
            }
        }
        else if (_hunterState == HunterState.Stalking)
        {
            if (_currentTarget == null || !GodotObject.IsInstanceValid(_currentTarget))
            {
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
            else if (!IsTargetInRange(DetectionRange))
            {
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
            else if ((_currentTarget as AnimalBase)?.IsPanicking == true ||
                     GlobalPosition.DistanceTo(_currentTarget.GlobalPosition) < ChaseTriggerRange)
            {
                _hunterState = HunterState.Chasing;
            }
        }
        else if (_hunterState == HunterState.Chasing)
        {
            if (_currentTarget == null || !GodotObject.IsInstanceValid(_currentTarget))
            {
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
            else if (!IsTargetInRange(DetectionRange * 1.5f))
            {
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
            else if (GlobalPosition.DistanceTo(_currentTarget.GlobalPosition) < KillRange)
            {
                _hunterState = HunterState.Killing;
            }
        }
        else if (_hunterState == HunterState.Killing)
        {
            if (_currentTarget == null || !GodotObject.IsInstanceValid(_currentTarget))
            {
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
            else
            {
                if (_currentTarget.HasMethod("take_damage"))
                    _currentTarget.Call("take_damage", KillDamage);
                ClearTarget();
                _hunterState = HunterState.Wandering;
            }
        }
    }

    protected override void ApplyMovement(float delta)
    {
        if (_hunterState == HunterState.Stalking && _currentTarget != null && GodotObject.IsInstanceValid(_currentTarget))
        {
            var toTarget = _currentTarget.GlobalPosition - GlobalPosition;
            toTarget.Y = 0;
            if (toTarget.LengthSquared() > 0.01f)
            {
                var dir = toTarget.Normalized();
                var vel = Velocity;
                vel.X = dir.X * StalkSpeed;
                vel.Z = dir.Z * StalkSpeed;
                var cohesion = GetSocialCohesionVector();
                ApplyCohesionToVelocity(ref vel, cohesion);
                Velocity = vel;
                LookAt(GlobalPosition + dir, Vector3.Up);
            }
            return;
        }
        if (_hunterState == HunterState.Chasing && _currentTarget != null && GodotObject.IsInstanceValid(_currentTarget))
        {
            var toTarget = _currentTarget.GlobalPosition - GlobalPosition;
            toTarget.Y = 0;
            if (toTarget.LengthSquared() > 0.01f)
            {
                var dir = toTarget.Normalized();
                var vel = Velocity;
                vel.X = dir.X * ChaseSpeed;
                vel.Z = dir.Z * ChaseSpeed;
                Velocity = vel;
                LookAt(GlobalPosition + dir, Vector3.Up);
            }
            return;
        }
        if (_hunterState == HunterState.Killing)
        {
            var vel = Velocity;
            vel.X = Mathf.MoveToward(vel.X, 0, ChaseSpeed * 2);
            vel.Z = Mathf.MoveToward(vel.Z, 0, ChaseSpeed * 2);
            Velocity = vel;
            return;
        }
        base.ApplyMovement(delta);
    }

    protected override string GetDebugStateString()
    {
        return _hunterState switch
        {
            HunterState.Wandering => "Wander",
            HunterState.Stalking => "Stalk",
            HunterState.Chasing => "Chase",
            HunterState.Killing => "Kill",
            _ => "?"
        };
    }

    protected override void UpdateDebugVisuals(Node sim, bool inClose)
    {
        base.UpdateDebugVisuals(sim, inClose);
        if (_debugMeshInstance == null || sim == null || !sim.Get("debug_mode").AsBool()) return;
        var imesh = _debugMeshInstance.Mesh as ImmediateMesh;
        if (imesh == null) return;
        if (sim.Get("debug_show_hunter_prey_line").AsBool() && _currentTarget != null && GodotObject.IsInstanceValid(_currentTarget))
        {
            var mat = MakeDebugMaterial(new Color(0.9f, 0.2f, 0.2f));
            var p = ToLocal(_currentTarget.GlobalPosition);
            var origin = new Vector3(0, DebugVisualYOffset, 0);
            var preyEnd = new Vector3(p.X, DebugVisualYOffset, p.Z);
            imesh.SurfaceBegin(Mesh.PrimitiveType.Lines, mat);
            imesh.SurfaceAddVertex(origin);
            imesh.SurfaceAddVertex(preyEnd);
            imesh.SurfaceEnd();
            if (inClose)
                PlaceDebugAnnotation("Prey", "Prey", (origin + preyEnd) * 0.5f);
        }
        if (sim.Get("debug_show_detection_radii").AsBool())
        {
            var origin = new Vector3(0, DebugVisualYOffset, 0);
            var chaseMat = MakeDebugMaterial(new Color(1.0f, 0.5f, 0.0f));
            imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, chaseMat);
            for (var i = 0; i < 25; i++)
            {
                var a = Mathf.Tau * (float)i / 24.0f;
                imesh.SurfaceAddVertex(origin + new Vector3(Mathf.Cos(a) * ChaseTriggerRange, 0, Mathf.Sin(a) * ChaseTriggerRange));
            }
            imesh.SurfaceEnd();
            if (inClose)
                PlaceDebugAnnotation("Chase", "Chase Range", origin + new Vector3(ChaseTriggerRange, 0, 0));
            var killMat = MakeDebugMaterial(new Color(1.0f, 0.0f, 0.0f));
            imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, killMat);
            for (var i = 0; i < 25; i++)
            {
                var a = Mathf.Tau * (float)i / 24.0f;
                imesh.SurfaceAddVertex(origin + new Vector3(Mathf.Cos(a) * KillRange, 0, Mathf.Sin(a) * KillRange));
            }
            imesh.SurfaceEnd();
            if (inClose)
                PlaceDebugAnnotation("Kill", "Kill Range", origin + new Vector3(KillRange, 0, 0));
        }
        _debugMeshInstance.Mesh = imesh;
    }

    private CharacterBody3D GetNearestPrey()
    {
        CharacterBody3D nearest = null;
        var bestDistSq = DetectionRange * DetectionRange;
        var sim = GetSimManager();
        if (sim != null && sim.HasMethod("get_animals_in_radius"))
        {
            var animalsList = sim.Call("get_animals_in_radius", GlobalPosition, DetectionRange, this).AsGodotArray();
            foreach (Variant v in animalsList)
            {
                var a = v.AsGodotObject() as CharacterBody3D;
                if (a == null || a == this) continue;
                if (a.IsInGroup("hunters")) continue; // Hunters don't target hunters
                var dSq = GlobalPosition.DistanceSquaredTo(a.GlobalPosition);
                if (dSq < bestDistSq)
                {
                    bestDistSq = dSq;
                    nearest = a;
                }
            }
            return nearest;
        }
        var parent = GetParent();
        if (parent == null) return null;
        foreach (Node child in parent.GetChildren())
        {
            if (child is not CharacterBody3D other || other == this) continue;
            if (child.IsInGroup("hunters")) continue;
            var dSq = GlobalPosition.DistanceSquaredTo(other.GlobalPosition);
            if (dSq < bestDistSq)
            {
                bestDistSq = dSq;
                nearest = other;
            }
        }
        return nearest;
    }

    private bool IsTargetInRange(float rng)
    {
        if (_currentTarget == null || !GodotObject.IsInstanceValid(_currentTarget)) return false;
        return GlobalPosition.DistanceTo(_currentTarget.GlobalPosition) <= rng;
    }

    private void ClearTarget() => _currentTarget = null;
}
