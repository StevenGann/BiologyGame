using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pre-baked height grid for worker-thread-safe sampling. Main thread populates via
/// SampleFromTerrain (calls terrain.get_height_at). Worker uses SampleHeight (no Godot APIs).
/// </summary>
public class HeightmapSampler
{
    public float TerrainSize { get; private set; }
    public float HeightMin { get; private set; }
    public float HeightMax { get; private set; }
    public int Resolution { get; private set; }

    private float[,] _heights;
    private float _halfSize;

    /// <summary>Allocate grid. Call before SampleFromTerrain.</summary>
    public void Initialize(int resolution, float terrainSize, float heightMin, float heightMax)
    {
        Resolution = resolution;
        TerrainSize = terrainSize;
        HeightMin = heightMin;
        HeightMax = heightMax;
        _halfSize = terrainSize * 0.5f;
        _heights = new float[resolution, resolution];
    }

    /// <summary>
    /// Call from main thread only. Samples terrain.get_height_at at grid points.
    /// </summary>
    /// <param name="terrainNode">Terrain node with get_height_at(x, z) method.</param>
    public void SampleFromTerrain(Node terrainNode)
    {
        if (_heights == null) return;
        if (!terrainNode.HasMethod("get_height_at"))
        {
            GD.PrintErr("HeightmapSampler: terrain has no get_height_at");
            return;
        }
        var step = TerrainSize / (Resolution - 1);
        for (var z = 0; z < Resolution; z++)
        for (var x = 0; x < Resolution; x++)
        {
            var wx = -_halfSize + x * step;
            var wz = -_halfSize + z * step;
            var h = (float)terrainNode.Call("get_height_at", wx, wz).AsDouble();
            _heights[x, z] = h;
        }
    }

    /// <summary>
    /// Sample height at world X,Z. Bilinear-style clamp to grid. Safe from worker thread.
    /// </summary>
    public float SampleHeight(float worldX, float worldZ)
    {
        if (_heights == null) return 0;
        var u = (worldX + _halfSize) / TerrainSize;
        var v = (worldZ + _halfSize) / TerrainSize;
        u = Mathf.Clamp(u, 0, 1);
        v = Mathf.Clamp(v, 0, 1);
        var px = (int)(u * (Resolution - 1));
        var pz = (int)(v * (Resolution - 1));
        px = Mathf.Clamp(px, 0, Resolution - 1);
        pz = Mathf.Clamp(pz, 0, Resolution - 1);
        return _heights[px, pz];
    }
}
