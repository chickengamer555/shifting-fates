class_name Player
extends CharacterBody3D
## Basic first person walker: WASD relative to facing, gravity, jump and mouse look.

const PITCH_LIMIT := 1.55

@export var speed: float = 5.0
@export var acceleration: float = 12.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

## Off while spectating, so the body ignores keys and mouse.
var input_enabled: bool = true
## False after Esc, so regaining focus doesn't grab the mouse back.
var wants_mouse: bool = true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	set_meta("verify_unit", "Player")
	_capture_mouse.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and wants_mouse:
		_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	# Esc and click work while spectating too, so they come before the input check.
	if event.is_action_pressed("ui_cancel"):
		wants_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.is_pressed():
		wants_mouse = true
		_capture_mouse()
		return
	if not input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if Input.is_action_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var weight := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * speed, weight)
	move_and_slide()


## Turns the body left and right and tilts the head up and down.
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	var pitch := head.rotation.x - relative.y * mouse_sensitivity
	head.rotation.x = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)


## Godot skips a capture request when it already reports CAPTURED, even if the first
## grab was refused (window not focused yet, e.g. embedded in the editor's Game tab).
## Dropping to VISIBLE first forces a fresh grab.
func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
