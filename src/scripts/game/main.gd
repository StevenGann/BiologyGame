extends Node

## Ensures the Player and its camera are active when the game starts.
## Manages posterize post-processing and SubViewport sizing.


func _ready() -> void:
	call_deferred("_ensure_camera")
	_setup_posterize()
	_update_viewport_size()
	get_viewport().size_changed.connect(_update_viewport_size)


func _setup_posterize() -> void:
	var viewport := get_node_or_null("GameViewport") as SubViewport
	var posterize_rect := get_node_or_null("PosterizeLayer/PosterizeRect") as TextureRect
	if viewport and posterize_rect:
		posterize_rect.texture = viewport.get_texture()


func _update_viewport_size() -> void:
	var viewport := get_node_or_null("GameViewport") as SubViewport
	if viewport:
		viewport.size = get_viewport().get_visible_rect().size


func _ensure_camera() -> void:
	var game_viewport := get_node_or_null("GameViewport")
	var player := game_viewport.get_node_or_null("Player") if game_viewport else null
	if player == null:
		push_error("Main: Player node not found. Check that res://scenes/player/player.tscn loads correctly.")
		return

	var camera: Camera3D = player.get_node_or_null("Camera3D")
	if camera == null:
		push_error("Main: Camera3D not found in Player scene.")
		return

	camera.current = true

	# Spawn player on terrain so they don't fall through (terrain collision is one-sided)
	var world := game_viewport.get_node_or_null("World") if game_viewport else null
	var terrain := world.get_node_or_null("TestTerrain") if world else null
	if terrain and terrain.has_method("get_height_at"):
		var height: float = terrain.get_height_at(0.0, 0.0)
		player.global_position = Vector3(0, height + 1.0, 0)
