extends Node3D
## Terrain with elevation derived from a grayscale image's brightness.
## Brighter pixels = higher elevation. Builds mesh with baked heights and
## uses trimesh collision for physics, guaranteeing visual/collision alignment.

@export var heightmap_path: String = ""
@export var terrain_size: float = 100.0
@export var height_min: float = -2.0
@export var height_max: float = 8.0
@export var resolution: int = 128

@export var ground_material: Material

var _heightmap_image: Image
var _map_width: int
var _map_depth: int

# Cached for get_height_at()
var _height_scale: float
var _terrain_half: float


func _ready() -> void:
	_setup_heightmap()
	_build_terrain()


func _setup_heightmap() -> void:
	if heightmap_path.is_empty() or not FileAccess.file_exists(heightmap_path):
		_generate_procedural_heightmap()
	else:
		_load_heightmap_from_file()


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


func _load_heightmap_from_file() -> void:
	var img := Image.new()
	var err := img.load(heightmap_path)
	if err != OK:
		push_error("HeightmapTerrain: Failed to load heightmap: %s" % heightmap_path)
		_generate_procedural_heightmap()
		return

	_heightmap_image = img.duplicate()
	_heightmap_image.convert(Image.FORMAT_R8)
	_map_width = _heightmap_image.get_width()
	_map_depth = _heightmap_image.get_height()


func _build_terrain() -> void:
	var ground := get_node_or_null("Ground") as StaticBody3D
	if not ground:
		push_error("HeightmapTerrain: Ground node not found")
		return

	# Remove existing mesh and collision
	for child in ground.get_children():
		child.queue_free()

	_height_scale = height_max - height_min
	_terrain_half = terrain_size * 0.5

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

	# Collision from the same mesh - guarantees exact visual/collision alignment
	var shape: Shape3D = mesh.create_trimesh_shape()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ground.add_child(collision)


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
