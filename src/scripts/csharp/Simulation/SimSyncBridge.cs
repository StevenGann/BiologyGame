using System;
using System.Collections.Generic;
using Godot;
using BiologyGame.Animals;
using BiologyGame.Plants;

namespace BiologyGame.Simulation;

/// <summary>
/// Main-thread bridge between C# simulation and Godot scene tree.
///
/// Flow: WorldPopulator fills active slice of arrays → SimulationGrid.Rebuild → CellProcessor.Tick each frame.
/// Optional population ramp grows active counts toward AnimalCount/PlantCount over time.
/// Entities within LOD_A cells of player get AnimalNode/PlantNode (promote); beyond
/// LOD_A + Hysteresis lose nodes (demote). HeightmapSampler provides Y for placement.
/// Exposes GetSnapshotArray for debug overlay (group "sim_bridge").
/// </summary>
public partial class SimSyncBridge : Node
{
    [Export] public NodePath AnimalsContainerPath { get; set; }
    [Export] public NodePath PlantsContainerPath { get; set; }
    [Export] public NodePath TerrainPath { get; set; }
    [Export] public NodePath PlayerPath { get; set; }

    [Export] public string AnimalScenePath { get; set; } = "res://scenes/animals/animal_base.tscn";
    [Export] public string PlantScenePath { get; set; } = "res://scenes/plants/plant_base.tscn";

    [ExportGroup("World Populator")]
    [Export] public int AnimalCount { get; set; } = 2000000;
    [Export] public int PlantCount { get; set; } = 4000000;
    [Export] public bool SpawnWholeMap { get; set; } = true;
    [Export] public float SpawnRadius { get; set; } = 600f;
    /// <summary>Added to <see cref="SimConfig.WorldOriginX"/> for spawn circle center (default ≈ world origin 0).</summary>
    [Export] public float SpawnCenterX { get; set; } = 4096f;
    [Export] public float SpawnCenterZ { get; set; } = 4096f;
    [Export] public float HerbivoreRatio { get; set; } = 0.7f;
    [Export] public int RandomSeed { get; set; } = -1;

    [ExportGroup("Population ramp")]
    /// <summary>When true, only <see cref="RampInitialAnimals"/> / <see cref="RampInitialPlants"/> exist at startup; the rest spawn over time up to AnimalCount / PlantCount.</summary>
    [Export] public bool RampPopulation { get; set; }
    [Export] public int RampInitialAnimals { get; set; } = 4096;
    [Export] public int RampInitialPlants { get; set; } = 16384;
    [Export] public float RampAnimalsPerSecond { get; set; } = 100_000f;
    [Export] public float RampPlantsPerSecond { get; set; } = 200_000f;
    /// <summary>Caps how many entities are spawned per frame per type to avoid long stalls.</summary>
    [Export] public int RampMaxSpawnPerFrame { get; set; } = 25_000;

    [ExportGroup("Debug")]
    /// <summary>Max entities packed into the minimap snapshot (each uses 4 floats). Keeps GDScript marshalling fast when sim counts are huge.</summary>
    [Export] public int DebugSnapshotMaxEntities { get; set; } = 16_384;

    private SimulationGrid _grid;
    private CellProcessor _processor;
    private AnimalStateData[] _animals;
    private PlantStateData[] _plants;
    private AnimalSpeciesConfig[] _speciesConfigs;
    private HeightmapSampler _heightSampler;

    private Node3D _animalsContainer;
    private Node3D _plantsContainer;
    private Node _terrainNode;
    private Node3D _player;

    private readonly Dictionary<int, Node3D> _promotedAnimals = new();
    private readonly Dictionary<int, Node3D> _promotedPlants = new();
    private readonly List<int> _toDemoteAnimals = new();
    private readonly List<int> _toDemotePlants = new();
    private readonly List<float> _snapshotBuffer = new();
    private float[] _snapshotArray = Array.Empty<float>();

    private PackedScene _animalScene;
    private PackedScene _plantScene;

    private int _activeAnimalCount;
    private int _activePlantCount;
    private Random _populationRng;
    private float _animalRampCarry;
    private float _plantRampCarry;

    private const int HeightmapResolution = 256;

    public override void _Ready()
    {
        AddToGroup("sim_bridge");
        _animalsContainer = GetNodeOrNull<Node3D>(AnimalsContainerPath);
        _plantsContainer = GetNodeOrNull<Node3D>(PlantsContainerPath);
        _terrainNode = GetNodeOrNull(TerrainPath);
        _player = GetNodeOrNull<Node3D>(PlayerPath);

        if (_animalsContainer == null) GD.PrintErr("SimSyncBridge: Animals container not found");
        if (_plantsContainer == null) GD.PrintErr("SimSyncBridge: Plants container not found");
        if (_player == null) GD.PrintErr("SimSyncBridge: Player not found");

        _heightSampler = new HeightmapSampler();
        _heightSampler.Initialize(
            HeightmapResolution,
            SimConfig.WorldOriginX,
            SimConfig.WorldOriginZ,
            SimConfig.WorldSizeXZ,
            SimConfig.WorldSizeXZ);

        var terrainForHeight = _terrainNode?.GetNodeOrNull<Node>("Terrain3D") ?? _terrainNode;
        if (terrainForHeight != null)
            _heightSampler.SampleFromTerrain3D(terrainForHeight);
        else
            GD.PrintErr("SimSyncBridge: Terrain3D not found for height sampling");

        _speciesConfigs = new[]
        {
            AnimalSpeciesConfig.CreateHerbivore(0, AnimalScenePath),
            AnimalSpeciesConfig.CreatePredator(1, AnimalScenePath),
        };

        _populationRng = RandomSeed >= 0 ? new Random(RandomSeed) : new Random();

        _animals = new AnimalStateData[Math.Max(0, AnimalCount)];
        _plants = new PlantStateData[Math.Max(0, PlantCount)];

        if (RampPopulation)
        {
            var initA = RampInitialAnimals > 0 ? RampInitialAnimals : Mathf.Min(4096, _animals.Length);
            var initP = RampInitialPlants > 0 ? RampInitialPlants : Mathf.Min(16384, _plants.Length);
            _activeAnimalCount = Mathf.Clamp(initA, 0, _animals.Length);
            _activePlantCount = Mathf.Clamp(initP, 0, _plants.Length);
        }
        else
        {
            _activeAnimalCount = _animals.Length;
            _activePlantCount = _plants.Length;
        }

        var config = BuildPopulatorConfig();
        WorldPopulator.Populate(
            _animals, _activeAnimalCount, _plants, _activePlantCount,
            config, _speciesConfigs[0], _speciesConfigs[1], ref _populationRng);

        _grid = new SimulationGrid();
        _grid.SetData(_animals, _activeAnimalCount, _plants, _activePlantCount);
        _grid.Rebuild();

        _processor = new CellProcessor(_grid, _animals, _activeAnimalCount, _plants, _activePlantCount);

        _animalScene = GD.Load<PackedScene>(AnimalScenePath);
        _plantScene = GD.Load<PackedScene>(PlantScenePath);

        if (_animalScene == null) GD.PrintErr("SimSyncBridge: Failed to load animal scene");
        if (_plantScene == null) GD.PrintErr("SimSyncBridge: Failed to load plant scene");
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_processor == null || _player == null) return;

        if (RampPopulation)
            RampSpawnStep((float)delta);

        var playerPos = _player.GlobalPosition;
        _processor.SetPlayerPosition(playerPos.X, playerPos.Z);
        _processor.Tick((float)delta);

        var playerCell = SimulationGrid.CellFromWorld(playerPos.X, playerPos.Z);
        var demoteThreshold = SimConfig.LOD_A_Cells + SimConfig.LOD_HysteresisCells;

        _toDemoteAnimals.Clear();
        foreach (var kv in _promotedAnimals)
        {
            var i = kv.Key;
            if (i >= _activeAnimalCount) continue;
            var dist = SimulationGrid.ManhattanDistance(
                _animals[i].CellX, _animals[i].CellZ,
                playerCell.CellX, playerCell.CellZ);
            if (dist > demoteThreshold)
                _toDemoteAnimals.Add(i);
        }
        foreach (var i in _toDemoteAnimals)
        {
            if (_promotedAnimals.TryGetValue(i, out var node))
            {
                _animalsContainer?.RemoveChild(node);
                node.QueueFree();
                _promotedAnimals.Remove(i);
            }
        }

        _toDemotePlants.Clear();
        foreach (var kv in _promotedPlants)
        {
            var i = kv.Key;
            if (i >= _activePlantCount) continue;
            if (_plants[i].IsConsumed) { _toDemotePlants.Add(i); continue; }
            var dist = SimulationGrid.ManhattanDistance(
                _plants[i].CellX, _plants[i].CellZ,
                playerCell.CellX, playerCell.CellZ);
            if (dist > demoteThreshold)
                _toDemotePlants.Add(i);
        }
        foreach (var i in _toDemotePlants)
        {
            if (_promotedPlants.TryGetValue(i, out var node))
            {
                _plantsContainer?.RemoveChild(node);
                node.QueueFree();
                _promotedPlants.Remove(i);
            }
        }

        for (var i = 0; i < _activeAnimalCount; i++)
        {
            var dist = SimulationGrid.ManhattanDistance(
                _animals[i].CellX, _animals[i].CellZ,
                playerCell.CellX, playerCell.CellZ);
            if (dist <= SimConfig.LOD_A_Cells)
            {
                if (!_promotedAnimals.ContainsKey(i))
                    PromoteAnimal(i);
                else
                    SyncAnimal(i);
            }
        }

        for (var i = 0; i < _activePlantCount; i++)
        {
            if (_plants[i].IsConsumed) continue;
            var dist = SimulationGrid.ManhattanDistance(
                _plants[i].CellX, _plants[i].CellZ,
                playerCell.CellX, playerCell.CellZ);
            if (dist <= SimConfig.LOD_A_Cells)
            {
                if (!_promotedPlants.ContainsKey(i))
                    PromotePlant(i);
                else
                    SyncPlant(i);
            }
        }
    }

    private void PromoteAnimal(int i)
    {
        if (_animalsContainer == null || _animalScene == null) return;
        ref var state = ref _animals[i];
        var node = _animalScene.Instantiate<Node3D>();
        var h = _heightSampler?.SampleHeight(state.Position.X, state.Position.Z) ?? 0;
        var pos = new Vector3(state.Position.X, h + 0.4f, state.Position.Z);
        node.SetMeta("sim_index", i);
        node.SetMeta("is_animal", true);
        _animalsContainer.AddChild(node);
        _promotedAnimals[i] = node;
        if (node is AnimalNode animalNode)
            animalNode.ApplyState(pos, state.Velocity, state.SpeciesId);
        else
            node.GlobalPosition = pos;
    }

    private void PromotePlant(int i)
    {
        if (_plantsContainer == null || _plantScene == null) return;
        ref var plant = ref _plants[i];
        var node = _plantScene.Instantiate<Node3D>();
        var h = _heightSampler?.SampleHeight(plant.Position.X, plant.Position.Z) ?? 0;
        var pos = new Vector3(plant.Position.X, h + 0.4f, plant.Position.Z);
        node.SetMeta("sim_index", i);
        node.SetMeta("is_animal", false);
        _plantsContainer.AddChild(node);
        _promotedPlants[i] = node;
        if (node is PlantNode plantNode)
            plantNode.ApplyState(pos, !plant.IsConsumed);
        else
            node.GlobalPosition = pos;
    }

    private void SyncAnimal(int i)
    {
        if (!_promotedAnimals.TryGetValue(i, out var node)) return;
        ref var state = ref _animals[i];
        var h = _heightSampler?.SampleHeight(state.Position.X, state.Position.Z) ?? 0;
        var pos = new Vector3(state.Position.X, h + 0.4f, state.Position.Z);
        if (node is AnimalNode animalNode)
            animalNode.ApplyState(pos, state.Velocity, state.SpeciesId);
        else
            node.GlobalPosition = pos;
    }

    private void SyncPlant(int i)
    {
        if (!_promotedPlants.TryGetValue(i, out var node)) return;
        ref var plant = ref _plants[i];
        var h = _heightSampler?.SampleHeight(plant.Position.X, plant.Position.Z) ?? 0;
        var pos = new Vector3(plant.Position.X, h + 0.4f, plant.Position.Z);
        if (node is PlantNode plantNode)
            plantNode.ApplyState(pos, !plant.IsConsumed);
        else
            node.GlobalPosition = pos;
    }

    /// <summary>Minimap / sim use same world frame as <see cref="SimConfig"/> (Terrain3D-centered).</summary>
    public float GetDebugMapWorldOriginX() => SimConfig.WorldOriginX;

    public float GetDebugMapWorldOriginZ() => SimConfig.WorldOriginZ;

    public float GetDebugMapWorldSizeXZ() => SimConfig.WorldSizeXZ;

    /// <summary>Thread-safe snapshot for debug overlay. Packed as [x, z, isAnimal, speciesId, ...].</summary>
    public void GetSnapshot(List<float> outBuffer)
    {
        var cap = DebugSnapshotMaxEntities > 0 ? DebugSnapshotMaxEntities : int.MaxValue;
        _grid?.GetSnapshot(outBuffer, cap);
    }

    /// <summary>Returns snapshot as float[] for GDScript (e.g. debug overlay). Packed as [x, z, isAnimal, speciesId, ...]. Reuses internal buffer to avoid GC pressure.</summary>
    public float[] GetSnapshotArray()
    {
        _snapshotBuffer.Clear();
        var cap = DebugSnapshotMaxEntities > 0 ? DebugSnapshotMaxEntities : int.MaxValue;
        _grid?.GetSnapshot(_snapshotBuffer, cap);
        var count = _snapshotBuffer.Count;
        if (_snapshotArray.Length != count)
            _snapshotArray = new float[count];
        for (var i = 0; i < count; i++)
            _snapshotArray[i] = _snapshotBuffer[i];
        return _snapshotArray;
    }

    private WorldPopulatorConfig BuildPopulatorConfig()
    {
        return new WorldPopulatorConfig
        {
            AnimalCount = AnimalCount,
            HerbivoreRatio = HerbivoreRatio,
            PlantCount = PlantCount,
            SpawnWholeMap = SpawnWholeMap,
            SpawnCenterX = SimConfig.WorldOriginX + SpawnCenterX,
            SpawnCenterZ = SimConfig.WorldOriginZ + SpawnCenterZ,
            SpawnRadius = SpawnRadius,
            Seed = RandomSeed >= 0 ? RandomSeed : null,
            PlantMaxHealth = 3,
        };
    }

    private void RampSpawnStep(float delta)
    {
        if (_grid == null || _processor == null) return;
        if (_activeAnimalCount >= AnimalCount && _activePlantCount >= PlantCount) return;

        var cfg = BuildPopulatorConfig();
        var maxBatch = Math.Max(1, RampMaxSpawnPerFrame);
        var changed = false;

        _animalRampCarry += RampAnimalsPerSecond * delta;
        if (_activeAnimalCount < AnimalCount && _animalRampCarry >= 1f)
        {
            var want = (int)_animalRampCarry;
            var batch = Math.Min(Math.Min(want, maxBatch), AnimalCount - _activeAnimalCount);
            _animalRampCarry -= batch;
            for (var k = 0; k < batch; k++)
            {
                var i = _activeAnimalCount;
                WorldPopulator.SpawnAnimalAt(i, _animals, ref _populationRng, cfg, _speciesConfigs[0], _speciesConfigs[1]);
                _grid.RegisterAnimal(i);
                _activeAnimalCount++;
            }
            changed = true;
        }

        _plantRampCarry += RampPlantsPerSecond * delta;
        if (_activePlantCount < PlantCount && _plantRampCarry >= 1f)
        {
            var want = (int)_plantRampCarry;
            var batch = Math.Min(Math.Min(want, maxBatch), PlantCount - _activePlantCount);
            _plantRampCarry -= batch;
            for (var k = 0; k < batch; k++)
            {
                var i = _activePlantCount;
                WorldPopulator.SpawnPlantAt(i, _plants, ref _populationRng, cfg);
                _grid.RegisterPlant(i);
                _activePlantCount++;
            }
            changed = true;
        }

        if (changed)
        {
            _grid.SetData(_animals, _activeAnimalCount, _plants, _activePlantCount);
            _processor.SetActiveEntityCounts(_activeAnimalCount, _activePlantCount);
        }
    }
}
