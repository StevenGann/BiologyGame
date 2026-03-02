class_name AnimalBase
extends CharacterBody3D

const PS1MaterialBuilder = preload("res://scripts/props/ps1_material_builder.gd")
const SimManager = preload("res://scripts/game/simulation_manager.gd")

signal animal_defeated

enum State { WANDERING, PANICKING }

## Species identifier for same-species checks (Social, AI).
## Add more species as needed; subclasses inherit this.
enum Species { BISON, DEER, RABBIT, WOLF, BEAR }

@export var species: Species = Species.BISON
@export var use_ps1_effect: bool = true
@export var max_health: int = 2
@export var wander_speed: float = 0.8
@export var panic_speed: float = 4.0
@export var wander_radius: float = 8.0
@export var detection_range: float = 6.0
@export var panic_duration: float = 3.0
@export var wander_pause_min: float = 1.0
@export var wander_pause_max: float = 4.0

## 0 = ignore others, 1 = strong influence. Affects cohesion, panic/calm contagion.
@export_range(0.0, 1.0) var social_factor: float = 0.5

@export_group("Debug LOD Label")
@export var debug_label_height: float = 2.5
@export var debug_label_font_size: int = 72
@export var cohesion_radius: float = 12.0
@export var contagion_radius: float = 10.0

var health: int
var _state := State.WANDERING
var _wander_target: Vector3
var _wander_timer: float
var _panic_timer: float
var _threat_position: Vector3
var _cached_sim_manager: Node = null
var _cached_instance_id: int = 0
var _cached_nearby: Array = []
var _cached_nearby_frame: int = -1
var _skip_social_this_frame: bool = false
var _accumulated_ai_delta: float = 0.0
var _accumulated_move_delta: float = 0.0
var _was_far_lod: bool = false
var _debug_label: Label3D = null
var _debug_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	add_to_group("animals")
	health = max_health
	if use_ps1_effect:
		PS1MaterialBuilder.apply_to_node($Model)
	_pick_new_wander_target()
	_wander_timer = randf_range(wander_pause_min, wander_pause_max)
	_setup_debug_label()
	_setup_debug_mesh()
	_cached_instance_id = get_instance_id()


func _setup_debug_label() -> void:
	_debug_label = Label3D.new()
	_debug_label.position = Vector3(0, debug_label_height, 0)
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.modulate = Color.YELLOW
	_debug_label.font_size = debug_label_font_size
	_debug_label.visible = false
	add_child(_debug_label)


func _setup_debug_mesh() -> void:
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.visible = false
	add_child(_debug_mesh_instance)


## Override in subclasses to return state name (e.g. "Wander", "Stalk", "Eat").
func _get_debug_state_string() -> String:
	match _state:
		State.WANDERING:
			return "Wander"
		State.PANICKING:
			return "Panic"
	return "?"


func _get_debug_species_string() -> String:
	match species:
		Species.BISON:
			return "Bison"
		Species.DEER:
			return "Deer"
		Species.RABBIT:
			return "Rabbit"
		Species.WOLF:
			return "Wolf"
		Species.BEAR:
			return "Bear"
	return "?"


## Returns global center of nearby same-species in cohesion range, or null if none.
func _get_cohesion_center() -> Variant:
	var nearby := _get_nearby_same_species()
	if nearby.is_empty():
		return null
	var center := Vector3.ZERO
	var count := 0
	var cohesion_radius_sq := cohesion_radius * cohesion_radius
	for a in nearby:
		if a != self:
			var dist_sq := global_position.distance_squared_to(a.global_position)
			if dist_sq < cohesion_radius_sq and dist_sq > 0.0001:
				center += a.global_position
				count += 1
	if count <= 0:
		return null
	center /= count
	return center


func _physics_process(delta: float) -> void:
	var gravity_vec: Vector3 = Vector3.DOWN * ProjectSettings.get_setting("physics/3d/default_gravity")
	velocity.y += gravity_vec.y * delta

	_accumulated_ai_delta += delta
	_accumulated_move_delta += delta

	var sim: Node = _get_sim_manager()
	if sim != null:
		var lod: int = sim.get_lod_tier(global_position)
		var ai_tick: bool = sim.should_ai_tick_this_frame(lod, _cached_instance_id)
		var move_tick: bool = sim.should_movement_tick_this_frame(lod, _cached_instance_id)

		if lod == SimManager.LODTier.FULL:
			if ai_tick:
				_skip_social_this_frame = false
				_update_nearby_cache()
				_update_state(_accumulated_ai_delta)
				_accumulated_ai_delta = 0.0
			if move_tick:
				_apply_movement(_accumulated_move_delta)
				_accumulated_move_delta = 0.0
		elif lod == SimManager.LODTier.MEDIUM:
			if ai_tick:
				_skip_social_this_frame = true
				_update_state(_accumulated_ai_delta)
				_accumulated_ai_delta = 0.0
			if move_tick:
				_apply_movement_simple(_accumulated_move_delta)
				_accumulated_move_delta = 0.0
		## FAR is handled by SimulationManager.process_far_animals() - no physics_process
	else:
		_skip_social_this_frame = false
		_update_nearby_cache()
		_update_state(delta)
		_apply_movement(delta)
		_accumulated_ai_delta = 0.0
		_accumulated_move_delta = 0.0

	_update_debug_label(sim)
	move_and_slide()


func _update_debug_label(sim: Node) -> void:
	if _debug_label == null:
		return
	if sim != null and sim.debug_mode:
		var lod: int = sim.get_lod_tier(global_position)
		if lod == SimManager.LODTier.FULL or lod == SimManager.LODTier.MEDIUM:
			_debug_label.visible = true
			var lod_str: String = "Full" if lod == SimManager.LODTier.FULL else "Medium"
			var parts: PackedStringArray = [lod_str]
			if sim.get("debug_show_state") != false:
				parts.append(_get_debug_state_string())
			if sim.get("debug_show_species") != false:
				parts.append(_get_debug_species_string())
			if sim.get("debug_show_panic_timer") != false and _state == State.PANICKING:
				parts.append("%.1fs" % _panic_timer)
			_debug_label.text = " | ".join(parts)
			_update_debug_visuals(sim)
		else:
			_debug_label.visible = false
			if _debug_mesh_instance != null:
				_debug_mesh_instance.visible = false
	else:
		_debug_label.visible = false
		if _debug_mesh_instance != null:
			_debug_mesh_instance.visible = false


## Override in subclasses to add hunter→prey, forager→plant, etc.
func _update_debug_visuals(sim: Node) -> void:
	if _debug_mesh_instance == null or sim == null or not sim.debug_mode:
		return
	_debug_mesh_instance.visible = true
	var imesh := ImmediateMesh.new()
	var segs := 24
	var origin := Vector3.ZERO

	if sim.get("debug_show_threat_line") != false and _state == State.PANICKING:
		var mat := _make_debug_material(Color.RED)
		imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		imesh.surface_add_vertex(origin)
		imesh.surface_add_vertex(to_local(_threat_position))
		imesh.surface_end()

	if sim.get("debug_show_cohesion_line") != false:
		var center = _get_cohesion_center()
		if center != null:
			var mat := _make_debug_material(Color.GREEN)
			imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
			imesh.surface_add_vertex(origin)
			imesh.surface_add_vertex(to_local(center))
			imesh.surface_end()

	if sim.get("debug_show_detection_radii") != false:
		var det_mat := _make_debug_material(Color.YELLOW)
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, det_mat)
		for i in range(segs + 1):
			var a := TAU * float(i) / float(segs)
			imesh.surface_add_vertex(origin + Vector3(cos(a) * detection_range, 0, sin(a) * detection_range))
		imesh.surface_end()
		var coh_mat := _make_debug_material(Color.CYAN)
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, coh_mat)
		for i in range(segs + 1):
			var a := TAU * float(i) / float(segs)
			imesh.surface_add_vertex(origin + Vector3(cos(a) * cohesion_radius, 0, sin(a) * cohesion_radius))
		imesh.surface_end()

	if sim.get("debug_show_nearby_species") != false:
		var nearby := _get_nearby_same_species()
		var cohesion_radius_sq := cohesion_radius * cohesion_radius
		var started := false
		var mat := _make_debug_material(Color.WHITE)
		for a in nearby:
			if a == self:
				continue
			var dist_sq := global_position.distance_squared_to(a.global_position)
			if dist_sq < cohesion_radius_sq and dist_sq > 0.0001:
				if not started:
					started = true
					imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
				imesh.surface_add_vertex(origin)
				imesh.surface_add_vertex(to_local(a.global_position))
		if started:
			imesh.surface_end()

	_debug_mesh_instance.mesh = imesh


func _make_debug_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m


func take_damage(amount: int) -> void:
	health -= amount
	var player := _get_player()
	_panic_from_position(player.global_position if player else global_position + (-global_transform.basis.z * 2.0))
	if health <= 0:
		_defeat()


func is_panicking() -> bool:
	return _state == State.PANICKING


func _defeat() -> void:
	animal_defeated.emit()
	queue_free()


func _update_state(delta: float) -> void:
	_update_threats(delta)
	_apply_contagion(delta)

	if _state == State.PANICKING:
		_panic_timer -= delta
		if _panic_timer <= 0:
			_state = State.WANDERING
			_pick_new_wander_target()
			_wander_timer = randf_range(wander_pause_min, wander_pause_max)


## Override in subclasses to add threat detection (e.g. Forager sets Hunter as threat).
func _update_threats(_delta: float) -> void:
	var player := _get_player()
	if player != null:
		var dist := global_position.distance_to(player.global_position)
		if dist < detection_range:
			_panic_from_position(player.global_position)


## Shared contagion logic; call from subclass overrides if overriding _update_state.
func _apply_contagion(delta: float) -> void:
	if _skip_social_this_frame or social_factor <= 0.0:
		return
	var nearby := _get_nearby_same_species()
	var panicking_count := 0
	var nearest_panicked: CharacterBody3D = null
	var nearest_panicked_dist_sq := contagion_radius * contagion_radius
	for a in nearby:
		if a == self:
			continue
		if a.is_panicking():
			panicking_count += 1
			var d_sq := global_position.distance_squared_to(a.global_position)
			if d_sq < nearest_panicked_dist_sq:
				nearest_panicked_dist_sq = d_sq
				nearest_panicked = a as CharacterBody3D

	if _state == State.WANDERING and panicking_count > 0:
		var base_chance := 0.15 * delta
		if randf() < social_factor * base_chance * panicking_count and nearest_panicked:
			_panic_from_position(nearest_panicked.global_position)
	elif _state == State.PANICKING and panicking_count == 0 and nearby.size() > 0:
		var calm_chance := 0.2 * delta * social_factor
		if randf() < calm_chance:
			_panic_timer -= panic_duration * 0.2


func _apply_movement_simple(delta: float) -> void:
	if _state == State.PANICKING:
		var away := (global_position - _threat_position).normalized()
		away.y = 0
		if away.length_squared() > 0.01:
			velocity.x = away.x * panic_speed
			velocity.z = away.z * panic_speed
			look_at(global_position + Vector3(velocity.x, 0, velocity.z), Vector3.UP)
	elif _state == State.WANDERING:
		if _wander_timer > 0:
			_wander_timer -= delta
			velocity.x = move_toward(velocity.x, 0, wander_speed * 2)
			velocity.z = move_toward(velocity.z, 0, wander_speed * 2)
		else:
			var to_target := _wander_target - global_position
			to_target.y = 0
			if to_target.length() < 0.5:
				_pick_new_wander_target()
				_wander_timer = randf_range(wander_pause_min, wander_pause_max)
				velocity.x = 0
				velocity.z = 0
			else:
				var dir := to_target.normalized()
				velocity.x = dir.x * wander_speed
				velocity.z = dir.z * wander_speed
				look_at(global_position + dir, Vector3.UP)


func _apply_movement(delta: float) -> void:
	var cohesion := _get_social_cohesion_vector()
	if _state == State.PANICKING:
		var away := (global_position - _threat_position).normalized()
		away.y = 0
		if away.length_squared() > 0.01:
			velocity.x = away.x * panic_speed
			velocity.z = away.z * panic_speed
			_apply_cohesion_to_velocity(cohesion)
			look_at(global_position + Vector3(velocity.x, 0, velocity.z), Vector3.UP)
	elif _state == State.WANDERING:
		if _wander_timer > 0:
			_wander_timer -= delta
			velocity.x = move_toward(velocity.x, 0, wander_speed * 2)
			velocity.z = move_toward(velocity.z, 0, wander_speed * 2)
		else:
			var to_target := _wander_target - global_position
			to_target.y = 0
			if to_target.length() < 0.5:
				_pick_new_wander_target()
				_wander_timer = randf_range(wander_pause_min, wander_pause_max)
				velocity.x = 0
				velocity.z = 0
			else:
				var dir := to_target.normalized()
				velocity.x = dir.x * wander_speed
				velocity.z = dir.z * wander_speed
				_apply_cohesion_to_velocity(cohesion)
				look_at(global_position + dir, Vector3.UP)


func _panic_from_position(pos: Vector3) -> void:
	_state = State.PANICKING
	_threat_position = pos
	_panic_timer = panic_duration


func _pick_new_wander_target() -> void:
	var offset := Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	_wander_target = global_position + offset


## Called by SimulationManager for FAR animals. Horizontal movement only, no gravity or physics.
func process_far_tick(delta: float, ai_tick: bool, move_tick: bool) -> void:
	_accumulated_ai_delta += delta
	_accumulated_move_delta += delta
	if ai_tick:
		_skip_social_this_frame = false
		_update_state_far(_accumulated_ai_delta)
		_accumulated_ai_delta = 0.0
	if move_tick:
		_apply_simple_wander(_accumulated_move_delta)
		_accumulated_move_delta = 0.0
	velocity.y = 0.0
	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta


## Simplified state for FAR LOD: contagion, panic timer, no threats. Override in subclasses if needed.
func _update_state_far(delta: float) -> void:
	_apply_contagion(delta)
	if _state == State.PANICKING:
		_panic_timer -= delta
		if _panic_timer <= 0:
			_state = State.WANDERING
			_pick_new_wander_target()
			_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _apply_simple_wander(delta: float) -> void:
	var cohesion: Vector3
	if _state == State.PANICKING:
		var away := (global_position - _threat_position).normalized()
		away.y = 0
		if away.length_squared() > 0.01:
			velocity.x = away.x * panic_speed * 0.5
			velocity.z = away.z * panic_speed * 0.5
		cohesion = _get_social_cohesion_vector()
		_apply_cohesion_to_velocity(cohesion)
		return
	if _wander_timer > 0:
		_wander_timer -= delta
		return
	var to_target := _wander_target - global_position
	to_target.y = 0
	if to_target.length() < 1.0:
		_pick_new_wander_target()
		_wander_timer = randf_range(1.0, 3.0)
		return
	var dir := to_target.normalized()
	velocity.x = dir.x * wander_speed * 0.5
	velocity.z = dir.z * wander_speed * 0.5
	cohesion = _get_social_cohesion_vector()
	_apply_cohesion_to_velocity(cohesion)


func _get_sim_manager() -> Node:
	if _cached_sim_manager == null or not is_instance_valid(_cached_sim_manager):
		_cached_sim_manager = get_tree().get_first_node_in_group("simulation_manager") as Node
	return _cached_sim_manager


func _update_nearby_cache() -> void:
	var fc := get_tree().get_frame()
	if _cached_nearby_frame != fc:
		_cached_nearby_frame = fc
		_cached_nearby = _fetch_nearby_same_species()


func _get_nearby_same_species() -> Array:
	var fc := get_tree().get_frame()
	if _cached_nearby_frame == fc:
		return _cached_nearby
	_cached_nearby_frame = fc
	_cached_nearby = _fetch_nearby_same_species()
	return _cached_nearby


func _fetch_nearby_same_species() -> Array:
	var max_range := maxf(cohesion_radius, contagion_radius) + 5.0
	var max_range_sq := max_range * max_range
	var sim: Node = _get_sim_manager()
	if sim != null and sim.has_method("get_same_species_in_radius"):
		return sim.get_same_species_in_radius(global_position, max_range, species, self)
	var result: Array = []
	var animals_parent := get_parent()
	if animals_parent:
		for a in animals_parent.get_children():
			if not is_instance_of(a, CharacterBody3D):
				continue
			var other := a as CharacterBody3D
			if other == self:
				continue
			if "species" not in other or other.species != species:
				continue
			if global_position.distance_squared_to(other.global_position) <= max_range_sq:
				result.append(other)
	return result


func _get_social_cohesion_vector() -> Vector3:
	if social_factor <= 0.0:
		return Vector3.ZERO
	var nearby := _get_nearby_same_species()
	if nearby.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	var count := 0
	var cohesion_radius_sq := cohesion_radius * cohesion_radius
	for a in nearby:
		if a != self:
			var dist_sq := global_position.distance_squared_to(a.global_position)
			if dist_sq < cohesion_radius_sq and dist_sq > 0.0001:
				center += a.global_position
				count += 1
	if count <= 0:
		return Vector3.ZERO
	center /= count
	var to_center := center - global_position
	to_center.y = 0
	if to_center.length_squared() < 0.01:
		return Vector3.ZERO
	return to_center.normalized() * social_factor * wander_speed * 0.5


func _apply_cohesion_to_velocity(cohesion: Vector3) -> void:
	if cohesion.length_squared() < 0.0001:
		return
	velocity.x += cohesion.x
	velocity.z += cohesion.z
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	var max_speed := panic_speed if _state == State.PANICKING else wander_speed
	if speed > max_speed:
		flat = flat.normalized() * max_speed
		velocity.x = flat.x
		velocity.z = flat.z


func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D
