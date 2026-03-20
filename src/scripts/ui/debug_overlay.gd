extends Control
## Debug minimap overlay. Toggle with ~ (KEY_QUOTELEFT).
## Shows NxN grid by LOD tier, animal/plant dots, player position.

@export var redraw_interval_frames: int = 4

var _overlay_visible: bool = false
var _frame_counter: int = 0
var _bridge: Node
var _player: Node3D
var _snapshot: Array = []


func _ready() -> void:
	_process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_bridge = get_tree().get_first_node_in_group("sim_bridge")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if not _bridge:
		push_warning("DebugOverlay: SimSyncBridge not in group 'sim_bridge'")
	if not _player:
		push_warning("DebugOverlay: Player not in group 'player'")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_overlay"):
		_overlay_visible = not _overlay_visible
		visible = _overlay_visible

	if not _overlay_visible:
		return

	_frame_counter += 1
	if _frame_counter < redraw_interval_frames:
		return
	_frame_counter = 0

	_fetch_snapshot()
	queue_redraw()


func _fetch_snapshot() -> void:
	if _bridge and _bridge.has_method("GetSnapshotArray"):
		_snapshot = _bridge.call("GetSnapshotArray")


func _draw() -> void:
	var map_size := int(minf(size.x, size.y))
	if map_size <= 0:
		return
	var n := 32  # SimConfig.GridN
	var cell_w: float = float(map_size) / n
	var world_size: float = 8192.0  # SimConfig.WorldSizeXZ
	var world_origin_x: float = 0.0
	var world_origin_z: float = 0.0

	# Background
	draw_rect(Rect2(0, 0, map_size, map_size), Color(0.1, 0.1, 0.15, 0.9))

	# Player cell for LOD
	var player_cx: int = 0
	var player_cz: int = 0
	if _player:
		var px := _player.global_position.x
		var pz := _player.global_position.z
		player_cx = int(floor((px - world_origin_x) / (world_size / n)))
		player_cz = int(floor((pz - world_origin_z) / (world_size / n)))
		player_cx = clampi(player_cx, 0, n - 1)
		player_cz = clampi(player_cz, 0, n - 1)

	# Grid by LOD tier
	var tier_colors := [
		Color(0.2, 0.7, 0.2, 0.4),   # Tier 0 green
		Color(0.8, 0.8, 0.2, 0.3),   # Tier 1 yellow
		Color(0.9, 0.5, 0.2, 0.3),   # Tier 2 orange
		Color(0.9, 0.2, 0.2, 0.3),   # Tier 3 red
	]
	for cx in n:
		for cz in n:
			var tier := _get_lod_tier(cx, cz, player_cx, player_cz)
			var col: Color = tier_colors[tier] if tier < 4 else Color(0.15, 0.15, 0.2, 0.5)
			var rx := cx * cell_w
			var rz := cz * cell_w
			draw_rect(Rect2(rx, rz, cell_w, cell_w), col)
			draw_rect(Rect2(rx, rz, cell_w, cell_w), Color(0.3, 0.3, 0.4, 0.5), false, 1.0)

	# Entity dots from snapshot: [x, z, isAnimal, speciesId, ...]
	var i := 0
	var snap_size := _snapshot.size() if _snapshot else 0
	while i + 3 < snap_size:
		var x: float = float(_snapshot[i])
		var z: float = float(_snapshot[i + 1])
		var is_animal: bool = float(_snapshot[i + 2]) > 0.5
		var species_id: int = int(_snapshot[i + 3])
		i += 4

		var u := (x - world_origin_x) / world_size
		var v := (z - world_origin_z) / world_size
		u = clampf(u, 0.0, 1.0)
		v = clampf(v, 0.0, 1.0)
		var dot_x := u * map_size
		var dot_y := v * map_size

		var dot_color: Color
		if is_animal:
			dot_color = Color(0.3, 0.5, 1.0) if species_id == 0 else Color(0.9, 0.3, 0.2)
		else:
			dot_color = Color(0.2, 0.8, 0.4)
		draw_circle(Vector2(dot_x, dot_y), 2.0, dot_color)

	# Player dot (cyan)
	if _player:
		var px := _player.global_position.x
		var pz := _player.global_position.z
		var u := (px - world_origin_x) / world_size
		var v := (pz - world_origin_z) / world_size
		u = clampf(u, 0.0, 1.0)
		v = clampf(v, 0.0, 1.0)
		var map_x := u * map_size
		var map_y := v * map_size
		draw_circle(Vector2(map_x, map_y), 3.0, Color(0.0, 1.0, 1.0))


func _get_lod_tier(cx: int, cz: int, player_cx: int, player_cz: int) -> int:
	var dist := abs(cx - player_cx) + abs(cz - player_cz)
	if dist <= 2: return 0
	if dist <= 4: return 1
	if dist <= 8: return 2
	if dist <= 16: return 3
	return 4
