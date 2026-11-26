class_name SkaterCamera
extends Node3D
## Third person orbit camera for the skater.
##
## This node is the pivot: it is [member Node3D.top_level], follows the skater's position
## and holds the yaw. Its [SpringArm3D] child holds the pitch and pulls the camera in when
## a wall gets between it and the skater. The mouse orbits freely; while the board rolls
## and the mouse has been still for [member follow_delay] seconds, the yaw drifts back
## behind the board.
##
## Mouse motion goes through [method look_mouse], which applies the player's
## [code]Settings.mouse_sensitivity[/code] multiplier ([member sensitivity_scale]), kept live
## through [signal Settings.changed]. [method look] takes the raw motion (tests, scripts).

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")

@export_group("Orbit")
## Radians of turn per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0025
## Lowest pitch (camera high above, looking down), radians.
@export var min_pitch: float = -1.2
## Highest pitch (camera low, looking up), radians.
@export var max_pitch: float = 0.35

@export_group("Follow")
## Height of the pivot above the skater's feet (m).
@export var pivot_height: float = 1.4
## Seconds after the last mouse motion before the camera drifts behind the board.
@export var follow_delay: float = 1.0
## How quickly the yaw catches up with the board (1/s).
@export var follow_rate: float = 2.5
## The camera only drifts behind the board above this speed (m/s).
@export var follow_min_speed: float = 1.5

## Player multiplier on [member mouse_sensitivity] for mouse motion, from Settings.
var sensitivity_scale: float = 1.0

var _since_look: float = INF
var _settings: SETTINGS_SCRIPT = null

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	bind_settings(Settings)


## Follows [param source]'s mouse sensitivity from now on (the Settings autoload by default).
func bind_settings(source: SETTINGS_SCRIPT) -> void:
	if _settings != null and _settings.changed.is_connected(_on_settings_changed):
		_settings.changed.disconnect(_on_settings_changed)
	_settings = source
	if _settings != null:
		_settings.changed.connect(_on_settings_changed)
		_on_settings_changed()


## Orbits by a mouse motion of [param relative] pixels, scaled by the player's setting.
func look_mouse(relative: Vector2) -> void:
	look(relative * sensitivity_scale)


## Orbits by a mouse motion: x turns the yaw, y the pitch (clamped).
func look(relative: Vector2) -> void:
	rotation.y -= relative.x * mouse_sensitivity
	var pitch := spring_arm.rotation.x - relative.y * mouse_sensitivity
	spring_arm.rotation.x = clampf(pitch, min_pitch, max_pitch)
	_since_look = 0.0


## Moves the pivot onto the skater and, when rolling, eases the yaw behind [param heading].
func follow(target: Vector3, heading: Vector3, speed: float, delta: float) -> void:
	global_position = target + Vector3.UP * pivot_height
	_since_look += delta
	if speed < follow_min_speed or _since_look < follow_delay:
		return
	var weight := 1.0 - exp(-follow_rate * delta)
	rotation.y = lerp_angle(rotation.y, _yaw_of(heading), weight)


## Jumps straight behind the board (spawns, respawns, teleports).
func snap_behind(target: Vector3, heading: Vector3) -> void:
	global_position = target + Vector3.UP * pivot_height
	rotation.y = _yaw_of(heading)


static func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _on_settings_changed() -> void:
	sensitivity_scale = _settings.mouse_sensitivity
