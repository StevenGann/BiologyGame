using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for HeightmapSampler. Tests Initialize and SampleHeight behavior
/// without requiring Godot/Terrain3D (no SampleFromTerrain3D).
/// </summary>
public class HeightmapSamplerTests
{
    [Fact]
    public void BeforeInitialize_IsReady_IsFalse()
    {
        var sampler = new HeightmapSampler();
        Assert.False(sampler.IsReady);
    }

    [Fact]
    public void BeforeInitialize_SampleHeight_ReturnsZero()
    {
        var sampler = new HeightmapSampler();
        var h = sampler.SampleHeight(0, 0);
        Assert.Equal(0f, h);
    }

    [Fact]
    public void Initialize_SetsProperties()
    {
        var sampler = new HeightmapSampler();
        sampler.Initialize(
            resolution: 64,
            worldOriginX: 0,
            worldOriginZ: 0,
            worldSizeX: 1000,
            worldSizeZ: 1000);

        Assert.Equal(64, sampler.Resolution);
        Assert.Equal(0, sampler.WorldOriginX);
        Assert.Equal(0, sampler.WorldOriginZ);
        Assert.Equal(1000, sampler.WorldSizeX);
        Assert.Equal(1000, sampler.WorldSizeZ);
    }

    [Fact]
    public void AfterInitialize_IsReady_IsTrue()
    {
        var sampler = new HeightmapSampler();
        sampler.Initialize(4, 0, 0, 100, 100);
        Assert.True(sampler.IsReady);
    }

    [Fact]
    public void Initialize_WithOffsetOrigin_SetsCorrectly()
    {
        var sampler = new HeightmapSampler();
        sampler.Initialize(
            resolution: 8,
            worldOriginX: -4096,
            worldOriginZ: -4096,
            worldSizeX: 8192,
            worldSizeZ: 8192);

        Assert.Equal(-4096, sampler.WorldOriginX);
        Assert.Equal(-4096, sampler.WorldOriginZ);
        Assert.Equal(8192, sampler.WorldSizeX);
        Assert.Equal(8192, sampler.WorldSizeZ);
    }

    [Fact]
    public void SampleHeight_WhenNotPopulated_ReturnsZero()
    {
        var sampler = new HeightmapSampler();
        sampler.Initialize(4, 0, 0, 100, 100);
        var h = sampler.SampleHeight(50, 50);
        Assert.Equal(0f, h);
    }

    [Fact]
    public void SampleHeight_ClampsOutOfBounds()
    {
        var sampler = new HeightmapSampler();
        sampler.Initialize(4, 0, 0, 100, 100);
        var h = sampler.SampleHeight(10000, 10000);
        Assert.Equal(0f, h);
    }
}
