class_name OrbitCamera
extends Node3D
## A pivot that orbits its child [Camera3D] around a focus point.
##
## The owner forwards input: [method rotate_by] for a drag, [method zoom_by] for the wheel.
## The camera sits on the pivot's local +Z axis at [member distance], looking at the pivot.
## [method glide_from] starts the camera at another camera's view and eases it into the orbit.
## The camera keeps out of level geometry ([member collision_mask]): when a wall stands
## between the focus and the camera it moves in front of the wall instead of clipping into it.

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
## Physics layers the camera may not pass through (0 turns the check off).
@export_flags_3d_physics var collision_mask: int = PhysicsLayers.WORLD_MASK
## Gap kept between the camera and a wall in the way (m).
@export var wall_margin: float = 0.15
## The camera never comes closer to the focus than this when pushed in by a wall (m).
@export var min_wall_reach: float = 0.25

## Current camera distance from the focus (m).
var distance: float = 2.5:
	set(value):
		distance = clampf(value, min_distance, max_distance)
		_place_camera()
var _yaw: float = 0.0
var _pitch: float = 0.0
var _glide: Tween = null
## Glide start and end as (yaw, pitch, distance).
var _glide_from: Vector3 = Vector3.ZERO
var _glide_to: Vector3 = Vector3.ZERO
## The camera's own field of view, and the source camera's one the glide starts from.
var _orbit_fov: float = 0.0
var _source_fov: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_place_camera()


func _physics_process(_delta: float) -> void:
	_keep_out_of_walls()


## Centres the orbit on [param focus] (global) at [param yaw] / [param pitch] radians.
func frame(focus: Vector3, view_distance: float, yaw: float, pitch: float) -> void:
	global_position = focus
	_yaw = yaw
	_pitch = clampf(pitch, min_pitch, max_pitch)
	distance = view_distance
	_apply_rotation()


## Starts the orbit where [param source] is (seen from the focus) and swings round to the
## current view over [param seconds]: yaw, pitch, distance and field of view ease together,
## so the camera circles the subject instead of cutting through it. Zooming ends it early.
func glide_from(source: Camera3D, seconds: float) -> void:
	if source == null or seconds <= 0.0:
		return
	_stop_glide()
	var offset := source.global_position - global_position
	var length := offset.length()
	if is_zero_approx(length):
		return
	_glide_to = Vector3(_yaw, _pitch, distance)
	_glide_from = Vector3(atan2(offset.x, offset.z), -asin(clampf(offset.y / length, -1.0, 1.0)),
			length)
	_orbit_fov = camera.fov
	_source_fov = source.fov
	_glide = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glide.tween_method(_glide_step, 0.0, 1.0, seconds)
	_glide_step(0.0)


## True while the camera is still easing in from [method glide_from].
func is_gliding() -> bool:
	return _glide != null and _glide.is_running()


## Orbits by a mouse drag of [param relative] pixels.
func rotate_by(relative: Vector2) -> void:
	_stop_glide()
	_yaw -= relative.x * drag_sensitivity
	_pitch = clampf(_pitch - relative.y * drag_sensitivity, min_pitch, max_pitch)
	_apply_rotation()


## Zooms in ([param notches] > 0) or out by wheel notches.
func zoom_by(notches: float) -> void:
	_stop_glide()
	distance = distance * (1.0 - zoom_step * notches)


func _apply_rotation() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)


## One step of the glide, [param weight] 0 (at the source) to 1 (at the orbit view).
func _glide_step(weight: float) -> void:
	_yaw = lerp_angle(_glide_from.x, _glide_to.x, weight)
	_pitch = lerpf(_glide_from.y, _glide_to.y, weight)
	distance = lerpf(_glide_from.z, _glide_to.z, weight)
	camera.fov = lerpf(_source_fov, _orbit_fov, weight)
	_apply_rotation()


## Ends a glide early, keeping the orbit where it is now.
func _stop_glide() -> void:
	if _glide == null:
		return
	_glide.kill()
	_glide = null
	camera.fov = _orbit_fov


func _place_camera() -> void:
	if camera != null:
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, distance))


## Pulls the camera in front of the first wall between the focus and the camera.
func _keep_out_of_walls() -> void:
	if collision_mask == 0 or camera == null or not is_inside_tree():
		return
	var wanted := global_transform * Vector3(0.0, 0.0, distance)
	var query := PhysicsRayQueryParameters3D.create(global_position, wanted, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var reach := distance
	if not hit.is_empty():
		var wall: Vector3 = hit["position"]
		reach = clampf(global_position.distance_to(wall) - wall_margin, min_wall_reach, distance)
	camera.position = Vector3(0.0, 0.0, reach)
