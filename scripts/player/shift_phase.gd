class_name ShiftPhase
extends SkaterAbility
## X: a dash. An instant, short burst where the player is looking, phasing out of the world.
##
## On press the skater bursts [member dash_distance] m in [member dash_duration] s along the
## camera's view (the crosshair): flattened to level ground when rolling, and pitched at most
## [member air_pitch_limit_deg] in the air, with no gravity while it lasts. It then comes out
## of the dash rolling level along that direction at its old speed plus
## [member exit_boost] (at least [member min_exit_speed]), so a dash is also a speed boost.
## The camera's field of view kicks out by [member fov_kick] for the burst. The skater stops
## colliding with the [code]phaseable[/code] physics layer (3) for [member phase_duration].
## The rig turns translucent while phased. If the phase runs out while the body is still inside a
## phaseable object, it stays phased until it is clear, so it never gets stuck in a wall.
## Bodies on the [code]world[/code] layer stay solid throughout.

@export_group("Dash")
## How far (m) the burst carries the skater...
@export var dash_distance: float = 8.5
## ...in this many seconds (it owns the skater's movement meanwhile).
@export var dash_duration: float = 0.16
## Speed (m/s) added on top of the speed the skater had when it dashed.
@export var exit_boost: float = 7.0
## Speed (m/s) the skater comes out of a dash with at the least.
@export var min_exit_speed: float = 15.0
## Steepest (degrees) an airborne dash goes up or down.
@export var air_pitch_limit_deg: float = 30.0
## Degrees the camera's field of view widens at the start of a dash, easing back after.
@export var fov_kick: float = 12.0

@export_group("Phase")
## Seconds the skater is out of phase with the phaseable layer.
@export var phase_duration: float = 0.45
## Seconds from one shift to the next being allowed.
@export var cooldown: float = 0.9

## True while the skater passes through phaseable bodies.
var phased: bool = false
## How many times the shift has fired (HUD, stats, tests).
var activation_count: int = 0

var _dash_left: float = 0.0
var _dash_direction: Vector3 = Vector3.FORWARD
var _exit_speed: float = 0.0
var _view_forward: Vector3 = Vector3.FORWARD
var _fov_tween: Tween = null
var _phase_left: float = 0.0
var _cooldown_left: float = 0.0


func physics_tick(body: CharacterBody3D, delta: float) -> void:
	var skater := body as Skater
	if skater == null:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if input_enabled and Input.is_action_just_pressed("shift_phase") and can_activate():
		_activate(skater)
	if _dash_left > 0.0:
		_dash_left -= delta
		if _dash_left > 0.0:
			skater.velocity = _dash_direction * (dash_distance / maxf(dash_duration, 0.01))
		else:
			# Out of the burst: rolling level along it, carrying the boost.
			var level := Vector3(_dash_direction.x, 0.0, _dash_direction.z)
			level = level.normalized() if not level.is_zero_approx() else skater.heading
			skater.velocity = level * _exit_speed
	if phased:
		_phase_left -= delta
		if _phase_left <= 0.0 and not _overlaps_phaseable(skater):
			_end_phase(skater)


func update_aim(view_forward: Vector3, _facing: Vector3) -> void:
	_view_forward = view_forward


func is_controlling_movement() -> bool:
	return _dash_left > 0.0


func is_active() -> bool:
	return phased


## True when a press would shift now (enabled, not already phased, cooldown over).
func can_activate() -> bool:
	return enabled and not phased and _cooldown_left <= 0.0


## Seconds until the next shift is allowed.
func get_cooldown_left() -> float:
	return _cooldown_left


func _activate(skater: Skater) -> void:
	phased = true
	activation_count += 1
	_dash_left = dash_duration
	_dash_direction = dash_direction(skater)
	_exit_speed = maxf(skater.speed + exit_boost, min_exit_speed)
	_kick_fov(skater)
	_phase_left = phase_duration
	_cooldown_left = cooldown
	skater.set_collision_mask_value(PhysicsLayers.PHASEABLE_LAYER, false)
	skater.set_translucent(true)
	activated.emit()


## Where a dash starting now goes: the camera's view, level when rolling, pitched at most
## [member air_pitch_limit_deg] in the air.
func dash_direction(skater: Skater) -> Vector3:
	var view := _view_forward
	if view.is_zero_approx():
		view = skater.heading
	var level := Vector3(view.x, 0.0, view.z)
	if level.is_zero_approx():
		level = skater.heading
	level = level.normalized()
	if skater.is_on_floor():
		return level
	var limit := deg_to_rad(air_pitch_limit_deg)
	var pitch := clampf(asin(clampf(view.normalized().y, -1.0, 1.0)), -limit, limit)
	return (level * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


func _kick_fov(skater: Skater) -> void:
	var camera := skater.camera
	if camera == null or fov_kick <= 0.0:
		return
	if _fov_tween != null and _fov_tween.is_valid():
		_fov_tween.kill()
		camera.fov = float(camera.get_meta(&"base_fov", camera.fov))
	camera.set_meta(&"base_fov", camera.fov)
	var base := camera.fov
	_fov_tween = create_tween()
	_fov_tween.tween_property(camera, "fov", base + fov_kick, dash_duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fov_tween.tween_property(camera, "fov", base, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _end_phase(skater: Skater) -> void:
	phased = false
	skater.set_collision_mask_value(PhysicsLayers.PHASEABLE_LAYER, true)
	skater.set_translucent(false)
	deactivated.emit()


## Whether the skater's collision shape currently overlaps anything on the phaseable layer.
func _overlaps_phaseable(skater: Skater) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = skater.body_shape.shape
	query.transform = skater.body_shape.global_transform
	query.collision_mask = PhysicsLayers.PHASEABLE_MASK
	query.exclude = [skater.get_rid()]
	var hits := skater.get_world_3d().direct_space_state.intersect_shape(query, 1)
	return not hits.is_empty()
