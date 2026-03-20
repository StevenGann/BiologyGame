using System;
using System.Collections.Generic;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Processes simulation cells by LOD tier. Computes player cell, iterates cells,
/// dispatches to AnimalLogic and PlantLogic. Call Tick each frame from simulation loop.
/// No Godot APIs; safe for worker thread.
/// </summary>
public class CellProcessor
{
    private readonly SimulationGrid _grid;
    private readonly AnimalStateData[] _animals;
    private readonly int _animalCount;
    private readonly PlantStateData[] _plants;
    private readonly int _plantCount;

    private Vector3 _playerPosition;
    private int _playerCellX;
    private int _playerCellZ;
    private float _transferAccumulator;

    private readonly List<int> _cellAnimalIndices = new();
    private readonly List<int> _cellPlantIndices = new();
    private readonly List<int> _sameSpeciesScratch = new();
    private readonly List<(Vector3 Pos, int State)> _neighborsScratch = new();

    public CellProcessor(
        SimulationGrid grid,
        AnimalStateData[] animals,
        int animalCount,
        PlantStateData[] plants,
        int plantCount)
    {
        _grid = grid ?? throw new ArgumentNullException(nameof(grid));
        _animals = animals ?? Array.Empty<AnimalStateData>();
        _animalCount = animalCount;
        _plants = plants ?? Array.Empty<PlantStateData>();
        _plantCount = plantCount;
    }

    /// <summary>Update player position for LOD tier computation. Call from main thread before Tick.</summary>
    public void SetPlayerPosition(float x, float z)
    {
        _playerPosition = new Vector3(x, 0, z);
        var (cx, cz) = SimulationGrid.CellFromWorld(x, z);
        _playerCellX = cx;
        _playerCellZ = cz;
    }

    /// <summary>Process one simulation tick. Call each frame.</summary>
    public void Tick(float delta)
    {
        _transferAccumulator += delta;
        if (_transferAccumulator >= SimConfig.TransferIntervalSeconds)
        {
            _grid.ProcessTransfers();
            _transferAccumulator = 0f;
        }

        var n = SimConfig.GridN;
        for (var cx = 0; cx < n; cx++)
        for (var cz = 0; cz < n; cz++)
        {
            var tier = SimulationGrid.GetLodTierForCell(cx, cz, _playerCellX, _playerCellZ);
            if (tier > 3) continue; // Beyond sim range

            var cellDelta = tier switch
            {
                0 => delta,
                1 => delta,
                2 => delta * SimConfig.LOD_Tier2_DeltaMultiplier,
                3 => delta * SimConfig.LOD_Tier3_DeltaMultiplier,
                _ => delta
            };

            ProcessCell(cx, cz, cellDelta, tier);
        }
    }

    private void ProcessCell(int cx, int cz, float delta, int tier)
    {
        _grid.GetAnimalIndicesInCell(cx, cz, _cellAnimalIndices);
        _grid.GetPlantIndicesInCell(cx, cz, _cellPlantIndices);

        foreach (var i in _cellAnimalIndices)
            ProcessAnimal(i, delta, tier);

        foreach (var i in _cellPlantIndices)
        {
            ref var plant = ref _plants[i];
            PlantLogic.Update(delta, ref plant);
        }
    }

    private void ProcessAnimal(int i, float delta, int tier)
    {
        ref var state = ref _animals[i];
        var pos = state.Position;

        _grid.GetSameSpeciesInRadius(pos, state.CohesionRadius, state.SpeciesId, i, _sameSpeciesScratch);

        _neighborsScratch.Clear();
        foreach (var j in _sameSpeciesScratch)
        {
            if (j >= _animalCount) continue;
            var other = _animals[j];
            var dSq = pos.DistanceSquaredTo(other.Position);
            if (dSq <= state.ContagionRadius * state.ContagionRadius)
                _neighborsScratch.Add((other.Position, other.State));
        }

        AnimalLogic.UpdateStateFar(delta, ref state, _neighborsScratch);

        var cohesion = ComputeCohesion(pos, state.CohesionRadius, state.SpeciesId, i);
        AnimalLogic.ApplySimpleWander(delta, ref state, cohesion);

        var vel = state.Velocity;
        state.Position = new Vector3(
            Mathf.Clamp(pos.X + vel.X * delta, SimConfig.WorldOriginX, SimConfig.WorldOriginX + SimConfig.WorldSizeXZ - 0.01f),
            pos.Y,
            Mathf.Clamp(pos.Z + vel.Z * delta, SimConfig.WorldOriginZ, SimConfig.WorldOriginZ + SimConfig.WorldSizeXZ - 0.01f));
    }

    private Vector3 ComputeCohesion(Vector3 pos, float radius, int speciesId, int excludeIndex)
    {
        _grid.GetSameSpeciesInRadius(pos, radius, speciesId, excludeIndex, _sameSpeciesScratch);
        if (_sameSpeciesScratch.Count == 0) return Vector3.Zero;

        var sum = Vector3.Zero;
        var count = 0;
        foreach (var j in _sameSpeciesScratch)
        {
            if (j >= _animalCount) continue;
            var other = _animals[j];
            if (pos.DistanceSquaredTo(other.Position) <= radius * radius)
            {
                sum += other.Position;
                count++;
            }
        }
        if (count == 0) return Vector3.Zero;

        var center = sum / count;
        var toCenter = center - pos;
        toCenter.Y = 0;
        if (toCenter.LengthSquared() < 0.0001f) return Vector3.Zero;

        return toCenter.Normalized() * 0.5f;
    }
}
