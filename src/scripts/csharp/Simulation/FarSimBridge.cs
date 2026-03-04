using Godot;
using BiologyGame.Animals;

namespace BiologyGame.Simulation;

/// <summary>
/// Bridges scene-tree animals and FarAnimalSim worker. Radii derived from SimulationManager.medium_sim_radius
/// +/- HysteresisMeters. DemoteRadius = medium + hysteresis; PromoteRadius = medium - hysteresis.
/// Runs on main thread; process priority -50 (after SimulationManager).
/// </summary>
public partial class FarSimBridge : Node
{
    /// <summary>Hysteresis (meters) around medium_sim_radius. Demote = medium + hysteresis; Promote = medium - hysteresis.</summary>
    [Export] public float HysteresisMeters { get; set; } = 10f;
    /// <summary>How often to drain promotion queue and instantiate animals (seconds).</summary>
    [Export] public float ReviewIntervalSeconds { get; set; } = 5f;

    private float _demoteRadiusSq;
    private float _promoteRadius;

    private Node3D _animalsNode;
    private Node _terrainNode;
    private FarAnimalSim _sim;
    private HeightmapSampler _heightmap;
    private PackedScene _foragerScene;
    private PackedScene _hunterScene;
    private float _reviewAccum;
    private const int HeightmapResolution = 128;

    public override void _Ready()
    {
        var world = GetParent();
        _animalsNode = world.GetNodeOrNull<Node3D>("Animals");
        _terrainNode = world.GetNodeOrNull("TestTerrain");
        if (_animalsNode == null)
        {
            GD.PrintErr("FarSimBridge: Animals node not found");
            return;
        }
        _heightmap = new HeightmapSampler();
        var terrainSize = 1000f;
        var heightMin = -2f;
        var heightMax = 8f;
        if (_terrainNode != null && _terrainNode.Get("terrain_size").VariantType == Variant.Type.Float)
            terrainSize = (float)_terrainNode.Get("terrain_size").AsDouble();
        if (_terrainNode != null && _terrainNode.Get("height_min").VariantType == Variant.Type.Float)
            heightMin = (float)_terrainNode.Get("height_min").AsDouble();
        if (_terrainNode != null && _terrainNode.Get("height_max").VariantType == Variant.Type.Float)
            heightMax = (float)_terrainNode.Get("height_max").AsDouble();
        _heightmap.Initialize(HeightmapResolution, terrainSize, heightMin, heightMax);
        if (_terrainNode != null)
            _heightmap.SampleFromTerrain(_terrainNode);

        var simManager = GetTree().GetFirstNodeInGroup("simulation_manager");
        var mediumRadius = 200f;
        if (simManager != null && simManager.Get("medium_sim_radius").VariantType == Variant.Type.Float)
            mediumRadius = (float)simManager.Get("medium_sim_radius").AsDouble();

        _demoteRadiusSq = (mediumRadius + HysteresisMeters) * (mediumRadius + HysteresisMeters);
        _promoteRadius = mediumRadius - HysteresisMeters;

        _sim = new FarAnimalSim(_heightmap, _promoteRadius);
        _sim.Start();

        _foragerScene = GD.Load<PackedScene>("res://scenes/animals/forager_animal.tscn");
        _hunterScene = GD.Load<PackedScene>("res://scenes/animals/hunter_animal.tscn");

        SetProcessPriority(-50); // After SimulationManager
    }

    public override void _ExitTree()
    {
        _sim?.Stop();
    }

    public override void _PhysicsProcess(double delta)
    {
        var player = GetTree().GetFirstNodeInGroup("player") as Node3D;
        if (player == null) return;

        var playerPos = player.GlobalPosition;
        _sim.PushInput(playerPos, (float)delta);

        // Demotion: animals past demote radius
        var toRemove = new System.Collections.Generic.List<Node>();
        foreach (Node child in _animalsNode.GetChildren())
        {
            if (child is not CharacterBody3D body) continue;
            if (playerPos.DistanceSquaredTo(body.GlobalPosition) <= _demoteRadiusSq) continue;

            var state = ToStateData(body);
            if (state.Species >= 0)
            {
                _sim.Demote(state);
                toRemove.Add(child);
            }
        }
        foreach (var n in toRemove)
        {
            _animalsNode.RemoveChild(n);
            n.QueueFree();
        }

        // Promotion: periodic review (main thread)
        _reviewAccum += (float)delta;
        if (_reviewAccum >= ReviewIntervalSeconds)
        {
            _reviewAccum = 0;
            while (_sim.TryGetPromote(out _, out var state))
            {
                PromoteOne(state);
            }
        }
    }

    private void PromoteOne(AnimalStateData state)
    {
        if (_animalsNode == null) return;
        var scene = IsForager(state.Species) ? _foragerScene : _hunterScene;
        if (scene == null) return;

        var node = scene.Instantiate<Node3D>();
        if (node is not CharacterBody3D body) return;

        var height = _heightmap?.SampleHeight(state.Position.X, state.Position.Z) ?? 0;
        var pos = state.Position;
        pos.Y = height + 0.3f;

        _animalsNode.AddChild(node);
        body.GlobalPosition = pos;

        if (node is AnimalBase animal)
        {
            animal.ApplyStateData(state);
        }
        else
        {
            body.Set("species", state.Species);
        }
    }

    private static bool IsForager(int species)
    {
        return species == (int)AnimalBase.Species.Deer || species == (int)AnimalBase.Species.Rabbit ||
               species == (int)AnimalBase.Species.Bison;
    }

    private static AnimalStateData ToStateData(CharacterBody3D body)
    {
        if (body is AnimalBase ab)
            return ab.ExportStateData();

        var sp = body.Get("species");
        var species = sp.VariantType == Variant.Type.Int ? (int)sp.AsInt32() : 0;
        return new AnimalStateData
        {
            Position = body.GlobalPosition,
            Velocity = body.Velocity,
            State = 0,
            Species = species,
            Health = 2,
            PanicTimer = 0,
            WanderTimer = 0,
            WanderTarget = body.GlobalPosition,
            ThreatPosition = body.GlobalPosition,
            WanderSpeed = 0.8f,
            PanicSpeed = 4f,
            SocialFactor = 0.5f,
            CohesionRadius = 12f,
            ContagionRadius = 10f,
            PanicDuration = 3f,
            WanderPauseMin = 1f,
            WanderPauseMax = 4f,
            WanderRadius = 8f
        };
    }

    /// <summary>
    /// Get FAR animal snapshot for debug minimap. Returns packed float array [x0, z0, species0, x1, z1, species1, ...].
    /// Callable from GDScript (float[] marshals to PackedFloat32Array).
    /// </summary>
    public float[] GetFarAnimalSnapshot()
    {
        var (data, _) = _sim?.GetSnapshot() ?? (System.Array.Empty<float>(), 0);
        return data;
    }
}
