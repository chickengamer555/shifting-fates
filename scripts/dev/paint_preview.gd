extends Node
## Dev preview of the paint step: opens the intro at its paint step and draws with real
## mouse events, one motion per frame, so recorded frames show strokes being painted.
## User args (after [code]--[/code]): [code]--stage body[/code] (default: a zigzag on the
## torso and a smile on the head), [code]--stage palette[/code] (the colour wheel open) or
## [code]--stage board[/code] (Done, then the board pass with a stripe down the deck).
## The look is saved to a preview file, never to the player's own.

const INTRO_PAINT := preload("res://scenes/dev/intro_paint.tscn")
const SAVE_PATH := "user://paint_preview_appearance.tres"
## Frames to wait for the camera glide before drawing.
const SETTLE_FRAMES := 45
const ZIGZAG: Array[Vector2] = [
	Vector2(-45, -50), Vector2(40, -25), Vector2(-40, 0), Vector2(40, 25), Vector2(-45, 50),
]
const SMILE_POINTS := 10
const SMILE_RADIUS := 14.0
const STEP_PX := 9.0
const DIALOGUE_ADVANCES := 2
## Bone each body part is aimed at, and how far along the bone (metres) its middle is.
const AIM_BONES: Dictionary[String, String] = {"Head": "Head", "Torso": "spine_02"}
const AIM_ALONG: Dictionary[String, float] = {"Head": 0.12, "Torso": 0.0}

var _intro: Node
## Global transforms of the aimed-at bones as last drawn (read when the skeleton hands its
## pose to the skin, so after the SkaterPose modifier); body parts are aimed at from them.
var _drawn: Dictionary[String, Transform3D] = {}
var _actions: Array[Callable] = []
var _wait: int = SETTLE_FRAMES


func _ready() -> void:
	GameState.appearance_path = SAVE_PATH
	_intro = INTRO_PAINT.instantiate()
	add_child(_intro)
	var skeleton := _intro.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		skeleton.skeleton_updated.connect(func() -> void:
			for part: String in AIM_BONES:
				var bone := skeleton.find_bone(AIM_BONES[part])
				if bone >= 0:
					_drawn[part] = skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	var stage := "body"
	var args := OS.get_cmdline_user_args()
	var at := args.find("--stage")
	if at >= 0 and at + 1 < args.size():
		stage = args[at + 1]
	match stage:
		"palette":
			_queue_body()
			_actions.append(_open_palette)
		"board":
			_queue_body()
			_actions.append(_finish_body)
			for _i in range(SETTLE_FRAMES):
				_actions.append(func() -> void: pass)
			_actions.append(_queue_board)
		_:
			_queue_body()
			_actions.append(_hover_cursor)


func _process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		return
	if not _actions.is_empty():
		(_actions.pop_front() as Callable).call()


func _creator() -> PaintCreator:
	return _intro.get_node_or_null("PaintCreator") as PaintCreator


func _part_on_screen(part_name: String) -> Vector2:
	var creator := _creator()
	if _drawn.has(part_name):
		var pose := _drawn[part_name]
		return creator.orbit.camera.unproject_position(
				pose.origin + pose.basis.y.normalized() * AIM_ALONG[part_name])
	var mesh := creator.find_child(part_name, true, false) as MeshInstance3D
	if mesh == null:
		mesh = _intro.find_child(part_name, true, false) as MeshInstance3D
	return creator.orbit.camera.unproject_position(
			mesh.global_transform * mesh.get_aabb().get_center())


func _queue_body() -> void:
	_actions.append(func() -> void: _queue_stroke("Torso", ZIGZAG, Color(0.85, 0.15, 0.15)))
	_actions.append(func() -> void:
		var smile: Array[Vector2] = []
		for i in range(SMILE_POINTS + 1):
			var angle := lerpf(0.2, PI - 0.2, float(i) / SMILE_POINTS)
			smile.append(Vector2(cos(angle), sin(angle)) * SMILE_RADIUS)
		_queue_stroke("Head", smile, Color(0.08, 0.08, 0.09)))


func _queue_board() -> void:
	var stripe: Array[Vector2] = [Vector2(-120, 0), Vector2(120, 0)]
	_queue_stroke("Deck", stripe, Color(0.83, 0.69, 0.22))


## Queues a drag through [param offsets] (pixels from the part's centre on screen).
func _queue_stroke(part_name: String, offsets: Array[Vector2], color: Color) -> void:
	var centre := _part_on_screen(part_name)
	var points: Array[Vector2] = []
	for i in range(offsets.size() - 1):
		var a := centre + offsets[i]
		var b := centre + offsets[i + 1]
		var steps := maxi(ceili(a.distance_to(b) / STEP_PX), 1)
		for s in range(steps):
			points.append(a.lerp(b, float(s) / steps))
	points.append(centre + offsets.back())
	var steps_now: Array[Callable] = []
	steps_now.append(func() -> void:
		_creator().brush_color = color
		_button(points[0], true))
	for i in range(1, points.size()):
		steps_now.append(_motion.bind(points[i - 1], points[i], MOUSE_BUTTON_MASK_LEFT))
	steps_now.append(func() -> void: _button(points.back(), false))
	steps_now.append_array(_actions)
	_actions = steps_now


func _hover_cursor() -> void:
	var at := _part_on_screen("Torso") + Vector2(60, -20)
	Input.warp_mouse(at)
	_motion(at, at, 0)


func _open_palette() -> void:
	_creator().palette.visible = true
	_hover_cursor()


func _finish_body() -> void:
	_creator().finish()
	var box := _intro.get_node("UI/DialogueBox") as DialogueBox
	for _i in range(DIALOGUE_ADVANCES):
		box.advance()


func _button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)


func _motion(from: Vector2, to: Vector2, held: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = held
	get_viewport().push_input(event, true)
