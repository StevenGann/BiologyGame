extends Control
## Debug minimap overlay. Toggle with F1 or ` (backtick/~).
##
## Shows 32×32 sim grid by LOD tier (green/yellow/orange/red), animal/plant dots,
## and player position. Data from SimSyncBridge.GetSnapshotArray().
##
## Optimizations: SubViewport at internal_resolution, throttled redraws,
## capped dots with uniform sampling, 1px rects for speed.
## SimSyncBridge reuses snapshot buffer to avoid GC pressure.

@export var redraw_interval_frames: int = 48  ## Frames between redraws (default ~0.8s at 60 FPS)
@export var max_dots_to_draw: int = 1500  ## Cap on entity dots; excess is uniformly sampled
@export var internal_resolution: int = 256  ## Draw resolution; viewport stretches to fill Minimap

var _overlay_visible: bool = false
var _frame_counter: int = 0
var _bridge: Node  ## SimSyncBridge (group "sim_bridge")
var _player: Node3D  ## FPSPlayer (group "player")
var _snapshot: Array = []  ## Packed [x, z, isAnimal, speciesId, ...] from C#
var _draw_control: Control  ## Inner Control in SubViewport that performs _draw


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("debug_overlay")

	_bridge = get_tree().get_first_node_in_group("sim_bridge")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_draw_control = $SubViewportContainer/SubViewport/DrawControl
	var vp: SubViewport = $SubViewportContainer/SubViewport
	if vp:
		vp.size = Vector2i(internal_resolution, internal_resolution)
	# With stretch=true, SubViewportContainer will resize viewport to fill; we draw at internal_resolution capped by viewport size
	if not _bridge:
		push_warning("DebugOverlay: SimSyncBridge not in group 'sim_bridge'")
	if not _player:
		push_warning("DebugOverlay: Player not in group 'player'")
	if not _draw_control:
		push_warning("DebugOverlay: DrawControl not found at SubViewportContainer/SubViewport/DrawControl")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_F1 or key_event.keycode == KEY_QUOTELEFT:
				_overlay_visible = not _overlay_visible
				visible = _overlay_visible
				get_viewport().set_input_as_handled()


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
	_update_draw_control()
	if _draw_control:
		_draw_control.queue_redraw()


func _fetch_snapshot() -> void:
	if _bridge and _bridge.has_method("GetSnapshotArray"):
		_snapshot = _bridge.call("GetSnapshotArray")


func _update_draw_control() -> void:
	if not _draw_control:
		return
	_draw_control.set_meta("snapshot", _snapshot)
	var px: float = _player.global_position.x if _player else 0.0
	var pz: float = _player.global_position.z if _player else 0.0
	_draw_control.set_meta("player_x", px)
	_draw_control.set_meta("player_z", pz)
	_draw_control.set_meta("internal_resolution", internal_resolution)
	_draw_control.set_meta("max_dots_to_draw", max_dots_to_draw)
	var grid_n: int = 16 if internal_resolution <= 128 else 32
	_draw_control.set_meta("grid_n", grid_n)
	if _bridge and _bridge.has_method("GetDebugMapWorldOriginX"):
		_draw_control.set_meta("world_origin_x", float(_bridge.call("GetDebugMapWorldOriginX")))
		_draw_control.set_meta("world_origin_z", float(_bridge.call("GetDebugMapWorldOriginZ")))
		_draw_control.set_meta("world_size_xz", float(_bridge.call("GetDebugMapWorldSizeXZ")))
	else:
		_draw_control.set_meta("world_origin_x", -4096.0)
		_draw_control.set_meta("world_origin_z", -4096.0)
		_draw_control.set_meta("world_size_xz", 8192.0)
