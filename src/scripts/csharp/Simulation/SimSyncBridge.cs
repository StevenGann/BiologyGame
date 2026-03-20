using System;
using System.Collections.Generic;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Bridges simulation (C# arrays) and Godot scene tree. Runs on main thread in _PhysicsProcess.
/// Promote: tier 0 entities get Godot nodes. Demote: entities leaving tier 0 lose nodes.
/// Hysteresis avoids thrashing at boundaries.
/// </summary>
public partial class SimSyncBridge : Node
{
    [Export] public NodePath AnimalsContainerPath { get; set; }
    [Export] public NodePath PlantsContainerPath { get; set; }
    [Export] public NodePath TerrainPath { get; set; }
    [Export] public NodePath PlayerPath { get; set; }

    [Export] public string AnimalScenePath { get; set; } = "res://scenes/animals/animal_base.tscn";
    [Export] public string PlantScenePath { get; set; } = "res://scenes/plants/plant_base.tscn";

    private SimulationGrid _grid;
    private CellProcessor _processor;
    private AnimalStateData[] _animals;
    private int _animalCount;
    private PlantStateData[] _plants;
    private int _plantCount;
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

    private PackedScene _animalScene;
    private PackedScene _plantScene;

    private const int HeightmapResolution = 256;
    private const int InitialAnimalCount = 20;
    private const int InitialPlantCount = 50;

    public override void _Ready()
    {
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

        _animals = new AnimalStateData[InitialAnimalCount];
        _plants = new PlantStateData[InitialPlantCount];

        var rng = new Random();
        var spawnRadius = 300f;
        for (var i = 0; i < InitialAnimalCount; i++)
        {
            _animals[i] = CreateAnimalState(rng, i % 2, spawnRadius);
        }
        for (var i = 0; i < InitialPlantCount; i++)
        {
            _plants[i] = CreatePlantState(rng, spawnRadius);
        }

        _grid = new SimulationGrid();
        _grid.SetData(_animals, InitialAnimalCount, _plants, InitialPlantCount);
        _grid.Rebuild();

        _processor = new CellProcessor(_grid, _animals, InitialAnimalCount, _plants, InitialPlantCount);

        _animalScene = GD.Load<PackedScene>(AnimalScenePath);
        _plantScene = GD.Load<PackedScene>(PlantScenePath);

        if (_animalScene == null) GD.PrintErr("SimSyncBridge: Failed to load animal scene");
        if (_plantScene == null) GD.PrintErr("SimSyncBridge: Failed to load plant scene");
    }

    private static AnimalStateData CreateAnimalState(Random rng, int speciesId, float spawnRadius = 8192f)
    {
        var config = speciesId == 0
            ? AnimalSpeciesConfig.CreateHerbivore(0)
            : AnimalSpeciesConfig.CreatePredator(1);
        var cx = SimConfig.WorldOriginX + 200f;
        var cz = SimConfig.WorldOriginZ + 200f;
        var x = cx + (float)((rng.NextDouble() * 2 - 1) * spawnRadius);
        var z = cz + (float)((rng.NextDouble() * 2 - 1) * spawnRadius);
        x = Mathf.Clamp(x, SimConfig.WorldOriginX, SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1);
        z = Mathf.Clamp(z, SimConfig.WorldOriginZ, SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 1);
        return new AnimalStateData
        {
            Position = new Vector3(x, 0, z),
            Velocity = Vector3.Zero,
            State = 0,
            SpeciesId = speciesId,
            Health = 100,
            CellX = 0,
            CellZ = 0,
            PanicTimer = 0,
            WanderTimer = 0,
            WanderTarget = new Vector3(x, 0, z),
            ThreatPosition = Vector3.Zero,
            WanderSpeed = config.WanderSpeed,
            PanicSpeed = config.PanicSpeed,
            SocialFactor = config.SocialFactor,
            CohesionRadius = config.CohesionRadius,
            ContagionRadius = config.ContagionRadius,
            PanicDuration = config.PanicDuration,
            WanderPauseMin = config.WanderPauseMin,
            WanderPauseMax = config.WanderPauseMax,
            WanderRadius = config.WanderRadius,
        };
    }

    private static PlantStateData CreatePlantState(Random rng, float spawnRadius = 8192f)
    {
        var cx = SimConfig.WorldOriginX + 200f;
        var cz = SimConfig.WorldOriginZ + 200f;
        var x = cx + (float)((rng.NextDouble() * 2 - 1) * spawnRadius);
        var z = cz + (float)((rng.NextDouble() * 2 - 1) * spawnRadius);
        x = Mathf.Clamp(x, SimConfig.WorldOriginX, SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 1);
        z = Mathf.Clamp(z, SimConfig.WorldOriginZ, SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 1);
        return new PlantStateData
        {
            Position = new Vector3(x, 0, z),
            CellX = 0,
            CellZ = 0,
            Health = 3,
            MaxHealth = 3,
            SpeciesId = 0,
        };
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
            if (i >= _animalCount) continue;
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
            if (i >= _plantCount) continue;
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

        for (var i = 0; i < _animalCount; i++)
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

        for (var i = 0; i < _plantCount; i++)
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
        node.GlobalPosition = new Vector3(state.Position.X, h + 0.4f, state.Position.Z);
        node.SetMeta("sim_index", i);
        node.SetMeta("is_animal", true);
        _animalsContainer.AddChild(node);
        _promotedAnimals[i] = node;
    }

    private void PromotePlant(int i)
    {
        if (_plantsContainer == null || _plantScene == null) return;
        ref var plant = ref _plants[i];
        var node = _plantScene.Instantiate<Node3D>();
        var h = _heightSampler?.SampleHeight(plant.Position.X, plant.Position.Z) ?? 0;
        node.GlobalPosition = new Vector3(plant.Position.X, h + 0.4f, plant.Position.Z);
        node.SetMeta("sim_index", i);
        node.SetMeta("is_animal", false);
        _plantsContainer.AddChild(node);
        _promotedPlants[i] = node;
    }

    private void SyncAnimal(int i)
    {
        if (!_promotedAnimals.TryGetValue(i, out var node)) return;
        ref var state = ref _animals[i];
        var h = _heightSampler?.SampleHeight(state.Position.X, state.Position.Z) ?? 0;
        node.GlobalPosition = new Vector3(state.Position.X, h + 0.4f, state.Position.Z);
    }

    private void SyncPlant(int i)
    {
        if (!_promotedPlants.TryGetValue(i, out var node)) return;
        ref var plant = ref _plants[i];
        var h = _heightSampler?.SampleHeight(plant.Position.X, plant.Position.Z) ?? 0;
        node.GlobalPosition = new Vector3(plant.Position.X, h + 0.4f, plant.Position.Z);
    }

    /// <summary>Thread-safe snapshot for debug overlay. Packed as [x, z, isAnimal, speciesId, ...].</summary>
    public void GetSnapshot(List<float> outBuffer)
    {
        _grid?.GetSnapshot(outBuffer);
    }
}
