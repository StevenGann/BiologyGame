extends RefCounted
## Builds a PS1-style ShaderMaterial that preserves the original material's texture and colors.

const PS1_SHADER := preload("res://shaders/ps1_style.gdshader")


static func create_from_material(original: Material) -> ShaderMaterial:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = PS1_SHADER

	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		if base.albedo_texture:
			shader_mat.set_shader_parameter("albedo", base.albedo_texture)
		shader_mat.set_shader_parameter("albedo_color", base.albedo_color)

	return shader_mat
