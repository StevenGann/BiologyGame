extends Node3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")


func _ready() -> void:
	_apply_ps1_to_model($Model)


func _apply_ps1_to_model(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for surf_idx in mesh.get_surface_count():
				var orig_mat := mesh.surface_get_material(surf_idx)
				if orig_mat:
					var shader_mat := PS1MaterialBuilder.create_from_material(orig_mat)
					mi.set_surface_override_material(surf_idx, shader_mat)
	for child in node.get_children():
		_apply_ps1_to_model(child)
