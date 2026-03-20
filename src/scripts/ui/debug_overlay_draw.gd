extends Control
## Inner draw surface for debug overlay. Receives snapshot and player position via meta from parent.
##
## Snapshot format: [x, z, isAnimal(0/1), speciesId, ...] per entity (4 floats each).
## Draws LOD grid (tier 0 green, 1 yellow, 2 orange, 3 red), entity dots (1px rects),
## and player dot (cyan). Uses world bounds 0..8192 on X and Z.

func _draw() -> void:
	var snapshot: Array = get_meta("snapshot", [])
	var player_x: float = get_meta("player_x", 0.0)
	var player_z: float = get_meta("player_z", 0.0)
	var internal_res: int = get_meta("internal_resolution", 128)
	var map_size: int = mini(internal_res, int(minf(size.x, size.y)))
	if map_size <= 0:
		return
	var grid_n: int = get_meta("grid_n", 16)
	var max_dots: int = get_meta("max_dots_to_draw", 1500)

	var cell_w: float = float(map_size) / grid_n
	var world_size: float = 8192.0
	var world_origin_x: float = 0.0
	var world_origin_z: float = 0.0

	# Background
	draw_rect(Rect2(0, 0, map_size, map_size), Color(0.1, 0.1, 0.15, 0.9))

	# Player cell for LOD
	var player_cx: int = 0
	var player_cz: int = 0
	player_cx = int(floor((player_x - world_origin_x) / (world_size / 32)))
	player_cz = int(floor((player_z - world_origin_z) / (world_size / 32)))
	player_cx = clampi(player_cx, 0, 31)
	player_cz = clampi(player_cz, 0, 31)

	# Map sim grid (32) to draw grid (grid_n)
	var scale_cx: float = 32.0 / float(grid_n)
	var scale_cz: float = 32.0 / float(grid_n)

	# Grid by LOD tier (coarse grid for speed)
	var tier_colors := [
		Color(0.2, 0.7, 0.2, 0.4),
		Color(0.8, 0.8, 0.2, 0.3),
		Color(0.9, 0.5, 0.2, 0.3),
		Color(0.9, 0.2, 0.2, 0.3),
	]
	for cx in grid_n:
		for cz in grid_n:
			var sim_cx: int = int(cx * scale_cx)
			var sim_cz: int = int(cz * scale_cz)
			var tier := _get_lod_tier(sim_cx, sim_cz, player_cx, player_cz)
			var col: Color = tier_colors[tier] if tier < 4 else Color(0.15, 0.15, 0.2, 0.5)
			var rx := cx * cell_w
			var rz := cz * cell_w
			draw_rect(Rect2(rx, rz, cell_w, cell_w), col)

	# Entity dots
	var snap_size: int = snapshot.size() if snapshot else 0
	var entity_count: int = snap_size / 4
	var step: int = 1
	if entity_count > max_dots:
		step = ceili(float(entity_count) / float(max_dots))
	var idx: int = 0
	var drawn: int = 0
	while idx < entity_count and drawn < max_dots:
		var i: int = idx * 4
		var x: float = float(snapshot[i])
		var z: float = float(snapshot[i + 1])
		var is_animal: bool = float(snapshot[i + 2]) > 0.5
		var species_id: int = int(snapshot[i + 3])

		var u := (x - world_origin_x) / world_size
		var v := (z - world_origin_z) / world_size
		u = clampf(u, 0.0, 1.0)
		v = clampf(v, 0.0, 1.0)
		var dot_x: int = int(u * map_size)
		var dot_y: int = int(v * map_size)

		var dot_color: Color
		if is_animal:
			dot_color = Color(0.3, 0.5, 1.0) if species_id == 0 else Color(0.9, 0.3, 0.2)
		else:
			dot_color = Color(0.2, 0.8, 0.4)
		draw_rect(Rect2i(dot_x, dot_y, 1, 1), dot_color)
		idx += step
		drawn += 1

	# Player dot
	var u := (player_x - world_origin_x) / world_size
	var v := (player_z - world_origin_z) / world_size
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)
	var map_x: int = int(u * map_size)
	var map_y: int = int(v * map_size)
	draw_rect(Rect2i(map_x, map_y, 1, 1), Color(0.0, 1.0, 1.0))


func _get_lod_tier(cx: int, cz: int, player_cx: int, player_cz: int) -> int:
	var dist: int = int(abs(cx - player_cx)) + int(abs(cz - player_cz))
	if dist <= 2: return 0
	if dist <= 4: return 1
	if dist <= 8: return 2
	if dist <= 16: return 3
	return 4
