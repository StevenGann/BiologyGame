extends Node3D
## Terrain with elevation derived from a grayscale image. Brighter pixels = higher elevation.
## - Uses trimesh collision (exact mesh alignment) for physics
## - If heightmap_path empty: generates procedural simplex noise heightmap
## - Exposes get_height_at(world_x, world_z) for spawning and animal placement
## - Child "Ground" StaticBody3D holds mesh and collision

@export var heightmap_path: String = ""  ## Empty = procedural noise
@export var terrain_size: float = 100.0  ## World size (X and Z extent)
@export var height_min: float = -2.0  ## Elevation range
@export var height_max: float = 8.0
@export var resolution: int = 128  ## Grid resolution for procedural heightmap

@export var ground_material: Material  ## Applied to terrain mesh; heightmap displacement disabled for baked mesh

var _heightmap_image: Image
var _map_width: int
var _map_depth: int

# Cached for get_height_at()
var _height_scale: float
var _terrain_half: float


func _ready() -> void:
	_setup_heightmap()
	_height_scale = height_max - height_min
	_terrain_half = terrain_size * 0.5
	_build_terrain()


## Load heightmap from file or generate procedural. Sets _heightmap_image, _map_width, _map_depth.
func _setup_heightmap() -> void:
	if heightmap_path.is_empty():
		_generate_procedural_heightmap()
		return
	# Use ResourceLoader (not FileAccess.file_exists) so export works: packed resources
	# are remapped (e.g. PNG -> .ctex) and file_exists can return false incorrectly.
	_load_heightmap_from_file()


## Generate simplex FBM noise as grayscale image when heightmap_path is empty.
func _generate_procedural_heightmap() -> void:
	_map_width = resolution
	_map_depth = resolution
	_heightmap_image = Image.create(_map_width, _map_depth, false, Image.FORMAT_R8)

	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.02

	for z in _map_depth:
		for x in _map_width:
			var nx := (x / float(_map_width)) * 2.0 - 1.0
			var nz := (z / float(_map_depth)) * 2.0 - 1.0
			var n := noise.get_noise_2d(nx * 50, nz * 50)
			n = (n + 1.0) * 0.5  # remap -1..1 to 0..1
			_heightmap_image.set_pixel(x, z, Color(n, n, n, 1.0))


## Load heightmap image from heightmap_path via ResourceLoader (export-safe).
func _load_heightmap_from_file() -> void:
	var tex := ResourceLoader.load(heightmap_path) as Texture2D
	if not tex:
		push_error("HeightmapTerrain: Failed to load heightmap: %s" % heightmap_path)
		_generate_procedural_heightmap()
		return

	_heightmap_image = tex.get_image()
	if not _heightmap_image:
		push_error("HeightmapTerrain: Could not get image from heightmap texture: %s" % heightmap_path)
		_generate_procedural_heightmap()
		return

	_heightmap_image.convert(Image.FORMAT_R8)
	_map_width = _heightmap_image.get_width()
	_map_depth = _heightmap_image.get_height()


## Build mesh from _heightmap_image, assign to Ground/MeshInstance3D, create trimesh collision.
func _build_terrain() -> void:
	var ground := get_node_or_null("Ground") as StaticBody3D
	if not ground:
		push_error("HeightmapTerrain: Ground node not found")
		return

	# Remove existing mesh and collision
	for child in ground.get_children():
		child.queue_free()

	# Build mesh with baked heights (same geometry for visual and collision)
	var mesh := _create_terrain_mesh()

	# Material: use baked mesh so disable shader displacement
	var mat: ShaderMaterial
	if ground_material and ground_material is ShaderMaterial:
		mat = ground_material.duplicate() as ShaderMaterial
		mat.set_shader_parameter("use_heightmap_displacement", false)
	else:
		mat = ground_material as ShaderMaterial if ground_material else null

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	if mat:
		mesh_instance.material_override = mat
	ground.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape: Shape3D = mesh.create_trimesh_shape()
	collision.shape = shape
	ground.call_deferred("add_child", collision)


## Build ArrayMesh from _heightmap_image: vertices with UV, triangles CCW.
func _create_terrain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var div_x: int = _map_width - 1
	var div_z: int = _map_depth - 1
	if div_x < 1:
		div_x = 1
	if div_z < 1:
		div_z = 1

	for j in _map_depth:
		for i in _map_width:
			var u := float(i) / float(div_x)
			var v := float(j) / float(div_z)
			var x := -_terrain_half + u * terrain_size
			var z := -_terrain_half + v * terrain_size
			var brightness := _heightmap_image.get_pixel(i, j).r
			var y := height_min + brightness * _height_scale

			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(x, y, z))

	for j in div_z:
		for i in div_x:
			var i0 := i + j * _map_width
			var i1 := i0 + 1
			var i2 := i0 + _map_width
			var i3 := i2 + 1
			# CCW from above (Y+) for correct normals
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i0)
			st.add_index(i3)
			st.add_index(i2)

	st.generate_normals()
	return st.commit()


## Sample height at world X,Z. Converts to UV, clamps, samples pixel brightness. Used by SimulationManager, WorldPopulator, HeightmapSampler.
func get_height_at(world_x: float, world_z: float) -> float:
	if not _heightmap_image:
		return 0.0

	# Convert world position to UV (0..1)
	var u := (world_x + _terrain_half) / terrain_size
	var v := (world_z + _terrain_half) / terrain_size
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)

	var px := int(u * (_map_width - 1))
	var pz := int(v * (_map_depth - 1))
	px = clampi(px, 0, _map_width - 1)
	pz = clampi(pz, 0, _map_depth - 1)

	var brightness := _heightmap_image.get_pixel(px, pz).r
	return height_min + brightness * _height_scale
