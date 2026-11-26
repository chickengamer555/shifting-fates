class_name SpectatorCamera
extends Camera3D
## Free-fly camera: WASD flies where it looks, E/Q go up/down, Shift is faster.

const PITCH_LIMIT := 1.55

@export var fly_speed: float = 8.0
@export var fast_multiplier: float = 4.0
@export var mouse_sensitivity: float = 0.002

var active: bool = false


func _ready() -> void:
	set_meta("verify_unit", "SpectatorCamera")


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative)


func _process(delta: float) -> void:
	if not active:
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var vertical := Input.get_axis("fly_down", "fly_up")
	var direction := global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction += Vector3.UP * vertical
	if direction.length() > 1.0:
		direction = direction.normalized()
	var move_speed := fly_speed
	if Input.is_action_pressed("fly_fast"):
		move_speed *= fast_multiplier
	global_position += direction * move_speed * delta


## Makes this the active view (or not).
func set_active(value: bool) -> void:
	active = value
	current = value


## Yaw around world up, pitch clamped so it can't flip over.
func look(relative: Vector2) -> void:
	rotation.y -= relative.x * mouse_sensitivity
	rotation.x = clampf(rotation.x - relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
