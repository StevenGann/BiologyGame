extends Node3D
## Renders far-LOD trees as camera-facing billboard quads via MultiMeshInstance3D.
## All tree variants share a single MultiMesh using a QuadMesh + tree_impostor.gdshader.
## Per-instance custom data (INSTANCE_CUSTOM.x) stores the atlas row for each instance
## so the shader can sample the correct variant row from the texture atlas.
##
## The impostor atlas texture must be pre-baked externally (one row per tree variant,
## front-facing view). Until an atlas is available, a solid-color fallback is used.
##
## Usage:
##   add_tree(pos, scale_size)   -- register a tree billboard
##   finalize()                  -- commit visible_instance_count
##
## Controlled by WorldChunkManager (per-chunk), activated when chunk is in the far band.

const IMPOSTOR_SHADER := preload("res://shaders/tree_impostor.gdshader")

## Distance beyond which the 3D MultiMesh is replaced by impostors.
@export var near_distance: float = 150.0
## Distance beyond which impostors are no longer rendered (matches PropMultimeshRenderer view_distance).
@export var far_distance: float = 600.0
@export var far_distance_margin: float = 30.0
## Optional baked atlas. If null, the shader uses a flat-color fallback.
@export var impostor_atlas: Texture2D = null
## Default quad width/height for a "unit" tree. Scaled per-instance via MultiMesh transform.
@export var quad_size: float = 1.0

const TREE_VARIANT_COUNT: int = 9

var _mmi: MultiMeshInstance3D = null
var _count: int = 0
## Pre-allocated capacity (set to chunk tree count at build time).
var _capacity: int = 0


func _ready() -> void:
	var config := get_node_or_null("/root/CullingConfig")
	if config:
		near_distance = config.get("impostor_near_distance")
		far_distance = config.get("impostor_far_distance")


## Call before add_tree to pre-allocate the MultiMesh buffer.
func init_capacity(count: int) -> void:
	_capacity = count
	_build_mmi()


## Add a single tree billboard at world position with given uniform scale.
## variant_idx selects the atlas row (0..TREE_VARIANT_COUNT-1).
func add_tree(pos: Vector3, scale_size: float, variant_idx: int = 0) -> void:
	if not _mmi:
		_build_mmi()
	if _count >= _mmi.multimesh.instance_count:
		_mmi.multimesh.instance_count += 1000
	# Store scale in the XZ diagonal of the Transform3D basis.
	var xform := Transform3D(Basis.IDENTITY.scaled(Vector3(scale_size, scale_size * 2.0, scale_size)), pos)
	_mmi.multimesh.set_instance_transform(_count, xform)
	# Pack atlas row into INSTANCE_CUSTOM (x = row, y/z/w unused).
	_mmi.multimesh.set_instance_custom_data(_count, Color(float(variant_idx), 0.0, 0.0, 0.0))
	_count += 1


## Call after all instances are added to set visible_instance_count.
func finalize() -> void:
	if _mmi:
		_mmi.multimesh.visible_instance_count = _count


func _build_mmi() -> void:
	if _mmi:
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true   ## Enables INSTANCE_CUSTOM in shader.
	mm.instance_count = maxi(_capacity, 64)
	mm.visible_instance_count = 0
	mm.mesh = quad

	var mat := ShaderMaterial.new()
	mat.shader = IMPOSTOR_SHADER
	mat.set_shader_parameter("atlas_rows", TREE_VARIANT_COUNT)
	mat.set_shader_parameter("albedo_color", Color.WHITE)
	if impostor_atlas:
		mat.set_shader_parameter("impostor_atlas", impostor_atlas)
	# (If no atlas, shader will sample an unset uniform which is black/transparent — acceptable.)

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visibility_range_begin = near_distance
	_mmi.visibility_range_begin_margin = 10.0
	_mmi.visibility_range_end = far_distance
	_mmi.visibility_range_end_margin = far_distance_margin
	add_child(_mmi)
