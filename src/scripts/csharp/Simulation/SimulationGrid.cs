using System;
using System.Collections.Generic;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// N×N spatial grid for animals and plants. Supports cell assignment, transfer-on-boundary-cross,
/// and neighbor queries. Uses SimConfig for bounds and cell size.
/// </summary>
public class SimulationGrid
{
    private readonly List<int>[,] _animalCells;
    private readonly List<int>[,] _plantCells;
    private readonly object _lock = new();

    private AnimalStateData[] _animals = Array.Empty<AnimalStateData>();
    private int _animalCount;
    private PlantStateData[] _plants = Array.Empty<PlantStateData>();
    private int _plantCount;

    public SimulationGrid()
    {
        var n = SimConfig.GridN;
        _animalCells = new List<int>[n, n];
        _plantCells = new List<int>[n, n];
        for (var x = 0; x < n; x++)
        for (var z = 0; z < n; z++)
        {
            _animalCells[x, z] = new List<int>();
            _plantCells[x, z] = new List<int>();
        }
    }

    /// <summary>Set the backing arrays. Call before Rebuild or ProcessTransfers.</summary>
    public void SetData(AnimalStateData[] animals, int animalCount, PlantStateData[] plants, int plantCount)
    {
        lock (_lock)
        {
            _animals = animals ?? Array.Empty<AnimalStateData>();
            _animalCount = animalCount;
            _plants = plants ?? Array.Empty<PlantStateData>();
            _plantCount = plantCount;
        }
    }

    /// <summary>Compute cell indices from world position. Clamps to valid range.</summary>
    public static (int CellX, int CellZ) CellFromWorld(float worldX, float worldZ)
    {
        var u = (worldX - SimConfig.WorldOriginX) / SimConfig.CellSizeMeters;
        var v = (worldZ - SimConfig.WorldOriginZ) / SimConfig.CellSizeMeters;
        var cx = (int)Mathf.Floor(u);
        var cz = (int)Mathf.Floor(v);
        cx = Mathf.Clamp(cx, 0, SimConfig.GridN - 1);
        cz = Mathf.Clamp(cz, 0, SimConfig.GridN - 1);
        return (cx, cz);
    }

    /// <summary>Manhattan distance between two cells.</summary>
    public static int ManhattanDistance(int cx1, int cz1, int cx2, int cz2)
    {
        return Math.Abs(cx1 - cx2) + Math.Abs(cz1 - cz2);
    }

    /// <summary>
    /// Rebuild the grid from current positions. Clears all cells and reassigns.
    /// Call when bulk-loading or after significant changes.
    /// </summary>
    public void Rebuild()
    {
        lock (_lock)
        {
            ClearCells();

            for (var i = 0; i < _animalCount; i++)
            {
                var pos = _animals[i].Position;
                var (cx, cz) = CellFromWorld(pos.X, pos.Z);
                _animals[i].CellX = cx;
                _animals[i].CellZ = cz;
                _animalCells[cx, cz].Add(i);
            }

            for (var i = 0; i < _plantCount; i++)
            {
                if (_plants[i].IsConsumed) continue;
                var pos = _plants[i].Position;
                var (cx, cz) = CellFromWorld(pos.X, pos.Z);
                _plants[i].CellX = cx;
                _plants[i].CellZ = cz;
                _plantCells[cx, cz].Add(i);
            }
        }
    }

    /// <summary>
    /// Check for boundary crosses and transfer entities. Call every M seconds.
    /// </summary>
    public void ProcessTransfers()
    {
        lock (_lock)
        {
            for (var i = 0; i < _animalCount; i++)
            {
                var pos = _animals[i].Position;
                var (newCx, newCz) = CellFromWorld(pos.X, pos.Z);
                var oldCx = _animals[i].CellX;
                var oldCz = _animals[i].CellZ;

                if (newCx != oldCx || newCz != oldCz)
                {
                    var list = _animalCells[oldCx, oldCz];
                    var idx = list.IndexOf(i);
                    if (idx >= 0)
                    {
                        list.RemoveAt(idx);
                    }
                    _animals[i].CellX = newCx;
                    _animals[i].CellZ = newCz;
                    _animalCells[newCx, newCz].Add(i);
                }
            }

            for (var i = 0; i < _plantCount; i++)
            {
                if (_plants[i].IsConsumed) continue;
                var pos = _plants[i].Position;
                var (newCx, newCz) = CellFromWorld(pos.X, pos.Z);
                var oldCx = _plants[i].CellX;
                var oldCz = _plants[i].CellZ;

                if (newCx != oldCx || newCz != oldCz)
                {
                    var list = _plantCells[oldCx, oldCz];
                    var idx = list.IndexOf(i);
                    if (idx >= 0)
                    {
                        list.RemoveAt(idx);
                    }
                    _plants[i].CellX = newCx;
                    _plants[i].CellZ = newCz;
                    _plantCells[newCx, newCz].Add(i);
                }
            }
        }
    }

    /// <summary>Fill outIndices with animal indices of same species within radius. Searches only adjacent cells (3x3). Clears list first.</summary>
    public void GetSameSpeciesInRadius(
        Vector3 center,
        float radius,
        int speciesId,
        int excludeIndex,
        List<int> outIndices)
    {
        outIndices.Clear();
        var rSq = radius * radius;
        var cells = GetAdjacentCells(center);

        lock (_lock)
        {
        foreach (var (cx, cz) in cells)
        {
            if (cx < 0 || cx >= SimConfig.GridN || cz < 0 || cz >= SimConfig.GridN) continue;
            var list = _animalCells[cx, cz];
            foreach (var i in list)
            {
                if (i == excludeIndex) continue;
                if (i >= _animalCount) continue;
                if (_animals[i].SpeciesId != speciesId) continue;
                if (center.DistanceSquaredTo(_animals[i].Position) <= rSq)
                    outIndices.Add(i);
            }
        }
        }
    }

    /// <summary>Fill outIndices with animal indices within radius. Searches only adjacent cells (3x3). Clears list first.</summary>
    public void GetAnimalsInRadius(Vector3 center, float radius, List<int> outIndices, int? excludeIndex = null)
    {
        outIndices.Clear();
        var rSq = radius * radius;
        var cells = GetAdjacentCells(center);

        lock (_lock)
        {
        foreach (var (cx, cz) in cells)
        {
            if (cx < 0 || cx >= SimConfig.GridN || cz < 0 || cz >= SimConfig.GridN) continue;
            var list = _animalCells[cx, cz];
            foreach (var i in list)
            {
                if (i >= _animalCount) continue;
                if (excludeIndex.HasValue && i == excludeIndex.Value) continue;
                if (center.DistanceSquaredTo(_animals[i].Position) <= rSq)
                    outIndices.Add(i);
            }
        }
        }
    }

    /// <summary>Fill outIndices with plant indices within radius (excluding consumed). Searches only adjacent cells (3x3). Clears list first.</summary>
    public void GetPlantsInRadius(Vector3 center, float radius, List<int> outIndices)
    {
        outIndices.Clear();
        var rSq = radius * radius;
        var cells = GetAdjacentCells(center);

        lock (_lock)
        {
        foreach (var (cx, cz) in cells)
        {
            if (cx < 0 || cx >= SimConfig.GridN || cz < 0 || cz >= SimConfig.GridN) continue;
            var list = _plantCells[cx, cz];
            foreach (var i in list)
            {
                if (i >= _plantCount) continue;
                if (_plants[i].IsConsumed) continue;
                if (center.DistanceSquaredTo(_plants[i].Position) <= rSq)
                    outIndices.Add(i);
            }
        }
        }
    }

    /// <summary>
    /// Get a snapshot of all entity positions for debug overlay.
    /// Packed as: [x, z, isAnimal(0/1), speciesId, ...] per entity.
    /// Clears and fills the provided list. Safe to call from any thread if grid is locked externally.
    /// </summary>
    public void GetSnapshot(List<float> outBuffer)
    {
        outBuffer.Clear();
        lock (_lock)
        {
            for (var i = 0; i < _animalCount; i++)
            {
                var p = _animals[i].Position;
                outBuffer.Add(p.X);
                outBuffer.Add(p.Z);
                outBuffer.Add(1f);
                outBuffer.Add((float)_animals[i].SpeciesId);
            }
            for (var i = 0; i < _plantCount; i++)
            {
                if (_plants[i].IsConsumed) continue;
                var p = _plants[i].Position;
                outBuffer.Add(p.X);
                outBuffer.Add(p.Z);
                outBuffer.Add(0f);
                outBuffer.Add((float)_plants[i].SpeciesId);
            }
        }
    }

    /// <summary>Get LOD tier (0–3) for a cell based on Manhattan distance from player cell.</summary>
    public static int GetLodTierForCell(int cellX, int cellZ, int playerCellX, int playerCellZ)
    {
        var dist = ManhattanDistance(cellX, cellZ, playerCellX, playerCellZ);
        if (dist <= SimConfig.LOD_A_Cells) return 0;
        if (dist <= SimConfig.LOD_B_Cells) return 1;
        if (dist <= SimConfig.LOD_C_Cells) return 2;
        if (dist <= SimConfig.LOD_D_Cells) return 3;
        return 4;
    }

    private void ClearCells()
    {
        for (var x = 0; x < SimConfig.GridN; x++)
        for (var z = 0; z < SimConfig.GridN; z++)
        {
            _animalCells[x, z].Clear();
            _plantCells[x, z].Clear();
        }
    }

    /// <summary>Returns the center cell plus its 8 adjacent cells (3x3). Used for neighbor queries.</summary>
    private static List<(int Cx, int Cz)> GetAdjacentCells(Vector3 center)
    {
        var (cx, cz) = CellFromWorld(center.X, center.Z);
        var result = new List<(int, int)>(9);
        for (var dx = -1; dx <= 1; dx++)
        for (var dz = -1; dz <= 1; dz++)
            result.Add((cx + dx, cz + dz));
        return result;
    }
}
