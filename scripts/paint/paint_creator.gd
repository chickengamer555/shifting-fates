class_name PaintCreator
extends Node3D
## The god's paint screen: the player shapes the look of their body or their board.
##
## Shows a white preview built from the skater rig (the mannequin in [enum Mode] PLAYER,
## the board in BOARD) under an orbit camera. Tools: brush (left drag paints dabs),
## fill (click a part to set its base colour) and eraser, with undo (Ctrl+Z), a colour
## picker, preset swatches and a brush size slider. "Done" emits [signal finished] with
## the edited [Appearance]. Pass the same appearance to the board pass so both are kept.
##
## Mouse handling only turns screen points into part hits; the work is done by public
## methods ([method paint_at], [method fill_part], ...) that tests can call headless.

## The player pressed Done. [param appearance] is the edited appearance.
signal finished(appearance: Appearance)

enum Mode { PLAYER, BOARD }
enum Tool { BRUSH, FILL, ERASER }

const SKATER_SCENE := preload("res://scenes/player/skater.tscn")
const RIG_NODE := ^"Rig"
const BODY_PATH := ^"TrickPivot/Body"
const BOARD_PATH := ^"TrickPivot/Board"
const TITLES := {
	Mode.PLAYER: "Imagine what you want to look like",
	Mode.BOARD: "Now do the same for your board",
}
const PRESET_COLORS: Array[Color] = [
	Color.WHITE, Color(0.1, 0.1, 0.1), Color(0.85, 0.15, 0.15), Color(0.95, 0.55, 0.1),
	Color(0.95, 0.85, 0.2), Color(0.2, 0.7, 0.3), Color(0.2, 0.45, 0.9), Color(0.55, 0.3, 0.8),
	Color(0.95, 0.6, 0.75), Color(0.55, 0.35, 0.2), Color(0.9, 0.75, 0.6), Color(0.83, 0.69, 0.22),
]
const SWATCH_SIZE := Vector2(28.0, 28.0)
const SWATCH_BORDER := 3
const GOLD := Color(0.83, 0.69, 0.22)
## Starting view: three-quarters from the rider's front (+X), a little from above.
const VIEW_YAW := PI * 0.5 - 0.5
const VIEW_PITCH := -0.25
## Camera distance per metre of the preview's longest side.
const FRAME_MARGIN := 1.4
## The eraser clears dabs within this many brush diameters of the click.
const ERASE_REACH := 1.0

## Which part of the rig is painted.
@export var mode: Mode = Mode.PLAYER:
	set(value):
		mode = value
		if is_node_ready():
			_refresh_mode()
## Active tool for mouse clicks.
@export var tool: Tool = Tool.BRUSH
## Paint and fill colour.
@export var brush_color: Color = Color(0.85, 0.15, 0.15)
## Brush diameter (m).
@export_range(0.01, 0.5) var brush_size: float = 0.06
## Undo steps kept.
@export var max_undo: int = 32
## When set, Done also saves the appearance there.
@export var save_path: String = ""
## The appearance being edited; a fresh one is made when none is given.
@export var appearance: Appearance

## Dabs currently on the preview (read-only).
var stroke_count: int:
	get:
		return appearance.strokes.size() if appearance != null else 0

var _rig: Node3D
var _shown_parts: Dictionary[StringName, MeshInstance3D] = {}
var _hit_meshes: Dictionary[StringName, TriangleMesh] = {}
var _dabs: Array[Decal] = []
var _undo_stack: Array[Appearance] = []
## True while a mouse drag is painting or erasing, so the whole drag is one undo step.
var _drag_open: bool = false
## State before the open drag; pushed to the undo stack on the drag's first change.
var _drag_snapshot: Appearance
var _orbiting: bool = false

@onready var preview: Node3D = $Preview
@onready var orbit: OrbitCamera = $CameraPivot
@onready var title_label: Label = %Title
@onready var brush_button: Button = %Brush
@onready var fill_button: Button = %Fill
@onready var eraser_button: Button = %Eraser
@onready var color_button: ColorPickerButton = %ColorPicker
@onready var swatches: GridContainer = %Swatches
@onready var size_slider: HSlider = %BrushSize
@onready var undo_button: Button = %Undo
@onready var done_button: Button = %Done


func _ready() -> void:
	if appearance == null:
		appearance = Appearance.new()
	_rig = _extract_rig()
	preview.add_child(_rig)
	_connect_ui()
	_refresh_mode()
	_dabs = appearance.apply_to(_rig)
	orbit.camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_handle_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _orbiting:
			orbit.rotate_by(motion.relative)
		elif _drag_open:
			_use_tool_at(motion.position)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_Z \
			and key.is_command_or_control_pressed():
		undo()
		get_viewport().set_input_as_handled()


## Paints a dab where the screen point [param pos] hits the shown model.
func paint_at_screen(pos: Vector2) -> bool:
	var hit := pick(pos)
	return not hit.is_empty() and paint_at(hit["part"], hit["position"], hit["normal"])


## Paints a dab on [param part_name] at [param local_pos] facing [param normal] (both in
## the part's local space). Refused (false) for parts not shown or dabs that merged.
func paint_at(part_name: StringName, local_pos: Vector3, normal: Vector3) -> bool:
	if not _shown_parts.has(part_name):
		return false
	var snapshot := appearance.snapshot()
	if not appearance.add_stroke(part_name, local_pos, normal, brush_color, brush_size):
		return false
	_record_undo(snapshot)
	while not _dabs.is_empty() and _dabs.size() >= appearance.strokes.size():
		_free_dab(_dabs.pop_front())
	var dab := PaintBrush.make_dab(appearance.strokes.back())
	_shown_parts[part_name].add_child(dab)
	_dabs.append(dab)
	return true


## Sets the base colour of the part under the screen point [param pos].
func fill_at_screen(pos: Vector2) -> bool:
	var hit := pick(pos)
	return not hit.is_empty() and fill_part(hit["part"])


## Sets the base colour of [param part_name] to [member brush_color].
func fill_part(part_name: StringName) -> bool:
	if not _shown_parts.has(part_name):
		return false
	_push_undo(appearance.snapshot())
	appearance.set_part_color(part_name, brush_color)
	_reapply()
	return true


## Erases dabs near the screen point [param pos].
func erase_at_screen(pos: Vector2) -> int:
	var hit := pick(pos)
	return 0 if hit.is_empty() else erase_at(hit["part"], hit["position"])


## Erases the dabs on [param part_name] within reach of [param local_pos].
func erase_at(part_name: StringName, local_pos: Vector3) -> int:
	if not _shown_parts.has(part_name):
		return 0
	var snapshot := appearance.snapshot()
	var removed := appearance.erase_near(part_name, local_pos, brush_size * ERASE_REACH)
	if removed > 0:
		_record_undo(snapshot)
		_reapply()
	return removed


## Takes back the last paint drag, fill or erase. False when there is nothing to undo.
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	appearance.copy_from(_undo_stack.pop_back())
	_reapply()
	return true


## Ends the session: saves when [member save_path] is set and emits [signal finished].
func finish() -> void:
	if not save_path.is_empty():
		appearance.save(save_path)
	finished.emit(appearance)


## The shown part under the screen point [param pos]: a Dictionary with [code]part[/code],
## [code]position[/code] and [code]normal[/code] (local to the part), or empty on a miss.
## Uses the meshes' own triangles, so it needs no physics bodies or physics frame.
func pick(pos: Vector2) -> Dictionary:
	var camera := orbit.camera
	var origin := camera.project_ray_origin(pos)
	var direction := camera.project_ray_normal(pos)
	var best := {}
	var best_distance := INF
	for part_name in _shown_parts:
		var part := _shown_parts[part_name]
		var to_local := part.global_transform.affine_inverse()
		var local_dir := to_local.basis * direction
		var hit := _hit_mesh(part_name).intersect_ray(to_local * origin, local_dir)
		if hit.is_empty():
			continue
		var local_pos: Vector3 = hit["position"]
		var hit_distance := origin.distance_to(part.global_transform * local_pos)
		if hit_distance >= best_distance:
			continue
		var normal: Vector3 = hit["normal"]
		if normal.dot(local_dir) > 0.0:
			normal = -normal
		best_distance = hit_distance
		best = {"part": part_name, "position": local_pos, "normal": normal.normalized()}
	return best


func _handle_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_RIGHT:
			_orbiting = button.pressed
		MOUSE_BUTTON_WHEEL_UP:
			orbit.zoom_by(button.factor if button.factor > 0.0 else 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			orbit.zoom_by(-(button.factor if button.factor > 0.0 else 1.0))
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin_click(button.position)
			else:
				_drag_open = false
				_drag_snapshot = null


func _begin_click(pos: Vector2) -> void:
	if tool == Tool.FILL:
		fill_at_screen(pos)
		return
	_drag_snapshot = appearance.snapshot()
	_drag_open = true
	_use_tool_at(pos)


func _use_tool_at(pos: Vector2) -> void:
	if tool == Tool.ERASER:
		erase_at_screen(pos)
	elif tool == Tool.BRUSH:
		paint_at_screen(pos)


## Records [param snapshot] as one undo step; inside a drag only its first change counts.
func _record_undo(snapshot: Appearance) -> void:
	if not _drag_open:
		_push_undo(snapshot)
	elif _drag_snapshot != null:
		_push_undo(_drag_snapshot)
		_drag_snapshot = null


func _push_undo(snapshot: Appearance) -> void:
	_undo_stack.append(snapshot)
	while _undo_stack.size() > maxi(max_undo, 1):
		_undo_stack.pop_front()


func _reapply() -> void:
	_dabs = appearance.apply_to(_rig)


func _free_dab(dab: Decal) -> void:
	if is_instance_valid(dab):
		dab.get_parent().remove_child(dab)
		dab.queue_free()


func _hit_mesh(part_name: StringName) -> TriangleMesh:
	if not _hit_meshes.has(part_name):
		_hit_meshes[part_name] = _shown_parts[part_name].mesh.generate_triangle_mesh()
	return _hit_meshes[part_name]


## Takes the skater's visual Rig out of a throwaway skater instance (no body, no camera).
func _extract_rig() -> Node3D:
	var skater := SKATER_SCENE.instantiate()
	var rig := skater.get_node(RIG_NODE) as Node3D
	skater.remove_child(rig)
	skater.free()
	return rig


func _refresh_mode() -> void:
	var body := _rig.get_node(BODY_PATH) as Node3D
	var board := _rig.get_node(BOARD_PATH) as Node3D
	body.visible = mode == Mode.PLAYER
	board.visible = mode == Mode.BOARD
	_shown_parts = Appearance.find_parts(body if mode == Mode.PLAYER else board)
	title_label.text = TITLES[mode]
	_frame_camera()


func _frame_camera() -> void:
	var bounds := AABB()
	var first := true
	for part_name in _shown_parts:
		var part := _shown_parts[part_name]
		var part_bounds := part.global_transform * part.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	orbit.frame(bounds.get_center(), bounds.get_longest_axis_size() * FRAME_MARGIN,
			VIEW_YAW, VIEW_PITCH)


func _connect_ui() -> void:
	brush_button.pressed.connect(func() -> void: tool = Tool.BRUSH)
	fill_button.pressed.connect(func() -> void: tool = Tool.FILL)
	eraser_button.pressed.connect(func() -> void: tool = Tool.ERASER)
	brush_button.button_pressed = tool == Tool.BRUSH
	fill_button.button_pressed = tool == Tool.FILL
	eraser_button.button_pressed = tool == Tool.ERASER
	color_button.color = brush_color
	color_button.color_changed.connect(_on_color_picker_color_changed)
	size_slider.value = brush_size
	size_slider.value_changed.connect(_on_brush_size_value_changed)
	undo_button.pressed.connect(undo)
	done_button.pressed.connect(finish)
	for color in PRESET_COLORS:
		swatches.add_child(_make_swatch(color))


func _make_swatch(color: Color) -> Button:
	var swatch := Button.new()
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.tooltip_text = "#" + color.to_html(false)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var highlighted := style.duplicate() as StyleBoxFlat
	highlighted.set_border_width_all(SWATCH_BORDER)
	highlighted.border_color = GOLD
	swatch.add_theme_stylebox_override(&"normal", style)
	swatch.add_theme_stylebox_override(&"hover", highlighted)
	swatch.add_theme_stylebox_override(&"pressed", highlighted)
	swatch.add_theme_stylebox_override(&"focus", highlighted)
	swatch.pressed.connect(_on_color_picker_color_changed.bind(color))
	return swatch


func _on_color_picker_color_changed(color: Color) -> void:
	brush_color = color
	color_button.color = color


func _on_brush_size_value_changed(value: float) -> void:
	brush_size = value
