class_name RocketBoostAbility
extends SkaterAbility
## Rocket boost: hold middle mouse to blast forward.
##
## While boosting, the skater's horizontal speed grows by [member acceleration] along the
## way it is already rolling (or along [member forward] when slower than
## [member min_direction_speed]), up to [member max_boost_speed]. Boosting burns
## [member fuel] (0..1). A boost starts on a fresh press with at least
## [member min_start_fuel]; it stops when released or when the tank runs dry, and then
## needs a new press. Fuel refills on the ground while not boosting.
##
## A [CPUParticles3D] child named [code]PixelSpray[/code] (small unshaded squares with
## nearest filtering) sprays out behind the skater only while boosting. The ability only
## edits [code]velocity[/code]; the Skater keeps its own movement and adopts the boosted
## speed. The Skater feeds [member forward] (its facing) through [method update_aim] every
## frame. Locked until the story unlocks it: [member enabled] starts false and
## [member SkaterAbility.unlock_id] is [code]rocket[/code]. Disabling it stops the boost.

const BOOST_ACTION := "rocket_boost"
## GameState id that unlocks the boost.
const UNLOCK_ID := &"rocket"

## Horizontal speed gained per second while boosting (m/s²).
@export var acceleration: float = 30.0
## The boost never pushes horizontal speed above this (m/s).
@export var max_boost_speed: float = 28.0
## Fuel burned per second of boosting (a full tank lasts 1 / this seconds).
@export var drain_per_second: float = 0.4
## Fuel regained per second on the ground while not boosting.
@export var recharge_per_second: float = 0.5
## Fuel needed to start a boost.
@export var min_start_fuel: float = 0.1
## Below this horizontal speed (m/s) the boost pushes along [member forward].
@export var min_direction_speed: float = 1.0
## How far (m) above the skater's origin the spray comes out.
@export var spray_height: float = 0.2

## The skater's facing, used when it is too slow to have a direction of travel.
var forward: Vector3 = Vector3.FORWARD
## Tank level, 0 (empty) .. 1 (full).
var fuel: float = 1.0
## True while the boost is pushing.
var boosting: bool = false

var _was_held: bool = false

@onready var _spray: CPUParticles3D = $PixelSpray


func _init() -> void:
	enabled = false
	unlock_id = UNLOCK_ID


func _ready() -> void:
	_spray.emitting = false


func physics_tick(skater: CharacterBody3D, delta: float) -> void:
	var held := input_enabled and Input.is_action_pressed(BOOST_ACTION)
	var pressed := held and not _was_held
	_was_held = held
	if boosting and (not held or fuel <= 0.0):
		_set_boosting(false)
	elif not boosting and pressed and fuel >= min_start_fuel:
		_set_boosting(true)
	if boosting:
		var direction := _boost_direction(skater.velocity)
		_push(skater, direction, delta)
		fuel = maxf(fuel - drain_per_second * delta, 0.0)
		_aim_spray(skater, direction)
	elif skater.is_on_floor():
		fuel = minf(fuel + recharge_per_second * delta, 1.0)


func update_aim(_view_forward: Vector3, facing: Vector3) -> void:
	forward = facing


func is_active() -> bool:
	return boosting


func _on_disabled() -> void:
	_was_held = false
	if boosting:
		_set_boosting(false)


func _boost_direction(velocity: Vector3) -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() >= min_direction_speed:
		return flat.normalized()
	var facing := Vector3(forward.x, 0.0, forward.z)
	return facing.normalized() if not facing.is_zero_approx() else Vector3.FORWARD


## Raises the speed along [param direction] (keeping any sideways and vertical motion),
## never past max_boost_speed.
func _push(skater: CharacterBody3D, direction: Vector3, delta: float) -> void:
	var flat := Vector3(skater.velocity.x, 0.0, skater.velocity.z)
	var along := flat.dot(direction)
	if along >= max_boost_speed:
		return
	var boosted := minf(along + acceleration * delta, max_boost_speed)
	skater.velocity += direction * (boosted - along)


## Places the spray behind the skater with its +Z (the emit direction) pointing back.
func _aim_spray(skater: CharacterBody3D, direction: Vector3) -> void:
	var origin := skater.global_position + Vector3.UP * spray_height
	_spray.global_transform = Transform3D(Basis.looking_at(direction), origin)


func _set_boosting(on: bool) -> void:
	boosting = on
	_spray.emitting = on
	if on:
		activated.emit()
	else:
		deactivated.emit()
