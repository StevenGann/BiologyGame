extends StaticBody3D
## Consumable plant for ForagerAnimal. Foragers call consume() when eating.
## - consume() decrements health; returns true while still edible
## - When health reaches 0: emit plant_depleted, queue_free
## - is_consumed() returns true when depleted (filtered from spatial queries)

signal plant_depleted  ## Emitted when health reaches 0 (before queue_free)

@export var max_health: int = 3
@export var use_ps1_effect: bool = true
@export var view_distance: float = 400.0  ## Distance beyond which plant is not rendered
@export var view_distance_margin: float = 20.0  ## Hysteresis to avoid pop-in

var health: int

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	add_to_group("plants")
	health = max_health
	if use_ps1_effect and has_node("Model"):
		PS1MaterialBuilder.apply_to_node($Model)
	if has_node("Model"):
		_apply_visibility_range_to_meshes($Model)


func _apply_visibility_range_to_meshes(node: Node) -> void:
	var config := get_node_or_null("/root/CullingConfig")
	var vd: float = config.get("prop_view_distance") if config else view_distance
	var vdm: float = config.get("prop_view_distance_margin") if config else view_distance_margin
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.visibility_range_end = vd
		mi.visibility_range_end_margin = vdm
	for child in node.get_children():
		_apply_visibility_range_to_meshes(child)


## Called by ForagerAnimal when eating. Decrements health. Returns true if still has health after decrement.
func consume() -> bool:
	if health <= 0:
		return false
	health -= 1
	if health <= 0:
		plant_depleted.emit()
		queue_free()
		return false
	return true


## Returns true when health <= 0 (plant no longer available for eating).
func is_consumed() -> bool:
	return health <= 0
