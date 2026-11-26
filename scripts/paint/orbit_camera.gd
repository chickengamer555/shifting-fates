class_name OrbitCamera
extends Node3D
## A pivot that orbits its child [Camera3D] around a focus point.
##
## The owner forwards input: [method rotate_by] for a drag, [method zoom_by] for the wheel.
## The camera sits on the pivot's local +Z axis at [member distance], looking at the pivot.

## Radians of turn per pixel dragged.
@export var drag_sensitivity: float = 0.008
## Closest and furthest camera distance (m).
@export var min_distance: float = 0.6
@export var max_distance: float = 6.0
## Distance change per wheel notch, as a fraction of the current distance.
@export var zoom_step: float = 0.1
## Pitch limits (radians) so the camera never flips over the top.
@export var min_pitch: float = -1.3
@export var max_pitch: float = 1.3

## Current camera distance from the focus (m).
var distance: float = 2.5:
	set(value):
		distance = clampf(value, min_distance, max_distance)
		_place_camera()
var _yaw: float = 0.0
var _pitch: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_place_camera()


## Centres the orbit on [param focus] (global) at [param yaw] / [param pitch] radians.
func frame(focus: Vector3, view_distance: float, yaw: float, pitch: float) -> void:
	global_position = focus
	_yaw = yaw
	_pitch = clampf(pitch, min_pitch, max_pitch)
	distance = view_distance
	_apply_rotation()


## Orbits by a mouse drag of [param relative] pixels.
func rotate_by(relative: Vector2) -> void:
	_yaw -= relative.x * drag_sensitivity
	_pitch = clampf(_pitch - relative.y * drag_sensitivity, min_pitch, max_pitch)
	_apply_rotation()


## Zooms in ([param notches] > 0) or out by wheel notches.
func zoom_by(notches: float) -> void:
	distance = distance * (1.0 - zoom_step * notches)


func _apply_rotation() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)


func _place_camera() -> void:
	if camera != null:
		camera.position = Vector3(0.0, 0.0, distance)
