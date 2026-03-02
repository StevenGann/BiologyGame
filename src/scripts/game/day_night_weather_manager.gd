extends Node
## Manages time of day cycle (Dawn→Day→Dusk→Night) and weather (wind, snowfall, fog).
## - Sun position, intensity, color; sky colors; ambient light
## - Weather targets rolled at phase boundaries; current values lerp toward targets
## - Snow particles follow player; collision via heightfield
## - Debug: arrow keys step time and adjust weather


# Time of day
@export var day_length_seconds: float = 600.0  ## Full cycle duration
@export var start_time_normalized: float = 0.0  ## 0-1, where 0=dawn

# Fog (density = base + snowfall * multiplier)
@export var fog_base_min: float = 0.015
@export var fog_snow_multiplier: float = 0.065

# Weather transitions
@export var weather_lerp_speed: float = 1.0

# Debug controls (arrow keys)
@export var debug_arrow_controls: bool = true
@export var debug_time_step_seconds: float = 30.0
@export var debug_weather_step: float = 0.15

# Snow particles
@export var snow_base_amount: int = 100000
@export var snow_gravity_base: float = -2.0
@export var snow_wind_strength: float = 3.0

# Node refs (siblings under GameViewport)
var _directional_light: DirectionalLight3D
var _world_env: WorldEnvironment
var _snow_particles: GPUParticles3D
var _snow_collision: GPUParticlesCollisionHeightField3D
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


func _unhandled_input(event: InputEvent) -> void:
	if not debug_arrow_controls or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_LEFT:
			_game_time -= debug_time_step_seconds
			if _game_time < 0.0:
				_game_time = fmod(_game_time, day_length_seconds) + day_length_seconds
			_phase_index = _get_phase_index()
			_last_phase_index = _phase_index
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_game_time += debug_time_step_seconds
			if _game_time >= day_length_seconds:
				_game_time = fmod(_game_time, day_length_seconds)
			_phase_index = _get_phase_index()
			_last_phase_index = _phase_index
			get_viewport().set_input_as_handled()
		KEY_UP:
			_target_snowfall = clampf(_target_snowfall + debug_weather_step, 0.0, 10.0)
			_target_wind = clampf(_target_wind + debug_weather_step, 0.0, 10.0)
			_current_snowfall = _target_snowfall
			_current_wind = _target_wind
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_target_snowfall = clampf(_target_snowfall - debug_weather_step, 0.0, 10.0)
			_target_wind = clampf(_target_wind - debug_weather_step, 0.0, 10.0)
			_current_snowfall = _target_snowfall
			_current_wind = _target_wind
			get_viewport().set_input_as_handled()


func _add_snow_particles() -> void:
	_snow_particles = _create_snow_particles()
	if _snow_particles:
		get_parent().add_child(_snow_particles)
		_snow_process_material = _snow_particles.process_material as ParticleProcessMaterial

	# Collision in World (same branch as terrain) so heightfield samples mesh geometry
	var world := get_parent().get_node_or_null("World") as Node3D
	if world:
		_snow_collision = _create_snow_collision()
		world.add_child(_snow_collision)
		# Nudge position to force initial heightfield update (WHEN_MOVED only updates on move)
		call_deferred("_force_collision_update")

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
	proc_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

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
	# Larger collision radius helps particles detect terrain contact
	particles.collision_base_size = 0.15

	return particles


func _force_collision_update() -> void:
	if _snow_collision:
		_snow_collision.position += Vector3(0.01, 0, 0)
		_snow_collision.position -= Vector3(0.01, 0, 0)


func _create_snow_collision() -> GPUParticlesCollisionHeightField3D:
	var collision := GPUParticlesCollisionHeightField3D.new()
	collision.name = "SnowParticleCollision"
	collision.size = Vector3(400, 120, 400)
	collision.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	collision.follow_camera_enabled = true
	# WHEN_MOVED + follow_camera: updates when camera moves (snow follows player)
	collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	return collision


func _get_phase_index() -> int:
	var phase_duration := day_length_seconds / 4.0
	return int(floor(_game_time / phase_duration)) % 4  ## 0=Dawn, 1=Day, 2=Dusk, 3=Night


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
	# Day: 1.0, dusk/dawn: ~0.5, night: 0.02 (very dim)
	return clampf(elev_factor * 0.5 + 0.5, 0.02, 1.0)


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


func _get_sky_energy_multiplier() -> float:
	var t := _get_normalized_time()
	var elev_factor := sin(t * TAU)
	# Day: 1.0, dusk/dawn: ~0.5, night: 0.08 (very dim)
	return clampf(elev_factor * 0.5 + 0.5, 0.08, 1.0)


func _get_sky_colors() -> Dictionary:
	var t := _get_normalized_time()
	var elev_factor := sin(t * TAU)
	# Day colors (bright, neutral)
	var day_top := Color(0.55, 0.6, 0.65)
	var day_horizon := Color(0.6, 0.65, 0.7)
	var day_ground := Color(0.3, 0.32, 0.35)
	var day_ground_horizon := Color(0.4, 0.43, 0.47)
	# Night colors (dark blue/purple)
	var night_top := Color(0.02, 0.03, 0.08)
	var night_horizon := Color(0.05, 0.06, 0.12)
	var night_ground := Color(0.01, 0.015, 0.03)
	var night_ground_horizon := Color(0.03, 0.04, 0.08)
	# Dawn/dusk (warm horizon)
	var dusk_top := Color(0.25, 0.2, 0.3)
	var dusk_horizon := Color(0.5, 0.35, 0.4)
	var dusk_ground := Color(0.15, 0.1, 0.12)
	var dusk_ground_horizon := Color(0.35, 0.25, 0.28)

	var blend := clampf(elev_factor * 0.5 + 0.5, 0.0, 1.0)  # 0 = night, 1 = day
	if blend > 0.6:
		return {
			"sky_top": day_top,
			"sky_horizon": day_horizon,
			"ground_bottom": day_ground,
			"ground_horizon": day_ground_horizon
		}
	if blend > 0.3:
		var t_dusk := (blend - 0.3) / 0.3
		return {
			"sky_top": dusk_top.lerp(day_top, t_dusk),
			"sky_horizon": dusk_horizon.lerp(day_horizon, t_dusk),
			"ground_bottom": dusk_ground.lerp(day_ground, t_dusk),
			"ground_horizon": dusk_ground_horizon.lerp(day_ground_horizon, t_dusk)
		}
	if blend > 0.1:
		var t_night := (blend - 0.1) / 0.2
		return {
			"sky_top": night_top.lerp(dusk_top, t_night),
			"sky_horizon": night_horizon.lerp(dusk_horizon, t_night),
			"ground_bottom": night_ground.lerp(dusk_ground, t_night),
			"ground_horizon": night_ground_horizon.lerp(dusk_ground_horizon, t_night)
		}
	return {
		"sky_top": night_top,
		"sky_horizon": night_horizon,
		"ground_bottom": night_ground,
		"ground_horizon": night_ground_horizon
	}


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

	# Update ambient and sky via environment
	if _world_env and _world_env.environment:
		var env: Environment = _world_env.environment
		var intensity := _get_sun_intensity()
		env.ambient_light_energy = lerpf(0.2, 0.6, intensity)
		env.ambient_light_color = Color(0.5, 0.52, 0.55).lerp(Color(0.2, 0.25, 0.35), 1.0 - intensity)

		# Update procedural sky colors and brightness by time of day
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
			var colors := _get_sky_colors()
			sky_mat.sky_top_color = colors["sky_top"]
			sky_mat.sky_horizon_color = colors["sky_horizon"]
			sky_mat.ground_bottom_color = colors["ground_bottom"]
			sky_mat.ground_horizon_color = colors["ground_horizon"]
			sky_mat.sky_energy_multiplier = _get_sky_energy_multiplier()


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


## Current game time in seconds (0..day_length_seconds).
func get_game_time() -> float:
	return _game_time


## Phase index: 0=Dawn, 1=Daytime, 2=Dusk, 3=Nighttime.
func get_phase_index() -> int:
	return _phase_index


## Human-readable phase name.
func get_phase_name() -> String:
	match _phase_index:
		PHASE_DAWN: return "Dawn"
		PHASE_DAY: return "Daytime"
		PHASE_DUSK: return "Dusk"
		PHASE_NIGHT: return "Nighttime"
	return "Unknown"
