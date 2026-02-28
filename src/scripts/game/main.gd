extends Node3D

## Ensures the Player and its camera are active when the game starts.
## If the Player fails to load, this helps surface the issue.


func _ready() -> void:
	call_deferred("_ensure_camera")


func _ensure_camera() -> void:
	var player := get_node_or_null("Player")
	if player == null:
		push_error("Main: Player node not found. Check that res://scenes/player/player.tscn loads correctly.")
		return

	var camera: Camera3D = player.get_node_or_null("Camera3D")
	if camera == null:
		push_error("Main: Camera3D not found in Player scene.")
		return

	camera.current = true
