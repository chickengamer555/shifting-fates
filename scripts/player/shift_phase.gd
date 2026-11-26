class_name ShiftPhase
extends SkaterAbility
## X: dash forward and phase out of the world for a moment.
##
## On press the skater dashes along its heading at [member dash_speed] for
## [member dash_duration] (hovering, no gravity) and stops colliding with the
## [code]phaseable[/code] physics layer (3) for [member phase_duration]. The rig turns
## translucent while phased. If the phase runs out while the body is still inside a
## phaseable object, it stays phased until it is clear, so it never gets stuck in a wall.
## Bodies on the [code]world[/code] layer stay solid throughout.

@export_group("Dash")
## Horizontal speed during the dash (m/s).
@export var dash_speed: float = 14.0
## Seconds the dash owns the skater's movement.
@export var dash_duration: float = 0.3

@export_group("Phase")
## Seconds the skater is out of phase with the phaseable layer.
@export var phase_duration: float = 0.45
## Seconds from one shift to the next being allowed.
@export var cooldown: float = 1.2

## True while the skater passes through phaseable bodies.
var phased: bool = false
## How many times the shift has fired (HUD, stats, tests).
var activation_count: int = 0

var _dash_left: float = 0.0
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
		skater.velocity = skater.heading * dash_speed
	if phased:
		_phase_left -= delta
		if _phase_left <= 0.0 and not _overlaps_phaseable(skater):
			_end_phase(skater)


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
	_phase_left = phase_duration
	_cooldown_left = cooldown
	skater.set_collision_mask_value(PhysicsLayers.PHASEABLE_LAYER, false)
	skater.set_translucent(true)
	activated.emit()


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
