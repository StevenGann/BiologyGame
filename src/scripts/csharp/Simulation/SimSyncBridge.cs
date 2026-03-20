using System;
using System.Collections.Generic;
using Godot;
using BiologyGame.Animals;
using BiologyGame.Plants;

namespace BiologyGame.Simulation;

/// <summary>
/// Main-thread bridge between C# simulation and Godot scene tree.
///
/// Flow: WorldPopulator fills arrays → SimulationGrid.Rebuild → CellProcessor.Tick each frame.
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
    [Export] public float SpawnCenterX { get; set; } = 400f;
    [Export] public float SpawnCenterZ { get; set; } = 400f;
    [Export] public float HerbivoreRatio { get; set; } = 0.7f;
    [Export] public int RandomSeed { get; set; } = -1;

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

        _animals = new AnimalStateData[AnimalCount];
        _plants = new PlantStateData[PlantCount];

        var config = new WorldPopulatorConfig
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
        WorldPopulator.Populate(
            _animals, AnimalCount, _plants, PlantCount,
            config, _speciesConfigs[0], _speciesConfigs[1]);

        _grid = new SimulationGrid();
        _grid.SetData(_animals, AnimalCount, _plants, PlantCount);
        _grid.Rebuild();

        _processor = new CellProcessor(_grid, _animals, AnimalCount, _plants, PlantCount);

        _animalScene = GD.Load<PackedScene>(AnimalScenePath);
        _plantScene = GD.Load<PackedScene>(PlantScenePath);

        if (_animalScene == null) GD.PrintErr("SimSyncBridge: Failed to load animal scene");
        if (_plantScene == null) GD.PrintErr("SimSyncBridge: Failed to load plant scene");
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_processor == null || _player == null) return;

        var playerPos = _player.GlobalPosition;
        _processor.SetPlayerPosition(playerPos.X, playerPos.Z);
        _processor.Tick((float)delta);

        var playerCell = SimulationGrid.CellFromWorld(playerPos.X, playerPos.Z);
        var demoteThreshold = SimConfig.LOD_A_Cells + SimConfig.LOD_HysteresisCells;

        _toDemoteAnimals.Clear();
        foreach (var kv in _promotedAnimals)
        {
            var i = kv.Key;
            if (i >= AnimalCount) continue;
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
            if (i >= PlantCount) continue;
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

        for (var i = 0; i < AnimalCount; i++)
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

        for (var i = 0; i < PlantCount; i++)
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

    /// <summary>Thread-safe snapshot for debug overlay. Packed as [x, z, isAnimal, speciesId, ...].</summary>
    public void GetSnapshot(List<float> outBuffer)
    {
        _grid?.GetSnapshot(outBuffer);
    }

    /// <summary>Returns snapshot as float[] for GDScript (e.g. debug overlay). Packed as [x, z, isAnimal, speciesId, ...]. Reuses internal buffer to avoid GC pressure.</summary>
    public float[] GetSnapshotArray()
    {
        _snapshotBuffer.Clear();
        _grid?.GetSnapshot(_snapshotBuffer);
        var count = _snapshotBuffer.Count;
        if (_snapshotArray.Length != count)
            _snapshotArray = new float[count];
        for (var i = 0; i < count; i++)
            _snapshotArray[i] = _snapshotBuffer[i];
        return _snapshotArray;
    }
}
