using Godot;
using System.Collections.Generic;

namespace BiologyGame.Animals;

/// <summary>
/// Renders MEDIUM LOD animals as GPU-instanced colored capsules via MultiMeshInstance3D.
/// One MultiMeshInstance3D per species, each using a CapsuleMesh with the species' tint color.
///
/// At FULL LOD: animals use their full 3D model (managed by AnimalBase).
/// At MEDIUM LOD: the 3D model is hidden; this renderer shows a colored capsule at the animal's position.
/// At FAR LOD: animals are managed by FarAnimalSim (no scene node visible at all).
///
/// Usage:
///   - Add as a child of the Animals node (or any Node3D in the scene).
///   - Each physics frame, call UpdatePositions() which reads all MEDIUM animals and
///     bulk-updates the MultiMesh transforms.
///   - Animals call SetVisualLod(lod) on LOD tier change to show/hide their 3D model.
///
/// Add to the "animal_mmr" group so AnimalBase can find it via GetTree().
/// </summary>
public partial class AnimalMultimeshRenderer : Node3D
{
    // Capsule dimensions per species (height, radius).
    private static readonly Dictionary<AnimalBase.Species, (float Height, float Radius)> SpeciesCapsule = new()
    {
        [AnimalBase.Species.Bison]  = (2.0f, 0.6f),
        [AnimalBase.Species.Deer]   = (1.8f, 0.4f),
        [AnimalBase.Species.Rabbit] = (0.6f, 0.2f),
        [AnimalBase.Species.Wolf]   = (1.2f, 0.35f),
        [AnimalBase.Species.Bear]   = (2.5f, 0.7f),
    };

    private static readonly Dictionary<AnimalBase.Species, Color> SpeciesColor = new()
    {
        [AnimalBase.Species.Bison]  = new Color(0.82f, 0.71f, 0.55f),
        [AnimalBase.Species.Deer]   = new Color(0.9f,  0.78f, 0.6f),
        [AnimalBase.Species.Rabbit] = new Color(1.0f,  1.0f,  1.0f),
        [AnimalBase.Species.Wolf]   = new Color(0.52f, 0.52f, 0.55f),
        [AnimalBase.Species.Bear]   = new Color(0.45f, 0.28f, 0.18f),
    };

    /// <summary>Radius beyond which full-3D model is hidden (should match SimulationManager.full_sim_radius).</summary>
    [Export] public float MediumLodRadius { get; set; } = 50.0f;

    // One MultiMeshInstance3D per species.
    private readonly Dictionary<AnimalBase.Species, MultiMeshInstance3D> _mmis = new();
    // Per-species list of animals currently at MEDIUM LOD (updated each frame).
    private readonly Dictionary<AnimalBase.Species, List<Node3D>> _mediumAnimals = new();

    private Node _animalsNode;

    public override void _Ready()
    {
        AddToGroup("animal_mmr");
        _animalsNode = GetParent();
        _SetupMultiMeshes();
    }

    public override void _Process(double delta)
    {
        UpdatePositions();
    }

    /// <summary>
    /// Scan all animals in the Animals node, collect MEDIUM-LOD ones by species,
    /// and bulk-update MultiMesh transforms.
    /// </summary>
    public void UpdatePositions()
    {
        // Clear per-species lists.
        foreach (var species in _mediumAnimals.Keys)
            _mediumAnimals[species].Clear();

        // Classify by LOD (uses SimulationManager group lookup for consistency).
        var sim = GetTree().GetFirstNodeInGroup("simulation_manager");
        foreach (var child in _animalsNode.GetChildren())
        {
            if (child is not AnimalBase animal || !GodotObject.IsInstanceValid(animal)) continue;
            if (!_mediumAnimals.ContainsKey(animal.species)) continue;

            int lod = 1; // Default MEDIUM
            if (sim != null)
                lod = (int)sim.Call("get_lod_tier", animal.GlobalPosition).AsInt32();

            if (lod == AnimalBase.LODTierMedium)
                _mediumAnimals[animal.species].Add(animal);
        }

        // Write transforms to MultiMesh buffers.
        foreach (var (species, animals) in _mediumAnimals)
        {
            if (!_mmis.TryGetValue(species, out var mmi)) continue;
            var mm = mmi.Multimesh;

            var count = animals.Count;
            if (mm.InstanceCount < count)
                mm.InstanceCount = count + 64; // Grow with headroom.

            for (var i = 0; i < count; i++)
            {
                var pos = animals[i].GlobalPosition;
                var (height, _) = SpeciesCapsule[species];
                // Offset up by half capsule height so capsule sits on ground.
                var xform = new Transform3D(Basis.Identity, pos + new Vector3(0, height * 0.5f, 0));
                mm.SetInstanceTransform(i, xform);
            }

            mm.VisibleInstanceCount = count;
        }
    }

    private void _SetupMultiMeshes()
    {
        var shader = GD.Load<Shader>("res://shaders/ps1_style.gdshader");
        var whiteTex = GD.Load<Texture2D>("res://assets/heightmaps/white_1x1.png");

        foreach (AnimalBase.Species species in System.Enum.GetValues<AnimalBase.Species>())
        {
            _mediumAnimals[species] = new List<Node3D>();

            var (height, radius) = SpeciesCapsule.GetValueOrDefault(species, (1.5f, 0.4f));
            var color = SpeciesColor.GetValueOrDefault(species, Colors.White);

            var capsule = new CapsuleMesh
            {
                Height = height,
                Radius = radius
            };

            var mm = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                InstanceCount = 32,
                VisibleInstanceCount = 0,
                Mesh = capsule
            };

            ShaderMaterial mat = null;
            if (shader != null)
            {
                mat = new ShaderMaterial { Shader = shader };
                mat.SetShaderParameter("albedo", whiteTex);
                mat.SetShaderParameter("albedo_color", color);
                mat.SetShaderParameter("use_solid_tint", true);
            }

            var mmi = new MultiMeshInstance3D
            {
                Multimesh = mm,
                CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
                VisibilityRangeBegin = MediumLodRadius,
                VisibilityRangeBeginMargin = 10.0f
            };
            if (mat != null)
                mmi.MaterialOverride = mat;

            AddChild(mmi);
            _mmis[species] = mmi;
        }
    }
}
