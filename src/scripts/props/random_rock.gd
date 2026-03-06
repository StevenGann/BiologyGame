extends Node3D
## Placeholder rock prop. On _ready: picks random model, applies PS1 effect.
## Physics (collision) is created only when player is near (via PropPhysicsManager).

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

const ROCK_MODELS: Array[PackedScene] = [
	preload("res://assets/models/placeholders/terrain/rock-a.glb"),
	preload("res://assets/models/placeholders/terrain/rock-b.glb"),
	preload("res://assets/models/placeholders/terrain/rock-c.glb"),
	preload("res://assets/models/placeholders/terrain/rock-large.glb"),
	preload("res://assets/models/placeholders/terrain/rock-small.glb"),
	preload("res://assets/models/placeholders/terrain/rock-wide.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeA.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeB.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeC.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeD.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeE.glb"),
	preload("res://assets/models/placeholders/terrain/rock_largeF.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallA.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallB.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallC.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallD.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallE.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallF.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallG.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallH.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallI.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallFlatA.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallFlatB.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallFlatC.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallTopA.glb"),
	preload("res://assets/models/placeholders/terrain/rock_smallTopB.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallA.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallB.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallC.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallD.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallE.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallF.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallG.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallH.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallI.glb"),
	preload("res://assets/models/placeholders/terrain/rock_tallJ.glb"),
	preload("res://assets/models/placeholders/terrain/rocks-large.glb"),
	preload("res://assets/models/placeholders/terrain/rocks-medium.glb"),
	preload("res://assets/models/placeholders/terrain/rocks-small.glb"),
]

@export var model_scale: float = 2.5
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
	if ROCK_MODELS.is_empty():
		return

	var pos := global_position
	var seed_val := int(hash(Vector3i(int(pos.x), int(pos.y), int(pos.z))))
	seed(seed_val)
	var idx := randi() % ROCK_MODELS.size()
	var scale_mult := 1.0 + randf_range(-scale_variation, scale_variation)

	_model = ROCK_MODELS[idx].instantiate() as Node3D
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
