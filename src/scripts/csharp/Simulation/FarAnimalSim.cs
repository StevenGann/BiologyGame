using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace BiologyGame.Simulation;

/// <summary>
/// Async FAR animal simulation. Runs on a background worker thread at 20 Hz.
/// No Godot API calls; uses AnimalStateData, AnimalLogic, FarSpatialGrid, HeightmapSampler.
/// Demote adds animals; promotion enqueues when within promote radius of player (set by FarSimBridge).
/// </summary>
public class FarAnimalSim
{
    private const int InitialCapacity = 512;

    private AnimalStateData[] _animals;
    private int _count;
    private readonly FarSpatialGrid _grid = new();
    private readonly List<(Vector3 Pos, int State)> _neighborBuffer = new();
    private readonly List<int> _sameSpeciesBuffer = new();
    [ThreadStatic] private static List<int> _threadSameSpecies;
    private readonly HeightmapSampler _heightmap;

    private volatile bool _running;
    private Thread _workerThread;
    private readonly ConcurrentQueue<AnimalStateData> _demoteQueue = new();
    private readonly ConcurrentQueue<(int Index, AnimalStateData State)> _promoteQueue = new();
    private Vector3 _playerPos;
    private float _accumulatedDelta;
    private readonly float _promoteRadiusSq;

    public FarAnimalSim(HeightmapSampler heightmap, float promoteRadius)
    {
        _heightmap = heightmap;
        _promoteRadiusSq = promoteRadius * promoteRadius;
        _animals = new AnimalStateData[InitialCapacity];
    }

    public int Count => _count;

    /// <summary>Enqueue an animal demoted from scene. Worker adds to _animals on next tick.</summary>
    public void Demote(AnimalStateData state)
    {
        _demoteQueue.Enqueue(state);
    }

    /// <summary>Dequeue next animal to promote. Main thread polls periodically (e.g. every 20s).</summary>
    public bool TryGetPromote(out int index, out AnimalStateData state)
    {
        if (_promoteQueue.TryDequeue(out var pair))
        {
            index = pair.Index;
            state = pair.State;
            return true;
        }
        index = -1;
        state = default;
        return false;
    }

    private readonly object _removeLock = new();

    private void RemoveAtIndices(int[] indices)
    {
        if (indices == null || indices.Length == 0) return;
        Array.Sort(indices, (a, b) => b.CompareTo(a)); // descending
        lock (_removeLock)
        {
            foreach (var index in indices)
            {
                if (index < 0 || index >= _count) continue;
                _count--;
                if (index < _count)
                    Array.Copy(_animals, index + 1, _animals, index, _count - index);
            }
        }
    }

    /// <summary>Push player position and accumulated delta. Called every physics frame from FarSimBridge.</summary>
    public void PushInput(Vector3 playerPos, float delta)
    {
        _playerPos = playerPos;
        _accumulatedDelta += delta;
    }

    public void Start()
    {
        if (_running) return;
        _running = true;
        _workerThread = new Thread(WorkerLoop) { IsBackground = true };
        _workerThread.Start();
    }

    public void Stop()
    {
        _running = false;
        _workerThread?.Join(500);
    }

    private void WorkerLoop()
    {
        const float tickRate = 1f / 20f; // 20 Hz
        var accumulated = 0f;

        while (_running)
        {
            accumulated += _accumulatedDelta;
            _accumulatedDelta = 0;

            // Process demotes
            while (_demoteQueue.TryDequeue(out var state))
            {
                if (_count >= _animals.Length)
                {
                    var next = new AnimalStateData[_animals.Length * 2];
                    Array.Copy(_animals, next, _count);
                    _animals = next;
                }
                _animals[_count++] = state;
            }

            // Tick
            while (accumulated >= tickRate)
            {
                accumulated -= tickRate;
                Tick(tickRate);
            }

            Thread.Sleep(10);
        }
    }

    private void Tick(float delta)
    {
        if (_count == 0) return;

        _grid.Rebuild(_animals, _count);

        // AISystem - single-threaded (contagion reads neighbor states, so parallel would race)
        for (var i = 0; i < _count; i++)
        {
            var state = _animals[i];
            _neighborBuffer.Clear();
            var maxRange = Mathf.Max(state.CohesionRadius, state.ContagionRadius) + 5f;
            _grid.GetSameSpeciesInRadius(state.Position, maxRange, state.Species, i, _sameSpeciesBuffer);
            foreach (var j in _sameSpeciesBuffer)
                _neighborBuffer.Add((_animals[j].Position, _animals[j].State));
            AnimalLogic.UpdateStateFar(delta, ref state, _neighborBuffer);
            _animals[i] = state;
        }

        // MovementSystem - parallel (cohesion reads Position; Position not written until end of loop,
        // so all reads see previous-tick positions - safe)
        Parallel.For(0, _count, i =>
        {
            var state = _animals[i];
            var cohesion = ComputeCohesion(i, ref state);
            AnimalLogic.ApplySimpleWander(delta, ref state, cohesion);
            state.Position.X += state.Velocity.X * delta;
            state.Position.Z += state.Velocity.Z * delta;
            if (_heightmap != null)
                state.Position.Y = _heightmap.SampleHeight(state.Position.X, state.Position.Z) + 0.3f;
            _animals[i] = state;
        });

        // Promotion check: distance to player < promote radius
        var toPromote = new List<int>();
        for (var i = 0; i < _count; i++)
        {
            var distSq = _playerPos.DistanceSquaredTo(_animals[i].Position);
            if (distSq < _promoteRadiusSq)
            {
                _promoteQueue.Enqueue((i, _animals[i]));
                toPromote.Add(i);
            }
        }
        if (toPromote.Count > 0)
            RemoveAtIndices(toPromote.ToArray());
    }

    private Vector3 ComputeCohesion(int index, ref AnimalStateData state)
    {
        if (state.SocialFactor <= 0) return Vector3.Zero;
        var buf = _threadSameSpecies ??= new List<int>();
        _grid.GetSameSpeciesInRadius(state.Position, state.CohesionRadius, state.Species, index, buf);
        if (buf.Count == 0) return Vector3.Zero;
        var center = Vector3.Zero;
        var count = 0;
        var cohRadiusSq = state.CohesionRadius * state.CohesionRadius;
        foreach (var j in buf)
        {
            var pos = _animals[j].Position;
            var distSq = state.Position.DistanceSquaredTo(pos);
            if (distSq < cohRadiusSq && distSq > 0.0001f)
            {
                center += pos;
                count++;
            }
        }
        if (count <= 0) return Vector3.Zero;
        center /= count;
        var toCenter = center - state.Position;
        toCenter.Y = 0;
        if (toCenter.LengthSquared() < 0.01f) return Vector3.Zero;
        return toCenter.Normalized() * state.SocialFactor * state.WanderSpeed * 0.5f;
    }
}
