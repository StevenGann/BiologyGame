extends Node3D
## Placeholder tree prop. On _ready: picks random model, applies PS1 effect.
## Physics (collision) is created only when player is near (via PropPhysicsManager).

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

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
@export var view_distance: float = 400.0
@export var view_distance_margin: float = 20.0

var physics_active: bool = false
var _model: Node3D
var _cached_collision_shape: Shape3D = null


func _ready() -> void:
	_spawn_model()


func _apply_ps1_with_original_colors(node: Node) -> void:
	PS1MaterialBuilder.apply_to_node(node)


func _create_trimesh_shape_from_model(model: Node3D) -> Shape3D:
	var all_faces: PackedVector3Array = []
	_collect_mesh_faces(model, all_faces)
	if all_faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(all_faces)
	return shape


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

	_model = TREE_MODELS[idx].instantiate() as Node3D
	_model.scale = Vector3.ONE * model_scale * scale_mult
	add_child(_model)
	if use_ps1_effect:
		_apply_ps1_with_original_colors(_model)

	_apply_visibility_range_to_meshes(_model)


func activate_physics() -> void:
	if physics_active:
		return
	if not _model:
		return
	if get_node_or_null("PhysicsBody"):
		physics_active = true
		return

	var body := StaticBody3D.new()
	body.name = "PhysicsBody"
	body.collision_layer = 2
	body.collision_mask = 0

	var shape: Shape3D
	if _cached_collision_shape:
		shape = _cached_collision_shape
	else:
		shape = _create_trimesh_shape_from_model(_model)
		if shape:
			_cached_collision_shape = shape

	if shape:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D.IDENTITY
		body.add_child(col)

	add_child(body)
	physics_active = true


func deactivate_physics() -> void:
	if not physics_active:
		return
	var body := get_node_or_null("PhysicsBody")
	if body:
		remove_child(body)
		body.queue_free()
	physics_active = false


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
