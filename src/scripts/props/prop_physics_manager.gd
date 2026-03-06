extends Node
## Manages distance-based physics activation for trees and rocks.
## Only props within activate_radius get physics bodies; beyond deactivate_radius they are removed.
## Throttles updates to avoid spikes when the player moves.

@export var activate_radius: float = 60.0  ## Enable physics when player is within this distance
@export var deactivate_radius: float = 80.0  ## Disable physics when player is beyond this (hysteresis)
@export var props_per_frame: int = 80  ## Max activate + deactivate operations per frame

var _props_node: Node3D
var _player: Node3D
var _process_index: int = 0
var _prop_list: Array[Node] = []


func _ready() -> void:
	_props_node = get_parent().get_node_or_null("TestTerrain/Props")
	if not _props_node:
		push_error("PropPhysicsManager: TestTerrain/Props not found")
	var config := get_node_or_null("/root/CullingConfig")
	if config:
		activate_radius = config.get("prop_physics_activate_radius")
		deactivate_radius = config.get("prop_physics_deactivate_radius")


func _physics_process(_delta: float) -> void:
	if not _props_node:
		return
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if not _player:
			return

	var player_pos := _player.global_position
	var activate_sq := activate_radius * activate_radius
	var deactivate_sq := deactivate_radius * deactivate_radius

	# Refresh prop list periodically (props spawn incrementally)
	if _process_index % 256 == 0:
		_prop_list.clear()
		for c in _props_node.get_children():
			if c.has_method("activate_physics") and c.has_method("deactivate_physics"):
				_prop_list.append(c)

	if _prop_list.is_empty():
		return

	var budget := props_per_frame
	var start := _process_index % _prop_list.size()
	var i := 0

	while budget > 0 and i < _prop_list.size():
		var idx := (start + i) % _prop_list.size()
		var prop = _prop_list[idx]
		i += 1

		if not is_instance_valid(prop):
			continue

		var dist_sq := player_pos.distance_squared_to(prop.global_position)
		var active: bool = prop.get("physics_active")

		if not active and dist_sq < activate_sq:
			prop.activate_physics()
			prop.set("physics_active", true)
			budget -= 1
		elif active and dist_sq > deactivate_sq:
			prop.deactivate_physics()
			prop.set("physics_active", false)
			budget -= 1

	_process_index += 1
