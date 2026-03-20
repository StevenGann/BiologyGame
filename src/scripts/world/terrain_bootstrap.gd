extends Node3D
## Ensures Terrain3D uses the game camera and logs diagnostic info when the scene loads.
## Attach to the parent of the Terrain3D node (e.g. WorldTerrain).

@export var enable_debug_logs: bool = false

var _terrain: Node
var _camera_set: bool = false


func _ready() -> void:
	_terrain = _find_terrain3d(self)
	if not _terrain:
		push_error("TerrainBootstrap: No Terrain3D child found")
		return

	_log_terrain_status()

	if enable_debug_logs and _terrain.get("debug_level") != null:
		_terrain.set("debug_level", 2)  # 2 = Info

	call_deferred("_set_camera_once")


func _process(_delta: float) -> void:
	if _camera_set:
		return
	_set_camera_once()


func _find_terrain3d(node: Node) -> Node:
	if node.get_class() == "Terrain3D":
		return node
	for child in node.get_children():
		var found := _find_terrain3d(child)
		if found:
			return found
	return null


func _set_camera_once() -> void:
	if _camera_set or not _terrain:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and _terrain.has_method("set_camera"):
		_terrain.set_camera(cam)
		_camera_set = true


func _log_terrain_status() -> void:
	var data_dir: String = _terrain.get("data_directory") if _terrain.get("data_directory") != null else ""
	print("[TerrainBootstrap] data_directory = ", data_dir)

	if data_dir.is_empty():
		push_warning("[TerrainBootstrap] Terrain3D data_directory is empty - no regions will load")
		return

	if not DirAccess.dir_exists_absolute(data_dir):
		push_error("[TerrainBootstrap] Directory does not exist: ", data_dir)
		return

	var dir := DirAccess.open(data_dir)
	if not dir:
		push_error("[TerrainBootstrap] Cannot open directory: ", data_dir)
		return

	var files: PackedStringArray = dir.get_files()
	var region_count: int = 0
	for f in files:
		if f.begins_with("terrain3d") and f.ends_with(".res"):
			region_count += 1

	print("[TerrainBootstrap] Files in directory: ", files.size(), " | Region files (terrain3d*.res): ", region_count)
	if region_count == 0:
		push_warning("[TerrainBootstrap] No terrain3d*.res region files found. Run the importer and save to this directory.")
