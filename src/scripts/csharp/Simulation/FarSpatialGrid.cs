using System.Collections.Generic;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Spatial grid for FAR animal neighbor queries. Cell size matches SimulationManager (24).
/// </summary>
public class FarSpatialGrid
{
    public const float CellSize = 24.0f;

    private readonly Dictionary<Vector2I, List<int>> _cells = new();
    private AnimalStateData[] _animals;
    private int _count;

    public void Rebuild(AnimalStateData[] animals, int count)
    {
        _animals = animals;
        _count = count;
        _cells.Clear();
        for (var i = 0; i < count; i++)
        {
            var pos = animals[i].Position;
            var key = CellKey(pos);
            if (!_cells.TryGetValue(key, out var list))
            {
                list = new List<int>();
                _cells[key] = list;
            }
            list.Add(i);
        }
    }

    public void GetSameSpeciesInRadius(Vector3 center, float radius, int species, int excludeId, List<int> outIndices)
    {
        outIndices.Clear();
        var rSq = radius * radius;
        var cells = CellsInRadius(center, radius);
        foreach (var key in cells)
        {
            if (!_cells.TryGetValue(key, out var list)) continue;
            foreach (var i in list)
            {
                if (i == excludeId) continue;
                if (_animals[i].Species != species) continue;
                if (center.DistanceSquaredTo(_animals[i].Position) <= rSq)
                    outIndices.Add(i);
            }
        }
    }

    private static Vector2I CellKey(Vector3 pos) =>
        new((int)Mathf.Floor(pos.X / CellSize), (int)Mathf.Floor(pos.Z / CellSize));

    private static List<Vector2I> CellsInRadius(Vector3 center, float radius)
    {
        var result = new List<Vector2I>();
        var cx = (int)Mathf.Floor(center.X / CellSize);
        var cz = (int)Mathf.Floor(center.Z / CellSize);
        var cellRadius = (int)Mathf.Ceil(radius / CellSize) + 1;
        for (var dx = -cellRadius; dx <= cellRadius; dx++)
        for (var dz = -cellRadius; dz <= cellRadius; dz++)
            result.Add(new Vector2I(cx + dx, cz + dz));
        return result;
    }
}
