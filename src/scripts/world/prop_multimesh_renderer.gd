extends Node3D
## GPU-instanced rendering for static props (trees, rocks) via MultiMeshInstance3D.
## One MultiMeshInstance3D per mesh variant. All instances of a variant are batched into a
## single draw call. Replaces individual tree/rock scene node instantiation.
##
## Usage:
##   add_tree_instance(variant_idx, xform) -> instance assigned into variant's MultiMesh slot
##   add_rock_instance(variant_idx, xform) -> same for rocks
##   finalize() -> call after all instances added (locks visible_instance_count)

const PS1_SHADER := preload("res://shaders/ps1_style.gdshader")
const WHITE_TEXTURE := preload("res://assets/heightmaps/white_1x1.png")

const TREE_SCENES: Array[PackedScene] = [
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

const ROCK_SCENES: Array[PackedScene] = [
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

## Per-variant capacity headroom factor (allocate this many times the expected average).
## Prevents reallocation when variant distribution is uneven.
const CAPACITY_HEADROOM: float = 1.6

## Maximum total trees/rocks this renderer can hold. Set to expected max world size.
@export var tree_capacity: int = 1100000
@export var rock_capacity: int = 1100000
@export var view_distance: float = 400.0
@export var view_distance_margin: float = 20.0
## Shadow casting for near props (impostors should use SHADOW_CASTING_SETTING_OFF).
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = \
	GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## One MultiMeshInstance3D per tree variant.
var _tree_mmis: Array[MultiMeshInstance3D] = []
## One MultiMeshInstance3D per rock variant.
var _rock_mmis: Array[MultiMeshInstance3D] = []
## How many instances have been added to each tree variant.
var _tree_counts: Array[int] = []
## How many instances have been added to each rock variant.
var _rock_counts: Array[int] = []


func _ready() -> void:
	var config := get_node_or_null("/root/CullingConfig")
	if config:
		view_distance = config.get("prop_view_distance")
		view_distance_margin = config.get("prop_view_distance_margin")
		var near_shadow: bool = config.get("prop_near_cast_shadow")
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_setup_multimeshes(TREE_SCENES, _tree_mmis, _tree_counts, tree_capacity)
	_setup_multimeshes(ROCK_SCENES, _rock_mmis, _rock_counts, rock_capacity)


## Add a single tree instance. variant_idx must be in [0, TREE_SCENES.size()).
## xform is the world-space Transform3D for this instance (position + rotation + scale).
func add_tree_instance(variant_idx: int, xform: Transform3D) -> void:
	_add_instance(_tree_mmis, _tree_counts, variant_idx, xform)


## Add a single rock instance. variant_idx must be in [0, ROCK_SCENES.size()).
func add_rock_instance(variant_idx: int, xform: Transform3D) -> void:
	_add_instance(_rock_mmis, _rock_counts, variant_idx, xform)


## Number of tree variants (convenience for callers picking variant_idx).
func tree_variant_count() -> int:
	return TREE_SCENES.size()


## Number of rock variants.
func rock_variant_count() -> int:
	return ROCK_SCENES.size()


## Call after populating all instances to flush visible_instance_count on each MultiMesh.
func finalize() -> void:
	for i in _tree_mmis.size():
		var mmi := _tree_mmis[i]
		if mmi:
			mmi.multimesh.visible_instance_count = _tree_counts[i]
	for i in _rock_mmis.size():
		var mmi := _rock_mmis[i]
		if mmi:
			mmi.multimesh.visible_instance_count = _rock_counts[i]


## Free all MultiMesh nodes (used by chunk manager when unloading a chunk).
func clear() -> void:
	for mmi in _tree_mmis:
		if mmi:
			mmi.queue_free()
	for mmi in _rock_mmis:
		if mmi:
			mmi.queue_free()
	_tree_mmis.clear()
	_rock_mmis.clear()
	_tree_counts.clear()
	_rock_counts.clear()


func _setup_multimeshes(
	scenes: Array[PackedScene],
	mmis: Array[MultiMeshInstance3D],
	counts: Array[int],
	total_capacity: int
) -> void:
	var per_variant_capacity := int(ceil(float(total_capacity) / scenes.size() * CAPACITY_HEADROOM))
	for scene in scenes:
		var mesh := _extract_mesh(scene)
		if not mesh:
			mmis.append(null)
			counts.append(0)
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = per_variant_capacity
		mm.visible_instance_count = 0
		mm.mesh = mesh

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = view_distance
		mmi.visibility_range_end_margin = view_distance_margin
		mmi.cast_shadow = cast_shadow
		_apply_ps1_materials(mmi, mesh, scene)
		add_child(mmi)

		mmis.append(mmi)
		counts.append(0)


func _add_instance(
	mmis: Array[MultiMeshInstance3D],
	counts: Array[int],
	variant_idx: int,
	xform: Transform3D
) -> void:
	if variant_idx < 0 or variant_idx >= mmis.size():
		return
	var mmi := mmis[variant_idx]
	if not mmi:
		return
	var slot := counts[variant_idx]
	var mm := mmi.multimesh
	if slot >= mm.instance_count:
		# Over capacity — extend (rare, triggers GPU buffer realloc)
		mm.instance_count = mm.instance_count + 1000
	mm.set_instance_transform(slot, xform)
	counts[variant_idx] = slot + 1
	mm.visible_instance_count = slot + 1


## Instantiate scene temporarily (off-screen) to extract the first Mesh resource found.
## The scene is immediately freed; only the Mesh (GPU resource) is retained.
func _extract_mesh(scene: PackedScene) -> Mesh:
	var inst := scene.instantiate()
	var mesh := _find_first_mesh(inst)
	inst.queue_free()
	return mesh


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _find_first_mesh(child)
		if m:
			return m
	return null


## Apply PS1 ShaderMaterial to each surface of the MultiMeshInstance3D.
## Reads the original albedo texture from the GLB's surface materials.
func _apply_ps1_materials(mmi: MultiMeshInstance3D, mesh: Mesh, scene: PackedScene) -> void:
	# Instantiate scene to read original materials from the MeshInstance3D.
	var inst := scene.instantiate()
	var source_mi := _find_first_mesh_instance(inst)

	for surf_idx in mesh.get_surface_count():
		var orig_mat: Material = null
		if source_mi:
			orig_mat = source_mi.get_surface_override_material(surf_idx)
			if not orig_mat:
				orig_mat = mesh.surface_get_material(surf_idx)
		else:
			orig_mat = mesh.surface_get_material(surf_idx)

		var albedo_tex: Texture2D = null
		if orig_mat is BaseMaterial3D:
			albedo_tex = (orig_mat as BaseMaterial3D).albedo_texture
		elif orig_mat:
			var tex = orig_mat.get("albedo_texture")
			if tex is Texture2D:
				albedo_tex = tex

		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = PS1_SHADER
		shader_mat.set_shader_parameter("albedo", albedo_tex if albedo_tex else WHITE_TEXTURE)
		shader_mat.set_shader_parameter("albedo_color", Color.WHITE)
		mmi.set_surface_override_material(surf_idx, shader_mat)

	inst.queue_free()


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var mi := _find_first_mesh_instance(child)
		if mi:
			return mi
	return null
