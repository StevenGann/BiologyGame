using Godot;

namespace BiologyGame.Animals;

/// <summary>
/// Forager: wanders, eats plants, panics and flees when spotting a hunter.
/// Mirrors forager_animal.gd.
/// </summary>
public partial class ForagerAnimal : AnimalBase
{
    [Export] public float PlantDetectionRange { get; set; } = 5.0f;
    [Export] public float HunterDetectionRange { get; set; } = 12.0f;
    [Export] public float HunterSafeDistance { get; set; } = 20.0f;
    [Export] public float EatingDuration { get; set; } = 2.0f;

    private enum ForagerState
    {
        Wandering,
        Eating,
        Panicking
    }

    private ForagerState _foragerState = ForagerState.Wandering;
    private Node3D _currentPlant;
    private float _eatingTimer;
    private bool _panickingFromHunter;

    public override void _Ready()
    {
        base._Ready();
        AddToGroup("foragers");
    }

    protected override void UpdateState(float delta)
    {
        UpdateThreats(delta);

        if (_state == State.Panicking)
        {
            if (_panickingFromHunter)
            {
                var hunter = GetNearestHunter();
                if (hunter == null || GlobalPosition.DistanceTo(hunter.GlobalPosition) >= HunterSafeDistance)
                {
                    _state = State.Wandering;
                    _foragerState = ForagerState.Wandering;
                    _panickingFromHunter = false;
                    PickNewWanderTarget();
                    _wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
                }
            }
            else
            {
                _panicTimer -= delta;
                if (_panicTimer <= 0)
                {
                    _state = State.Wandering;
                    _foragerState = ForagerState.Wandering;
                    PickNewWanderTarget();
                    _wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
                }
            }
        }

        ApplyContagion(delta);

        if (_foragerState == ForagerState.Wandering)
        {
            var hunter = GetNearestHunter();
            if (hunter == null)
            {
                var plant = GetNearestPlant();
                if (plant != null)
                {
                    _currentPlant = plant;
                    _foragerState = ForagerState.Eating;
                    _eatingTimer = EatingDuration;
                }
            }
        }
        else if (_foragerState == ForagerState.Eating)
        {
            if (GetNearestHunter() != null) { /* stay in eating, will be overridden by threat */ }
            else if (_currentPlant == null || !GodotObject.IsInstanceValid(_currentPlant))
            {
                _foragerState = ForagerState.Wandering;
                _currentPlant = null;
            }
            else
            {
                _eatingTimer -= delta;
                if (_eatingTimer <= 0)
                {
                    if (_currentPlant.HasMethod("consume") && _currentPlant.Call("consume").AsBool())
                        _eatingTimer = EatingDuration;
                    else
                    {
                        _foragerState = ForagerState.Wandering;
                        _currentPlant = null;
                    }
                }
            }
        }
    }

    protected override void UpdateThreats(float delta)
    {
        base.UpdateThreats(delta);
        var hunter = GetNearestHunter();
        if (hunter != null)
        {
            base.PanicFromPosition(hunter.GlobalPosition);
            _panickingFromHunter = true;
            _foragerState = ForagerState.Panicking;
        }
    }

    protected override void ApplyMovement(float delta)
    {
        if (_state == State.Panicking)
        {
            var away = (GlobalPosition - _threatPosition).Normalized();
            away.Y = 0;
            if (away.LengthSquared() > 0.01f)
            {
                var vel = Velocity;
                vel.X = away.X * PanicSpeed;
                vel.Z = away.Z * PanicSpeed;
                var cohesion = GetSocialCohesionVector();
                ApplyCohesionToVelocity(ref vel, cohesion);
                Velocity = vel;
                LookAt(GlobalPosition + new Vector3(vel.X, 0, vel.Z), Vector3.Up);
            }
        }
        else if (_foragerState == ForagerState.Eating)
        {
            var vel = Velocity;
            vel.X = Mathf.MoveToward(vel.X, 0, WanderSpeed * 2);
            vel.Z = Mathf.MoveToward(vel.Z, 0, WanderSpeed * 2);
            Velocity = vel;
        }
        else
        {
            base.ApplyMovement(delta);
        }
    }

    protected override string GetDebugStateString()
    {
        return _foragerState switch
        {
            ForagerState.Wandering => "Wander",
            ForagerState.Eating => "Eat",
            ForagerState.Panicking => "Panic",
            _ => "?"
        };
    }

    protected override void UpdateDebugVisuals(Node sim)
    {
        base.UpdateDebugVisuals(sim);
        if (_debugMeshInstance == null || sim == null || !sim.Get("debug_mode").AsBool()) return;
        var imesh = _debugMeshInstance.Mesh as ImmediateMesh;
        if (imesh == null) return;
        if (sim.Get("debug_show_forager_plant_line").AsBool() && _currentPlant != null && GodotObject.IsInstanceValid(_currentPlant))
        {
            var mat = MakeDebugMaterial(new Color(1.0f, 0.6f, 0.0f));
            imesh.SurfaceBegin(Mesh.PrimitiveType.Lines, mat);
            imesh.SurfaceAddVertex(Vector3.Zero);
            imesh.SurfaceAddVertex(ToLocal(_currentPlant.GlobalPosition));
            imesh.SurfaceEnd();
        }
        if (sim.Get("debug_show_detection_radii").AsBool())
        {
            var plantMat = MakeDebugMaterial(new Color(0.4f, 0.8f, 0.2f));
            imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, plantMat);
            for (var i = 0; i < 25; i++)
            {
                var a = Mathf.Tau * (float)i / 24.0f;
                imesh.SurfaceAddVertex(new Vector3(Mathf.Cos(a) * PlantDetectionRange, 0, Mathf.Sin(a) * PlantDetectionRange));
            }
            imesh.SurfaceEnd();
            var hunterMat = MakeDebugMaterial(new Color(0.8f, 0.2f, 0.2f));
            imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, hunterMat);
            for (var i = 0; i < 25; i++)
            {
                var a = Mathf.Tau * (float)i / 24.0f;
                imesh.SurfaceAddVertex(new Vector3(Mathf.Cos(a) * HunterDetectionRange, 0, Mathf.Sin(a) * HunterDetectionRange));
            }
            imesh.SurfaceEnd();
        }
        _debugMeshInstance.Mesh = imesh;
    }

    private Node3D GetNearestHunter()
    {
        Node3D nearest = null;
        var bestDistSq = HunterDetectionRange * HunterDetectionRange;
        var sim = GetSimManager();
        if (sim != null && sim.HasMethod("get_hunters_in_radius"))
        {
            var huntersList = sim.Call("get_hunters_in_radius", GlobalPosition, HunterDetectionRange).AsGodotArray();
            foreach (Variant v in huntersList)
            {
                var h = v.AsGodotObject() as Node3D;
                if (h == null || h == this) continue;
                var dSq = GlobalPosition.DistanceSquaredTo(h.GlobalPosition);
                if (dSq < bestDistSq)
                {
                    bestDistSq = dSq;
                    nearest = h;
                }
            }
            return nearest;
        }
        var parent = GetParent();
        if (parent == null) return null;
        foreach (Node child in parent.GetChildren())
        {
            if (!child.IsInGroup("hunters") || child is not Node3D hn) continue;
            if (hn == this) continue;
            var dSq = GlobalPosition.DistanceSquaredTo(hn.GlobalPosition);
            if (dSq < bestDistSq)
            {
                bestDistSq = dSq;
                nearest = hn;
            }
        }
        return nearest;
    }

    private Node3D GetNearestPlant()
    {
        Node3D nearest = null;
        var bestDistSq = PlantDetectionRange * PlantDetectionRange;
        var sim = GetSimManager();
        if (sim != null && sim.HasMethod("get_plants_in_radius"))
        {
            var plantsList = sim.Call("get_plants_in_radius", GlobalPosition, PlantDetectionRange).AsGodotArray();
            foreach (Variant v in plantsList)
            {
                var pn = v.AsGodotObject() as Node3D;
                if (pn == null) continue;
                var dSq = GlobalPosition.DistanceSquaredTo(pn.GlobalPosition);
                if (dSq < bestDistSq)
                {
                    bestDistSq = dSq;
                    nearest = pn;
                }
            }
            return nearest;
        }
        var parent = GetParent()?.GetParent();
        var plantsNode = parent?.GetNodeOrNull<Node3D>("Plants");
        if (plantsNode == null) return null;
        foreach (Node child in plantsNode.GetChildren())
        {
            if (child is not Node3D pn) continue;
            if (!pn.HasMethod("is_consumed") || pn.Call("is_consumed").AsBool()) continue;
            var dSq = GlobalPosition.DistanceSquaredTo(pn.GlobalPosition);
            if (dSq < bestDistSq)
            {
                bestDistSq = dSq;
                nearest = pn;
            }
        }
        return nearest;
    }
}
