extends Node
## Manages time of day cycle and weather (wind, snowfall, fog).
## Weather targets change only at phase boundaries (Dawn, Daytime, Dusk, Nighttime).
## All values interpolate smoothly.


# Time of day
@export var day_length_seconds: float = 600.0
@export var start_time_normalized: float = 0.0  ## 0-1, where 0=dawn

# Fog
@export var fog_base_min: float = 0.015
@export var fog_snow_multiplier: float = 0.065

# Weather transitions
@export var weather_lerp_speed: float = 1.0

# Snow particles
@export var snow_base_amount: int = 8000
@export var snow_gravity_base: float = -2.0
@export var snow_wind_strength: float = 4.0

# Node refs (siblings under GameViewport)
var _directional_light: DirectionalLight3D
var _world_env: WorldEnvironment
var _snow_particles: GPUParticles3D
var _player: Node3D

const PHASE_DAWN := 0
const PHASE_DAY := 1
const PHASE_DUSK := 2
const PHASE_NIGHT := 3

var _game_time: float = 0.0
var _phase_index: int = 0
var _last_phase_index: int = -1

var _target_wind: float = 0.0
var _target_snowfall: float = 0.0
var _target_wind_direction_deg: float = 0.0

var _current_wind: float = 0.0
var _current_snowfall: float = 0.0
var _current_wind_direction_deg: float = 0.0

var _rng: RandomNumberGenerator
var _sun_distance: float = 150.0
var _snow_process_material: ParticleProcessMaterial  # Reference to process_material for gravity updates


func _ready() -> void:
	var viewport := get_parent()
	_directional_light = viewport.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	_world_env = viewport.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_player = viewport.get_node_or_null("Player") as Node3D

	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_game_time = start_time_normalized * day_length_seconds
	_phase_index = _get_phase_index()
	_last_phase_index = _phase_index
	_roll_weather_targets()
	_current_wind = _target_wind
	_current_snowfall = _target_snowfall
	_current_wind_direction_deg = _target_wind_direction_deg

	# Duplicate environment so we don't modify the original asset
	if _world_env and _world_env.environment:
		_world_env.environment = _world_env.environment.duplicate(true)

	# Defer snow particle creation to avoid renderer null material race condition
	call_deferred("_add_snow_particles")

	_update_sun()
	_update_fog()


func _process(delta: float) -> void:
	_game_time += delta
	if _game_time >= day_length_seconds:
		_game_time = fmod(_game_time, day_length_seconds)

	_phase_index = _get_phase_index()
	if _phase_index != _last_phase_index:
		_last_phase_index = _phase_index
		_roll_weather_targets()

	_current_wind = lerpf(_current_wind, _target_wind, weather_lerp_speed * delta)
	_current_snowfall = lerpf(_current_snowfall, _target_snowfall, weather_lerp_speed * delta)
	_current_wind_direction_deg = lerpf(_current_wind_direction_deg, _target_wind_direction_deg, weather_lerp_speed * delta)

	_update_sun()
	_update_fog()
	_update_snow()


func _add_snow_particles() -> void:
	_snow_particles = _create_snow_particles()
	if _snow_particles:
		get_parent().add_child(_snow_particles)
		_snow_process_material = _snow_particles.process_material as ParticleProcessMaterial
	_update_snow()


func _create_snow_particles() -> GPUParticles3D:
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(150, 30, 150)
	proc_mat.direction = Vector3(0, -1, 0)
	proc_mat.spread = 0.5
	proc_mat.initial_velocity_min = 0.5
	proc_mat.initial_velocity_max = 1.5
	proc_mat.gravity = Vector3(0, snow_gravity_base, 0)
	proc_mat.scale_min = 0.05
	proc_mat.scale_max = 0.15
	proc_mat.color = Color(0.95, 0.96, 1.0, 0.9)

	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = Color(0.98, 0.99, 1.0, 0.85)
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# BILLBOARD_PARTICLES causes null material errors in Godot 4.6 RD renderer
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = quad_mat

	var particles := GPUParticles3D.new()
	particles.name = "SnowParticles"
	particles.transform = Transform3D.IDENTITY.translated(Vector3(0, 80, 0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = snow_base_amount
	particles.lifetime = 8.0
	particles.process_material = proc_mat
	particles.draw_pass_1 = quad
	# Default visibility_aabb (8x8x8) causes frustum culling when looking forward/down
	# Use large AABB so snow is always visible around the player
	particles.visibility_aabb = AABB(Vector3(-200, -100, -200), Vector3(400, 200, 400))
	return particles


func _get_phase_index() -> int:
	var phase_duration := day_length_seconds / 4.0
	return int(floor(_game_time / phase_duration)) % 4


func _roll_weather_targets() -> void:
	_target_wind = _rng.randf()
	_target_snowfall = _rng.randf()
	_target_wind_direction_deg = _rng.randf_range(0.0, 360.0)


func _get_normalized_time() -> float:
	return _game_time / day_length_seconds


func _get_sun_angles() -> Vector2:
	var t := _get_normalized_time()
	var azimuth: float = t * TAU
	# elevation: high at noon (t=0.25), low at dawn/dusk, below horizon at night
	var elevation: float = sin(t * TAU) * 0.55 + 0.1
	elevation = clampf(elevation, -0.2, 0.65)
	return Vector2(azimuth, elevation)


func _get_sun_intensity() -> float:
	var t := _get_normalized_time()
	var elev_factor := sin(t * TAU)
	return clampf(elev_factor * 0.5 + 0.5, 0.05, 1.0)


func _get_sun_color() -> Color:
	var t := _get_normalized_time()
	var elev_factor := sin(t * TAU)
	if elev_factor > 0.5:
		return Color(0.95, 0.93, 0.9)
	if elev_factor > 0.0:
		return Color(1.0, 0.9, 0.7).lerp(Color(0.95, 0.93, 0.9), elev_factor * 2.0)
	if elev_factor > -0.5:
		return Color(1.0, 0.6, 0.4).lerp(Color(0.3, 0.4, 0.6), -elev_factor * 2.0)
	return Color(0.25, 0.3, 0.45)


func _update_sun() -> void:
	if not _directional_light:
		return

	var angles := _get_sun_angles()
	var azimuth: float = angles.x
	var elevation: float = angles.y

	var sun_dir := Vector3(
		cos(elevation) * cos(azimuth),
		sin(elevation),
		cos(elevation) * sin(azimuth)
	)
	var sun_pos := sun_dir * _sun_distance

	_directional_light.global_position = sun_pos
	_directional_light.look_at(Vector3.ZERO, Vector3.UP)
	_directional_light.light_energy = _get_sun_intensity()
	_directional_light.light_color = _get_sun_color()

	# Update ambient via environment
	if _world_env and _world_env.environment:
		var env: Environment = _world_env.environment
		var intensity := _get_sun_intensity()
		env.ambient_light_energy = lerpf(0.2, 0.6, intensity)
		env.ambient_light_color = Color(0.5, 0.52, 0.55).lerp(Color(0.2, 0.25, 0.35), 1.0 - intensity)


func _update_fog() -> void:
	if not _world_env or not _world_env.environment:
		return

	var env: Environment = _world_env.environment
	env.volumetric_fog_density = fog_base_min + _current_snowfall * fog_snow_multiplier
	# Note: volumetric_fog_wind was removed in Godot 4.x Environment API.
	# Wind is still applied to snow particles via ParticleProcessMaterial.gravity.


func _update_snow() -> void:
	if not _snow_particles or not _snow_process_material:
		return

	var has_snow: bool = _current_snowfall > 0.01
	_snow_particles.visible = has_snow
	_snow_particles.emitting = has_snow
	_snow_particles.amount = maxi(1, int(snow_base_amount * _current_snowfall))

	# Follow player so snow spawns around them (emission box stays centered on player)
	if _player:
		_snow_particles.global_position = _player.global_position + Vector3(0, 80, 0)

	var wind_rad := deg_to_rad(_current_wind_direction_deg)
	var wind_x := cos(wind_rad) * _current_wind * snow_wind_strength
	var wind_z := sin(wind_rad) * _current_wind * snow_wind_strength
	_snow_process_material.gravity = Vector3(wind_x, snow_gravity_base, wind_z)


func get_game_time() -> float:
	return _game_time


func get_phase_index() -> int:
	return _phase_index


func get_phase_name() -> String:
	match _phase_index:
		PHASE_DAWN: return "Dawn"
		PHASE_DAY: return "Daytime"
		PHASE_DUSK: return "Dusk"
		PHASE_NIGHT: return "Nighttime"
	return "Unknown"
