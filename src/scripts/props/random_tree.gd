extends StaticBody3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

## Preloaded tree models (DirAccess fails in export, so we preload for reliability).
const TREE_MODELS: Array[PackedScene] = [
	preload("res://assets/models/placeholders/trees/tree.glb"),
	preload("res://assets/models/placeholders/trees/tree-autumn.glb"),
	preload("res://assets/models/placeholders/trees/tree-autumn-tall.glb"),
	preload("res://assets/models/placeholders/trees/tree-crooked.glb"),
	preload("res://assets/models/placeholders/trees/tree-high.glb"),
	preload("res://assets/models/placeholders/trees/tree-high-crooked.glb"),
	preload("res://assets/models/placeholders/trees/tree-high-round.glb"),
	preload("res://assets/models/placeholders/trees/tree-tall.glb"),
	preload("res://assets/models/placeholders/trees/tree-trunk.glb"),
]

@export var model_scale: float = 3.5
@export var scale_variation: float = 0.5
@export var use_ps1_effect: bool = true


func _ready() -> void:
	_spawn_model()


func _apply_ps1_with_original_colors(node: Node) -> void:
	PS1MaterialBuilder.apply_to_node(node)


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
	if TREE_MODELS.is_empty():
		return

	var pos := global_position
	var seed_val := int(hash(Vector3i(int(pos.x), int(pos.y), int(pos.z))))
	seed(seed_val)
	var idx := randi() % TREE_MODELS.size()
	var scale_mult := 2.0 + randf_range(-scale_variation, scale_variation)

	var model := TREE_MODELS[idx].instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale * scale_mult
	add_child(model)
	if use_ps1_effect:
		_apply_ps1_with_original_colors(model)

	_create_trimesh_collision(model)
