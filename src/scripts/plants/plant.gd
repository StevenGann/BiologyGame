extends StaticBody3D
## Minimal Plant type for Forager animals to eat.
## When consumed, health decrements; when depleted, plant is freed.

signal plant_depleted

@export var max_health: int = 3
@export var use_ps1_effect: bool = true

var health: int

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	add_to_group("plants")
	health = max_health
	if use_ps1_effect and has_node("Model"):
		PS1MaterialBuilder.apply_to_node($Model)


## Called by Forager when eating. Returns true if plant was consumed (still has health).
func consume() -> bool:
	if health <= 0:
		return false
	health -= 1
	if health <= 0:
		plant_depleted.emit()
		queue_free()
		return false
	return true


func is_consumed() -> bool:
	return health <= 0
