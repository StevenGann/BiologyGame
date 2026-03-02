using System.Collections.Generic;
using Godot;
using BiologyGame.Simulation;

namespace BiologyGame.Animals;

/// <summary>
/// Base class for all animals. Provides wandering, panic-from-threat, contagion (panic spread),
/// and cohesion (flocking) behaviors. Integrates with SimulationManager (GDScript) for LOD
/// and spatial queries. Supports FAR LOD via ProcessFarTick and state export for async sim.
/// </summary>
public partial class AnimalBase : CharacterBody3D
{
	/// <summary>LOD tier constant: full simulation (&lt; 30m from player).</summary>
	public const int LODTierFull = 0;
	/// <summary>LOD tier constant: medium simulation (30–90m).</summary>
	public const int LODTierMedium = 1;
	/// <summary>LOD tier constant: far simulation (&gt; 90m).</summary>
	public const int LODTierFar = 2;

	/// <summary>Emitted when health reaches zero (defeated). Used for XP/loot hooks.</summary>
	[Signal]
	public delegate void AnimalDefeatedEventHandler();

	/// <summary>High-level behavior state.</summary>
	public enum State
	{
		Wandering,
		Panicking
	}

	/// <summary>Species ID. Must match species_constants.gd for GDScript compatibility.</summary>
	public enum Species
	{
		Bison = 0,
		Deer = 1,
		Rabbit = 2,
		Wolf = 3,
		Bear = 4
	}

	/// <summary>Species type. Used for cohesion/contagion and scene instantiation.</summary>
	[Export] public Species species { get; set; } = Species.Bison;
	[Export] public bool UsePs1Effect { get; set; } = true;
	[Export] public int MaxHealth { get; set; } = 2;
	[Export] public float WanderSpeed { get; set; } = 0.8f;
	[Export] public float PanicSpeed { get; set; } = 4.0f;
	[Export] public float WanderRadius { get; set; } = 8.0f;
	[Export] public float DetectionRange { get; set; } = 6.0f;
	[Export] public float PanicDuration { get; set; } = 3.0f;
	[Export] public float WanderPauseMin { get; set; } = 1.0f;
	[Export] public float WanderPauseMax { get; set; } = 4.0f;
	/// <summary>0–1. Affects contagion and cohesion strength.</summary>
	[Export(PropertyHint.Range, "0,1")] public float SocialFactor { get; set; } = 0.5f;

	[ExportGroup("Debug LOD Label")]
	[Export] public float DebugLabelHeight { get; set; } = 2.5f;
	[Export] public int DebugLabelFontSize { get; set; } = 72;
	/// <summary>Radius for cohesion (move toward same-species center).</summary>
	[Export] public float CohesionRadius { get; set; } = 12.0f;
	/// <summary>Radius for contagion (panic spread from nearby panicking same-species).</summary>
	[Export] public float ContagionRadius { get; set; } = 10.0f;

	public int Health { get; set; }
	/// <summary>True when animal was in FAR LOD last frame (for terrain re-snap on promote).</summary>
	public bool WasFarLod { get; set; }

	protected State _state = State.Wandering;
	protected Vector3 _wanderTarget;
	protected float _wanderTimer;
	protected float _panicTimer;
	protected Vector3 _threatPosition;
	private Node _cachedSimManager;
	private int _cachedInstanceId;
	private Godot.Collections.Array _cachedNearby = new();
	private long _cachedNearbyFrame = -1;
	private bool _skipSocialThisFrame;
	private float _accumulatedAiDelta;
	private float _accumulatedMoveDelta;
	private Label3D _debugLabel;
	protected MeshInstance3D _debugMeshInstance;
	private static readonly RandomNumberGenerator _rng = new();

	/// <summary>True when in Panicking state.</summary>
	public bool IsPanicking => _state == State.Panicking;

	public override void _Ready()
	{
		AddToGroup("animals");
		Health = MaxHealth;
		if (UsePs1Effect && HasNode("Model"))
		{
			var model = GetNode<Node3D>("Model");
			ApplyPs1ToNode(model);
		}
		PickNewWanderTarget();
		_wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
		SetupDebugLabel();
		SetupDebugMesh();
		_cachedInstanceId = (int)GetInstanceId();
	}

	private void ApplyPs1ToNode(Node node)
	{
		var script = GD.Load<GDScript>("res://scripts/props/ps1_material_builder.gd");
		script.Call("apply_to_node", node);
	}

	private void SetupDebugLabel()
	{
		_debugLabel = new Label3D
		{
			Position = new Vector3(0, DebugLabelHeight, 0),
			Billboard = BaseMaterial3D.BillboardModeEnum.Enabled,
			Modulate = Colors.Yellow,
			FontSize = DebugLabelFontSize,
			Visible = false
		};
		AddChild(_debugLabel);
	}

	private void SetupDebugMesh()
	{
		_debugMeshInstance = new MeshInstance3D { Visible = false };
		AddChild(_debugMeshInstance);
	}

	protected virtual string GetDebugStateString()
	{
		return _state switch
		{
			State.Wandering => "Wander",
			State.Panicking => "Panic",
			_ => "?"
		};
	}

	protected virtual string GetDebugSpeciesString()
	{
		return species switch
		{
			Species.Bison => "Bison",
			Species.Deer => "Deer",
			Species.Rabbit => "Rabbit",
			Species.Wolf => "Wolf",
			Species.Bear => "Bear",
			_ => "?"
		};
	}

	public override void _PhysicsProcess(double delta)
	{
		var d = (float)delta;
		var gravity = (float)ProjectSettings.GetSetting("physics/3d/default_gravity");
		var vel = Velocity;
		vel.Y += -gravity * d;
		Velocity = vel;

		_accumulatedAiDelta += d;
		_accumulatedMoveDelta += d;

		var sim = GetSimManager();
		if (sim != null)
		{
			var pos = GlobalPosition;
			var lod = (int)sim.Call("get_lod_tier", pos).AsInt32();
			var aiTick = sim.Call("should_ai_tick_this_frame", lod, _cachedInstanceId).AsBool();
			var moveTick = sim.Call("should_movement_tick_this_frame", lod, _cachedInstanceId).AsBool();

			if (lod == LODTierFull)
			{
				if (aiTick)
				{
					_skipSocialThisFrame = false;
					UpdateNearbyCache();
					UpdateState(_accumulatedAiDelta);
					_accumulatedAiDelta = 0;
				}
				if (moveTick)
				{
					ApplyMovement(_accumulatedMoveDelta);
					_accumulatedMoveDelta = 0;
				}
			}
			else if (lod == LODTierMedium)
			{
				if (aiTick)
				{
					_skipSocialThisFrame = true;
					UpdateState(_accumulatedAiDelta);
					_accumulatedAiDelta = 0;
				}
				if (moveTick)
				{
					ApplyMovementSimple(_accumulatedMoveDelta);
					_accumulatedMoveDelta = 0;
				}
			}
			UpdateDebugLabel(sim);
		}
		else
		{
			_skipSocialThisFrame = false;
			UpdateNearbyCache();
			UpdateState(d);
			ApplyMovement(d);
			_accumulatedAiDelta = 0;
			_accumulatedMoveDelta = 0;
		}

		MoveAndSlide();
	}

	private void UpdateDebugLabel(Node sim)
	{
		if (_debugLabel == null) return;
		var debugMode = sim.Get("debug_mode").AsBool();
		if (!debugMode)
		{
			_debugLabel.Visible = false;
			if (_debugMeshInstance != null) _debugMeshInstance.Visible = false;
			return;
		}
		var lod = (int)sim.Call("get_lod_tier", GlobalPosition).AsInt32();
		if (lod == LODTierFull || lod == LODTierMedium)
		{
			_debugLabel.Visible = true;
			var lodStr = lod == LODTierFull ? "Full" : "Medium";
			var parts = new Godot.Collections.Array { lodStr };
			if (sim.Get("debug_show_state").AsBool()) parts.Add(GetDebugStateString());
			if (sim.Get("debug_show_species").AsBool()) parts.Add(GetDebugSpeciesString());
			if (sim.Get("debug_show_panic_timer").AsBool() && _state == State.Panicking)
				parts.Add($"{_panicTimer:F1}s");
			var strs = new System.Collections.Generic.List<string>();
			foreach (Variant v in parts) strs.Add(v.AsString());
			_debugLabel.Text = string.Join(" | ", strs);
			UpdateDebugVisuals(sim);
		}
		else
		{
			_debugLabel.Visible = false;
			if (_debugMeshInstance != null) _debugMeshInstance.Visible = false;
		}
	}

	protected virtual void UpdateDebugVisuals(Node sim)
	{
		if (_debugMeshInstance == null || sim == null || !sim.Get("debug_mode").AsBool()) return;
		_debugMeshInstance.Visible = true;
		var imesh = new ImmediateMesh();
		const int segs = 24;
		var origin = Vector3.Zero;

		if (sim.Get("debug_show_threat_line").AsBool() && _state == State.Panicking)
		{
			var mat = MakeDebugMaterial(Colors.Red);
			imesh.SurfaceBegin(Mesh.PrimitiveType.Lines, mat);
			imesh.SurfaceAddVertex(origin);
			imesh.SurfaceAddVertex(ToLocal(_threatPosition));
			imesh.SurfaceEnd();
		}

		if (sim.Get("debug_show_cohesion_line").AsBool())
		{
			var center = GetCohesionCenter();
			if (center != null)
			{
				var mat = MakeDebugMaterial(Colors.Green);
				imesh.SurfaceBegin(Mesh.PrimitiveType.Lines, mat);
				imesh.SurfaceAddVertex(origin);
				imesh.SurfaceAddVertex(ToLocal(center.Value));
				imesh.SurfaceEnd();
			}
		}

		if (sim.Get("debug_show_detection_radii").AsBool())
		{
			var detMat = MakeDebugMaterial(Colors.Yellow);
			imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, detMat);
			for (var i = 0; i <= segs; i++)
			{
				var a = Mathf.Tau * (float)i / segs;
				imesh.SurfaceAddVertex(origin + new Vector3(Mathf.Cos(a) * DetectionRange, 0, Mathf.Sin(a) * DetectionRange));
			}
			imesh.SurfaceEnd();
			var cohMat = MakeDebugMaterial(Colors.Cyan);
			imesh.SurfaceBegin(Mesh.PrimitiveType.LineStrip, cohMat);
			for (var i = 0; i <= segs; i++)
			{
				var a = Mathf.Tau * (float)i / segs;
				imesh.SurfaceAddVertex(origin + new Vector3(Mathf.Cos(a) * CohesionRadius, 0, Mathf.Sin(a) * CohesionRadius));
			}
			imesh.SurfaceEnd();
		}

		if (sim.Get("debug_show_nearby_species").AsBool())
		{
			var nearby = GetNearbySameSpecies();
			var cohRadiusSq = CohesionRadius * CohesionRadius;
			var started = false;
			var mat = MakeDebugMaterial(Colors.White);
			foreach (Node a in nearby)
			{
				if (a == this) continue;
				var other = a as Node3D;
				if (other == null) continue;
				var distSq = GlobalPosition.DistanceSquaredTo(other.GlobalPosition);
				if (distSq < cohRadiusSq && distSq > 0.0001f)
				{
					if (!started) { started = true; imesh.SurfaceBegin(Mesh.PrimitiveType.Lines, mat); }
					imesh.SurfaceAddVertex(origin);
					imesh.SurfaceAddVertex(ToLocal(other.GlobalPosition));
				}
			}
			if (started) imesh.SurfaceEnd();
		}

		_debugMeshInstance.Mesh = imesh;
	}

	protected static StandardMaterial3D MakeDebugMaterial(Color col)
	{
		return new StandardMaterial3D
		{
			ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
			AlbedoColor = col
		};
	}

	/// <summary>Called by player raycast or hunter. Reduces health and triggers panic from threat position.</summary>
	public void TakeDamage(int amount)
	{
		Health -= amount;
		var player = GetPlayer();
		var threatPos = player != null ? player.GlobalPosition : GlobalPosition + (-GlobalTransform.Basis.Z * 2.0f);
		PanicFromPosition(threatPos);
		if (Health <= 0) Defeat();
	}

	private void Defeat()
	{
		EmitSignal(SignalName.AnimalDefeated);
		QueueFree();
	}

	/// <summary>Override in subclasses. Updates threat detection, contagion, and state timers.</summary>
	protected virtual void UpdateState(float delta)
	{
		UpdateThreats(delta);
		ApplyContagion(delta);
		if (_state == State.Panicking)
		{
			_panicTimer -= delta;
			if (_panicTimer <= 0)
			{
				_state = State.Wandering;
				PickNewWanderTarget();
				_wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
			}
		}
	}

	/// <summary>Override in subclasses. Check for player/hunter and call PanicFromPosition if detected.</summary>
	protected virtual void UpdateThreats(float delta)
	{
		var player = GetPlayer();
		if (player != null && GlobalPosition.DistanceTo(player.GlobalPosition) < DetectionRange)
			PanicFromPosition(player.GlobalPosition);
	}

	protected void ApplyContagion(float delta)
	{
		if (_skipSocialThisFrame || SocialFactor <= 0) return;
		var nearby = GetNearbySameSpecies();
		var panickingCount = 0;
		CharacterBody3D nearestPanicked = null;
		var nearestPanickedDistSq = ContagionRadius * ContagionRadius;
		foreach (Node a in nearby)
		{
			if (a == this) continue;
			var other = a as AnimalBase;
			if (other == null || !other.IsPanicking) continue;
			panickingCount++;
			var dSq = GlobalPosition.DistanceSquaredTo(other.GlobalPosition);
			if (dSq < nearestPanickedDistSq)
			{
				nearestPanickedDistSq = dSq;
				nearestPanicked = other;
			}
		}
		if (_state == State.Wandering && panickingCount > 0 && nearestPanicked != null)
		{
			var baseChance = 0.15f * delta;
			if (GD.Randf() < SocialFactor * baseChance * panickingCount)
				PanicFromPosition(nearestPanicked.GlobalPosition);
		}
		else if (_state == State.Panicking && panickingCount == 0 && nearby.Count > 0)
		{
			var calmChance = 0.2f * delta * SocialFactor;
			if (GD.Randf() < calmChance)
				_panicTimer -= PanicDuration * 0.2f;
		}
	}

	private void ApplyMovementSimple(float delta)
	{
		if (_state == State.Panicking)
		{
			var away = (GlobalPosition - _threatPosition).Normalized();
			away.Y = 0;
			if (away.LengthSquared() > 0.01f)
			{
				var vel = Velocity;
				vel.X = away.X * PanicSpeed;
				vel.Z = away.Z * PanicSpeed;
				Velocity = vel;
				LookAt(GlobalPosition + new Vector3(vel.X, 0, vel.Z), Vector3.Up);
			}
		}
		else if (_state == State.Wandering)
		{
			if (_wanderTimer > 0)
			{
				_wanderTimer -= delta;
				var vel = Velocity;
				vel.X = Mathf.MoveToward(vel.X, 0, WanderSpeed * 2);
				vel.Z = Mathf.MoveToward(vel.Z, 0, WanderSpeed * 2);
				Velocity = vel;
			}
			else
			{
				var toTarget = _wanderTarget - GlobalPosition;
				toTarget.Y = 0;
				if (toTarget.Length() < 0.5f)
				{
					PickNewWanderTarget();
					_wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
					var vel = Velocity;
					vel.X = 0; vel.Z = 0;
					Velocity = vel;
				}
				else
				{
					var dir = toTarget.Normalized();
					var vel = Velocity;
					vel.X = dir.X * WanderSpeed;
					vel.Z = dir.Z * WanderSpeed;
					Velocity = vel;
					LookAt(GlobalPosition + dir, Vector3.Up);
				}
			}
		}
	}

	/// <summary>Override in subclasses. Applies velocity based on state (wander/panic) and cohesion.</summary>
	protected virtual void ApplyMovement(float delta)
	{
		var cohesion = GetSocialCohesionVector();
		if (_state == State.Panicking)
		{
			var away = (GlobalPosition - _threatPosition).Normalized();
			away.Y = 0;
			if (away.LengthSquared() > 0.01f)
			{
				var vel = Velocity;
				vel.X = away.X * PanicSpeed;
				vel.Z = away.Z * PanicSpeed;
				ApplyCohesionToVelocity(ref vel, cohesion);
				Velocity = vel;
				LookAt(GlobalPosition + new Vector3(vel.X, 0, vel.Z), Vector3.Up);
			}
		}
		else if (_state == State.Wandering)
		{
			if (_wanderTimer > 0)
			{
				_wanderTimer -= delta;
				var vel = Velocity;
				vel.X = Mathf.MoveToward(vel.X, 0, WanderSpeed * 2);
				vel.Z = Mathf.MoveToward(vel.Z, 0, WanderSpeed * 2);
				Velocity = vel;
			}
			else
			{
				var toTarget = _wanderTarget - GlobalPosition;
				toTarget.Y = 0;
				if (toTarget.Length() < 0.5f)
				{
					PickNewWanderTarget();
					_wanderTimer = (float)GD.RandRange(WanderPauseMin, WanderPauseMax);
					var vel = Velocity;
					vel.X = 0; vel.Z = 0;
					Velocity = vel;
				}
				else
				{
					var dir = toTarget.Normalized();
					var vel = Velocity;
					vel.X = dir.X * WanderSpeed;
					vel.Z = dir.Z * WanderSpeed;
					ApplyCohesionToVelocity(ref vel, cohesion);
					Velocity = vel;
					LookAt(GlobalPosition + dir, Vector3.Up);
				}
			}
		}
	}

	protected void PanicFromPosition(Vector3 pos)
	{
		_state = State.Panicking;
		_threatPosition = pos;
		_panicTimer = PanicDuration;
	}

	protected void PickNewWanderTarget()
	{
		var offset = new Vector3(
			(float)GD.RandRange(-WanderRadius, WanderRadius),
			0,
			(float)GD.RandRange(-WanderRadius, WanderRadius)
		);
		_wanderTarget = GlobalPosition + offset;
	}

	/// <summary>
	/// Called by SimulationManager (GDScript) for FAR LOD animals when physics_process is disabled.
	/// Uses AnimalLogic (no Godot APIs) so logic is shared with FarAnimalSim worker thread.
	/// </summary>
	/// <param name="delta">Frame delta.</param>
	/// <param name="aiTick">Whether to run AI update this frame.</param>
	/// <param name="moveTick">Whether to run movement this frame.</param>
	public void ProcessFarTick(double delta, bool aiTick, bool moveTick)
	{
		var d = (float)delta;
		_accumulatedAiDelta += d;
		_accumulatedMoveDelta += d;
		var state = ToStateData();
		var neighbors = GetNeighborsForFarLogic();
		if (aiTick)
		{
			_skipSocialThisFrame = false;
			AnimalLogic.UpdateStateFar(_accumulatedAiDelta, ref state, neighbors);
			FromStateData(state);
			_accumulatedAiDelta = 0;
		}
		if (moveTick)
		{
			var cohesion = ComputeCohesionFromNeighbors(neighbors);
			AnimalLogic.ApplySimpleWander(_accumulatedMoveDelta, ref state, cohesion);
			FromStateData(state);
			_accumulatedMoveDelta = 0;
		}
		var vel = Velocity;
		vel.Y = 0;
		Velocity = vel;
		var pos = GlobalPosition;
		pos.X += vel.X * d;
		pos.Z += vel.Z * d;
		GlobalPosition = pos;
	}

	private AnimalStateData ToStateData()
	{
		return new AnimalStateData
		{
			Position = GlobalPosition,
			Velocity = Velocity,
			State = _state == State.Panicking ? 1 : 0,
			Species = (int)species,
			Health = Health,
			PanicTimer = _panicTimer,
			WanderTimer = _wanderTimer,
			WanderTarget = _wanderTarget,
			ThreatPosition = _threatPosition,
			WanderSpeed = WanderSpeed,
			PanicSpeed = PanicSpeed,
			SocialFactor = SocialFactor,
			CohesionRadius = CohesionRadius,
			ContagionRadius = ContagionRadius,
			PanicDuration = PanicDuration,
			WanderPauseMin = WanderPauseMin,
			WanderPauseMax = WanderPauseMax,
			WanderRadius = WanderRadius
		};
	}

	private void FromStateData(AnimalStateData s)
	{
		_state = s.State == 1 ? State.Panicking : State.Wandering;
		_panicTimer = s.PanicTimer;
		_wanderTimer = s.WanderTimer;
		_wanderTarget = s.WanderTarget;
		_threatPosition = s.ThreatPosition;
		Velocity = s.Velocity;
	}

	private List<(Vector3 Pos, int State)> GetNeighborsForFarLogic()
	{
		var nearby = GetNearbySameSpecies();
		var list = new List<(Vector3, int)>();
		var maxRangeSq = Mathf.Max(CohesionRadius, ContagionRadius) + 5.0f;
		maxRangeSq *= maxRangeSq;
		foreach (Node a in nearby)
		{
			if (a == this) continue;
			var other = a as AnimalBase;
			if (other == null) continue;
			var pos = other.GlobalPosition;
			if (GlobalPosition.DistanceSquaredTo(pos) > maxRangeSq) continue;
			list.Add((pos, other.IsPanicking ? 1 : 0));
		}
		return list;
	}

	/// <summary>
	/// Export full state for demotion to FarAnimalSim. Called by FarSimBridge on main thread.
	/// </summary>
	public Simulation.AnimalStateData ExportStateData()
	{
		return ToStateData();
	}

	/// <summary>
	/// Restore state when promoted from FarAnimalSim. Caller must set GlobalPosition with terrain height.
	/// </summary>
	public void ApplyStateData(Simulation.AnimalStateData s)
	{
		Health = s.Health;
		FromStateData(s);
	}

	private Vector3 ComputeCohesionFromNeighbors(List<(Vector3 Pos, int State)> neighbors)
	{
		if (SocialFactor <= 0 || neighbors.Count == 0) return Vector3.Zero;
		var center = Vector3.Zero;
		var count = 0;
		var cohRadiusSq = CohesionRadius * CohesionRadius;
		foreach (var (pos, _) in neighbors)
		{
			var distSq = GlobalPosition.DistanceSquaredTo(pos);
			if (distSq < cohRadiusSq && distSq > 0.0001f)
			{
				center += pos;
				count++;
			}
		}
		if (count <= 0) return Vector3.Zero;
		center /= count;
		var toCenter = center - GlobalPosition;
		toCenter.Y = 0;
		if (toCenter.LengthSquared() < 0.01f) return Vector3.Zero;
		return toCenter.Normalized() * SocialFactor * WanderSpeed * 0.5f;
	}

	protected Node GetSimManager()
	{
		if (_cachedSimManager == null || !GodotObject.IsInstanceValid(_cachedSimManager))
			_cachedSimManager = GetTree().GetFirstNodeInGroup("simulation_manager") as Node;
		return _cachedSimManager;
	}

	private void UpdateNearbyCache()
	{
		var fc = GetTree().GetFrame();
		if (_cachedNearbyFrame != fc)
		{
			_cachedNearbyFrame = fc;
			_cachedNearby = FetchNearbySameSpecies();
		}
	}

	private Godot.Collections.Array GetNearbySameSpecies()
	{
		var fc = GetTree().GetFrame();
		if (_cachedNearbyFrame == fc) return _cachedNearby;
		_cachedNearbyFrame = fc;
		_cachedNearby = FetchNearbySameSpecies();
		return _cachedNearby;
	}

	private Godot.Collections.Array FetchNearbySameSpecies()
	{
		var maxRange = Mathf.Max(CohesionRadius, ContagionRadius) + 5.0f;
		var sim = GetSimManager();
		if (sim != null && sim.HasMethod("get_same_species_in_radius"))
		{
			var result = sim.Call("get_same_species_in_radius", GlobalPosition, maxRange, (int)species, this);
			return result.AsGodotArray();
		}
		var arr = new Godot.Collections.Array();
		var parent = GetParent();
		if (parent == null) return arr;
		var maxRangeSq = maxRange * maxRange;
		foreach (Node child in parent.GetChildren())
		{
			if (child is not CharacterBody3D other || other == this) continue;
			if (child is AnimalBase ab && ab.species != species) continue;
			if (child.Get("species").VariantType != Variant.Type.Int) continue;
			if ((int)child.Get("species").AsInt32() != (int)species) continue;
			if (GlobalPosition.DistanceSquaredTo(other.GlobalPosition) <= maxRangeSq)
				arr.Add(other);
		}
		return arr;
	}

	private Vector3? GetCohesionCenter()
	{
		var nearby = GetNearbySameSpecies();
		if (nearby.Count == 0) return null;
		var center = Vector3.Zero;
		var count = 0;
		var cohRadiusSq = CohesionRadius * CohesionRadius;
		foreach (Node a in nearby)
		{
			if (a == this) continue;
			var other = a as Node3D;
			if (other == null) continue;
			var distSq = GlobalPosition.DistanceSquaredTo(other.GlobalPosition);
			if (distSq < cohRadiusSq && distSq > 0.0001f) { center += other.GlobalPosition; count++; }
		}
		if (count <= 0) return null;
		return center / count;
	}

	protected Vector3 GetSocialCohesionVector()
	{
		if (SocialFactor <= 0) return Vector3.Zero;
		var nearby = GetNearbySameSpecies();
		if (nearby.Count == 0) return Vector3.Zero;
		var center = Vector3.Zero;
		var count = 0;
		var cohRadiusSq = CohesionRadius * CohesionRadius;
		foreach (Node a in nearby)
		{
			if (a == this) continue;
			var other = a as Node3D;
			if (other == null) continue;
			var distSq = GlobalPosition.DistanceSquaredTo(other.GlobalPosition);
			if (distSq < cohRadiusSq && distSq > 0.0001f) { center += other.GlobalPosition; count++; }
		}
		if (count <= 0) return Vector3.Zero;
		center /= count;
		var toCenter = center - GlobalPosition;
		toCenter.Y = 0;
		if (toCenter.LengthSquared() < 0.01f) return Vector3.Zero;
		return toCenter.Normalized() * SocialFactor * WanderSpeed * 0.5f;
	}

	protected void ApplyCohesionToVelocity(ref Vector3 vel, Vector3 cohesion)
	{
		if (cohesion.LengthSquared() < 0.0001f) return;
		vel.X += cohesion.X;
		vel.Z += cohesion.Z;
		var flat = new Vector3(vel.X, 0, vel.Z);
		var speed = flat.Length();
		var maxSpeed = _state == State.Panicking ? PanicSpeed : WanderSpeed;
		if (speed > maxSpeed)
		{
			flat = flat.Normalized() * maxSpeed;
			vel.X = flat.X;
			vel.Z = flat.Z;
		}
	}

	private Node3D GetPlayer() => GetTree().GetFirstNodeInGroup("player") as Node3D;
}
