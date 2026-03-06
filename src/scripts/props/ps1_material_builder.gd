extends RefCounted
## Creates PS1-style ShaderMaterial (vertex jitter, affine mapping). Preserves albedo texture and color.
## - create_from_material: build ShaderMaterial from BaseMaterial3D or fallback
## - apply_to_node: recursively replace mesh materials under node with PS1 variant

const PS1_SHADER := preload("res://shaders/ps1_style.gdshader")
const WHITE_TEXTURE := preload("res://assets/heightmaps/white_1x1.png")


## Build PS1 ShaderMaterial from original. Uses albedo_texture/albedo_color or WHITE_TEXTURE if missing.
static func create_from_material(original: Material) -> ShaderMaterial:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = PS1_SHADER

	var albedo_tex: Texture2D = null
	var albedo_col: Color = Color.WHITE

	if original and original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		albedo_tex = base.albedo_texture
		albedo_col = base.albedo_color
	elif original:
		# Fallback for other material types (e.g. some GLB imports)
		var tex = original.get("albedo_texture")
		if tex is Texture2D:
			albedo_tex = tex
		var col = original.get("albedo_color")
		if col is Color:
			albedo_col = col

	if albedo_tex:
		shader_mat.set_shader_parameter("albedo", albedo_tex)
	else:
		shader_mat.set_shader_parameter("albedo", WHITE_TEXTURE)
	shader_mat.set_shader_parameter("albedo_color", albedo_col)

	return shader_mat


## Recursively apply PS1 effect to all MeshInstance3D under node. Replaces surface materials with PS1 variant.
## If tint_color is not null, uses it as albedo_color (for species coloring); otherwise preserves original material color.
static func apply_to_node(node: Node, tint_color: Color = Color(1, 1, 1, 1)) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for surf_idx in mesh.get_surface_count():
				var orig_mat: Material = mi.get_surface_override_material(surf_idx)
				if not orig_mat:
					orig_mat = mesh.surface_get_material(surf_idx)
				var shader_mat := _create_ps1_material(orig_mat, tint_color)
				if shader_mat != null:
					mi.set_surface_override_material(surf_idx, shader_mat)
	for child in node.get_children():
		apply_to_node(child, tint_color)


## Internal: build PS1 ShaderMaterial. Uses tint_color as albedo_color (for species coloring).
static func _create_ps1_material(original: Material, tint_color: Color) -> ShaderMaterial:
	if not PS1_SHADER:
		return null
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = PS1_SHADER

	var albedo_tex: Texture2D = null
	if original and original is BaseMaterial3D:
		albedo_tex = (original as BaseMaterial3D).albedo_texture
	elif original:
		var tex = original.get("albedo_texture")
		if tex is Texture2D:
			albedo_tex = tex

	shader_mat.set_shader_parameter("albedo", albedo_tex if albedo_tex else WHITE_TEXTURE)
	shader_mat.set_shader_parameter("albedo_color", tint_color)
	return shader_mat
