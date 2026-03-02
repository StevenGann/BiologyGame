extends StaticBody3D
## Consumable plant for ForagerAnimal. Foragers call consume() when eating.
## - consume() decrements health; returns true while still edible
## - When health reaches 0: emit plant_depleted, queue_free
## - is_consumed() returns true when depleted (filtered from spatial queries)

signal plant_depleted  ## Emitted when health reaches 0 (before queue_free)

@export var max_health: int = 3
@export var use_ps1_effect: bool = true

var health: int

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	add_to_group("plants")
	health = max_health
	if use_ps1_effect and has_node("Model"):
		PS1MaterialBuilder.apply_to_node($Model)


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
