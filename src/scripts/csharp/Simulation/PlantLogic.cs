using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Pure C# logic for plant behavior. No Godot APIs; safe for worker thread.
/// Handles regrowth and respawn (consumed plants gradually recover).
/// Consumption is performed by animal processing when herbivores eat; this class only handles growth.
/// </summary>
public static class PlantLogic
{
    /// <summary>
    /// Update plant state: regrowth when not fully healthy, respawn when consumed.
    /// </summary>
    /// <param name="delta">Time step.</param>
    /// <param name="plant">Plant state (modified in place).</param>
    public static void Update(float delta, ref PlantStateData plant)
    {
        if (plant.Health >= plant.MaxHealth)
        {
            plant.RegrowthAccumulator = 0f;
            return;
        }

        var rate = plant.Health <= 0 ? SimConfig.PlantRespawnRate : SimConfig.PlantRegrowthRate;
        plant.RegrowthAccumulator += delta * rate;

        while (plant.RegrowthAccumulator >= 1f && plant.Health < plant.MaxHealth)
        {
            plant.Health++;
            plant.RegrowthAccumulator -= 1f;
        }

        if (plant.Health >= plant.MaxHealth)
            plant.RegrowthAccumulator = 0f;
    }
}
