extends StaticBody3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

@export var models_folder: String = "res://assets/models/placeholders/trees/"
@export var model_scale: float = 3.5
@export var scale_variation: float = 0.5
@export var use_ps1_effect: bool = true

var _model_scenes: Array[PackedScene] = []


func _ready() -> void:
	_load_models()
	_spawn_model()


func _load_models() -> void:
	var dir := DirAccess.open(models_folder)
	if dir == null:
		push_error("RandomTree: Cannot open folder: %s" % models_folder)
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".glb") and not dir.current_is_dir():
			var scene := load(models_folder.path_join(file)) as PackedScene
			if scene:
				_model_scenes.append(scene)
		file = dir.get_next()
	dir.list_dir_end()


func _apply_ps1_with_original_colors(node: Node) -> void:
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
		_apply_ps1_with_original_colors(child)


func _create_trimesh_collision(model: Node3D) -> void:
	var all_faces: PackedVector3Array = []
	_collect_mesh_faces(model, all_faces)
	if all_faces.is_empty():
		return

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(all_faces)

	var col_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape:
		col_shape.shape = shape
		col_shape.transform = Transform3D.IDENTITY


func _collect_mesh_faces(node: Node3D, faces: PackedVector3Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			var mesh_faces := mesh.get_faces()
			var xform := global_transform.affine_inverse() * mesh_instance.global_transform
			for i in mesh_faces.size():
				faces.append(xform * mesh_faces[i])
	for child in node.get_children():
		if child is Node3D:
			_collect_mesh_faces(child as Node3D, faces)


func _spawn_model() -> void:
	if _model_scenes.is_empty():
		return

	var pos := global_position
	var seed_val := int(hash(Vector3i(int(pos.x), int(pos.y), int(pos.z))))
	seed(seed_val)
	var idx := randi() % _model_scenes.size()
	var scale_mult := 2.0 + randf_range(-scale_variation, scale_variation)

	var model := _model_scenes[idx].instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale * scale_mult
	add_child(model)
	if use_ps1_effect:
		_apply_ps1_with_original_colors(model)

	_create_trimesh_collision(model)
