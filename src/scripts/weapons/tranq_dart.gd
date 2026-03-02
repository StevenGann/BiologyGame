extends Node3D
## Tranq dart visual. Instantiated by Player at raycast hit point. Parent is either hit animal (so dart follows)
## or World/TranqDarts (terrain hit). Applies PS1 effect to Model child in _ready.
## No gameplay logic; purely visual. Freed when parent is freed (e.g. animal defeated).

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	PS1MaterialBuilder.apply_to_node($Model)
