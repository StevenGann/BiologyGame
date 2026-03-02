extends StaticBody3D
## Placeholder rock prop. On _ready: picks random model from ROCK_MODELS by position-based seed,
## instantiates with scale variation, applies PS1 effect, builds trimesh collision from mesh.

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")

## Preloaded rock models. Preload used because DirAccess can fail in export.
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


## Pick random rock by position-seeded RNG, instantiate, scale, apply PS1, create collision.
func _spawn_model() -> void:
	if ROCK_MODELS.is_empty():
		return

	var pos := global_position
	var seed_val := int(hash(Vector3i(int(pos.x), int(pos.y), int(pos.z))))
	seed(seed_val)
	var idx := randi() % ROCK_MODELS.size()
	var scale_mult := 1.0 + randf_range(-scale_variation, scale_variation)

	var model := ROCK_MODELS[idx].instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale * scale_mult
	add_child(model)
	if use_ps1_effect:
		_apply_ps1_with_original_colors(model)

	_create_trimesh_collision(model)
