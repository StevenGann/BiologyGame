using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pre-baked height grid for worker-thread-safe sampling. Main thread populates via
/// SampleFromTerrain3D (calls terrain.data.get_height). Worker uses SampleHeight (no Godot APIs).
/// </summary>
public class HeightmapSampler
{
    public float WorldOriginX { get; private set; }
    public float WorldOriginZ { get; private set; }
    public float WorldSizeX { get; private set; }
    public float WorldSizeZ { get; private set; }
    public int Resolution { get; private set; }

    private float[,] _heights = new float[0, 0];
    private float _stepX;
    private float _stepZ;

    /// <summary>
    /// Allocate grid. Call before SampleFromTerrain3D.
    /// </summary>
    /// <param name="resolution">Grid resolution (e.g. 128 or 256).</param>
    /// <param name="worldOriginX">World X of min corner (e.g. 0 or -halfExtent).</param>
    /// <param name="worldOriginZ">World Z of min corner.</param>
    /// <param name="worldSizeX">World extent in X (m).</param>
    /// <param name="worldSizeZ">World extent in Z (m).</param>
    public void Initialize(
        int resolution,
        float worldOriginX,
        float worldOriginZ,
        float worldSizeX,
        float worldSizeZ)
    {
        Resolution = resolution;
        WorldOriginX = worldOriginX;
        WorldOriginZ = worldOriginZ;
        WorldSizeX = worldSizeX;
        WorldSizeZ = worldSizeZ;
        _heights = new float[resolution, resolution];
        _stepX = worldSizeX / Mathf.Max(1, resolution - 1);
        _stepZ = worldSizeZ / Mathf.Max(1, resolution - 1);
    }

    /// <summary>
    /// Call from main thread only. Samples Terrain3D via terrain.data.get_height at grid points.
    /// </summary>
    /// <param name="terrainNode">Terrain3D node (has "data" property with get_height(Vector3)).</param>
    public void SampleFromTerrain3D(Node terrainNode)
    {
        if (_heights == null || _heights.Length == 0) return;

        var dataVar = terrainNode.Get("data");
        if (dataVar.VariantType == Variant.Type.Nil || dataVar.VariantType == Variant.Type.Object && dataVar.AsGodotObject() == null)
        {
            GD.PrintErr("HeightmapSampler: Terrain3D has no data property");
            return;
        }

        var dataObj = dataVar.AsGodotObject();
        if (dataObj == null || !dataObj.HasMethod("get_height"))
        {
            GD.PrintErr("HeightmapSampler: Terrain3D.data has no get_height method");
            return;
        }

        for (var z = 0; z < Resolution; z++)
        for (var x = 0; x < Resolution; x++)
        {
            var wx = WorldOriginX + x * _stepX;
            var wz = WorldOriginZ + z * _stepZ;
            var pos = new Vector3(wx, 0, wz);
            var h = (float)dataObj.Call("get_height", pos).AsDouble();
            _heights[x, z] = h;
        }
    }

    /// <summary>
    /// Sample height at world X,Z. Bilinear-style clamp to grid. Safe from worker thread.
    /// </summary>
    public float SampleHeight(float worldX, float worldZ)
    {
        if (_heights == null || _heights.Length == 0) return 0f;

        var u = (worldX - WorldOriginX) / Mathf.Max(0.001f, WorldSizeX);
        var v = (worldZ - WorldOriginZ) / Mathf.Max(0.001f, WorldSizeZ);
        u = Mathf.Clamp(u, 0f, 1f);
        v = Mathf.Clamp(v, 0f, 1f);

        var px = (int)(u * (Resolution - 1));
        var pz = (int)(v * (Resolution - 1));
        px = Mathf.Clamp(px, 0, Resolution - 1);
        pz = Mathf.Clamp(pz, 0, Resolution - 1);

        return _heights[px, pz];
    }

    /// <summary>
    /// Whether the sampler has been initialized and populated.
    /// </summary>
    public bool IsReady => _heights != null && _heights.Length > 0;
}
