using Xunit;
using BiologyGame.Simulation;

namespace BiologyGame.Tests.Simulation;

/// <summary>
/// Unit tests for SimConfig.
/// </summary>
public class SimConfigTests
{
    [Fact]
    public void GridN_IsPositive()
    {
        Assert.True(SimConfig.GridN > 0);
    }

    [Fact]
    public void CellSizeMeters_MatchesWorldSizeOverGridN()
    {
        var expected = SimConfig.WorldSizeXZ / SimConfig.GridN;
        Assert.Equal(expected, SimConfig.CellSizeMeters);
    }

    [Fact]
    public void LODThresholds_AreOrdered()
    {
        Assert.True(SimConfig.LOD_A_Cells <= SimConfig.LOD_B_Cells);
        Assert.True(SimConfig.LOD_B_Cells <= SimConfig.LOD_C_Cells);
        Assert.True(SimConfig.LOD_C_Cells <= SimConfig.LOD_D_Cells);
    }

    [Fact]
    public void TransferInterval_IsPositive()
    {
        Assert.True(SimConfig.TransferIntervalSeconds > 0);
    }

    [Fact]
    public void WorldSizeXZ_IsPositive()
    {
        Assert.True(SimConfig.WorldSizeXZ > 0);
    }

    [Fact]
    public void HalfExtentXZ_IsHalfOfWorldSize()
    {
        Assert.Equal(SimConfig.WorldSizeXZ * 0.5f, SimConfig.HalfExtentXZ);
    }

    [Fact]
    public void ThreadPoolSize_IsPositive()
    {
        Assert.True(SimConfig.ThreadPoolSize > 0);
    }
}
