extends Node3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	PS1MaterialBuilder.apply_to_node($Model)
