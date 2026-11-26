class_name PaintCreator
extends Node3D
## The god's paint screen: the player paints their body or their board, freely.
##
## Painting happens in place: set [member target_rig] to the real skater's rig before adding
## the creator and it paints that rig where it stands in the level (the body in [enum Mode]
## PLAYER, the board in BOARD; the other half is hidden until Done). Its orbit camera glides
## in from [member glide_from] and circles the rig; a short-range work light on the camera
## keeps the rig readable without relighting the level. Without a target (standalone use,
## tests) it paints a rig of its own under [code]Preview[/code].
## [br]Paint goes into each paintable mesh's texture ([PaintCanvas]): a left drag on the
## model draws a continuous line, fill floods the clicked part, the eraser paints back to
## white, and each drag or fill is one undo step (Ctrl+Z). A left drag off the model, or a
## right drag anywhere, turns the view; the wheel zooms. A ring under the mouse shows the
## brush at the size it paints. Keys: B brush, F fill, E eraser, [ and ] brush size.
## [br]Done stores the painted textures in [member appearance], saves it when
## [member save_path] is set and emits [signal finished]. Pass the same appearance to the
## board pass so both are kept.
## [br]Mouse handling only turns screen points into hits; the work is done by public methods
## ([method paint_at_screen], [method paint_at], [method fill_part], ...) that tests call
## headless. While open the cursor is free ([method MouseCursor.release]) and the clicks and
## drags the creator uses are marked handled, so nothing behind it grabs the mouse.

## The player pressed Done. [param appearance] is the edited appearance.
signal finished(appearance: Appearance)

enum Mode { PLAYER, BOARD }
enum Tool { BRUSH, FILL, ERASER }

const RIG_SCENE := preload("res://scenes/player/skater_rig.tscn")
const BODY_PATH := ^"TrickPivot/Body"
const BOARD_PATH := ^"TrickPivot/Board"
const TITLES: Dictionary[Mode, String] = {
	Mode.PLAYER: "Paint yourself",
	Mode.BOARD: "Paint your board",
}
const HINTS: Dictionary[Mode, String] = {
	Mode.PLAYER: "Drag on yourself to paint  ·  drag the sky or right drag to turn  ·  wheel to zoom",
	Mode.BOARD: "Drag on the board to paint  ·  drag the sky or right drag to turn  ·  wheel to zoom",
}
## Recent colours offered before the player has used any.
const STARTER_COLORS: Array[Color] = [
	Color(0.08, 0.08, 0.09), Color(0.85, 0.15, 0.15), Color(0.95, 0.55, 0.1),
	Color(0.95, 0.85, 0.2), Color(0.2, 0.65, 0.35), Color(0.2, 0.45, 0.9),
	Color(0.55, 0.3, 0.8), Color(0.83, 0.69, 0.22),
]
const RECENT_COUNT := 8
const CHIP_SIZE := Vector2(18.0, 18.0)
const CHIP_RADIUS := 9
const CHIP_RING := 2
const CHIP_RING_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const CHIP_EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.25)
## Font Awesome glyphs of the tool strip.
const ICON_BRUSH := "\uf1fc"
const ICON_FILL := "\uf576"
const ICON_ERASER := "\uf12d"
const ICON_UNDO := "\uf0e2"
const ICON_DOT := "\uf111"
## Weight of the Done label.
const DONE_WEIGHT := 560
## Metadata key holding a recent-colour chip's colour.
const META_CHIP_COLOR := &"chip_color"
## Brush diameter limits (m) and the change per [ or ] key press (a factor).
const MIN_BRUSH := 0.01
const MAX_BRUSH := 0.16
const BRUSH_KEY_FACTOR := 1.25
## Starting view: three-quarters from the rider's front (+X), a little from above. The board
## is looked at more from above, so its deck shows.
const VIEW_YAW := PI * 0.5 - 0.5
const VIEW_PITCH := -0.25
const BOARD_VIEW_PITCH := -0.7
## Camera distance per metre of the shown model's longest side.
const FRAME_MARGIN := 1.35
## The orbit centre sits this fraction of the model's size below its middle, so the model
## shows a little above the screen centre, clear of the tool strip.
const FOCUS_DROP := 0.06
## Screen distance between brush samples along a drag: this fraction of the brush radius on
## screen, but never less than [constant MIN_STEP_PX] pixels.
const STEP_OF_RADIUS := 0.5
const MIN_STEP_PX := 2.0

## Which part of the rig is painted.
@export var mode: Mode = Mode.PLAYER:
	set(value):
		mode = value
		if is_node_ready():
			_refresh_mode()
## Active tool for mouse clicks.
@export var tool: Tool = Tool.BRUSH:
	set(value):
		tool = value
		if is_node_ready():
			_sync_tool_buttons()
## Paint and fill colour.
@export var brush_color: Color = Color(0.85, 0.15, 0.15):
	set(value):
		brush_color = value
		if is_node_ready():
			_show_brush_color()
## Brush diameter in metres on the model.
@export_range(0.01, 0.16) var brush_size: float = 0.04
## Undo steps kept.
@export var max_undo: int = 32
## When set, Done also saves the appearance there.
@export var save_path: String = ""
## The appearance being edited; a fresh one is made when none is given.
@export var appearance: Appearance
## Seconds the camera takes to glide from [member glide_from] to its orbit.
@export var glide_seconds: float = 1.2

## The rig to paint, set before the creator enters the tree (the intro passes the skater's
## [code]Rig[/code]). Null: the creator makes a rig of its own under [code]Preview[/code].
var target_rig: Node3D = null
## Camera the view glides in from (e.g. the skater's). Null: the orbit view shows at once.
var glide_from: Camera3D = null
## The texture painter of the shown half of the rig.
var canvas: PaintCanvas
## Strokes and fills that can still be undone.
var stroke_count: int:
	get:
		return canvas.undo_count if canvas != null else 0

var _rig: Node3D
var _shown_meshes: Array[MeshInstance3D] = []
## True while a left drag paints or erases.
var _painting: bool = false
## True while a drag turns the view.
var _orbiting: bool = false
## Last screen point of the open stroke, for stepping along the drag.
var _last_screen: Vector2 = Vector2.ZERO
var _has_last_screen: bool = false
## Visibility of the rig's body and board before painting, put back by [method finish].
var _rig_visibility: Dictionary[NodePath, bool] = {}
var _recent: Array[Color] = []
var _finished: bool = false
## False until picking has been switched to the pose the rig is drawn with (it is recorded
## on the rig's first skeleton update after the canvas is made).
var _pose_synced: bool = false

@onready var preview: Node3D = $Preview
@onready var orbit: OrbitCamera = $CameraPivot
@onready var title_label: Label = %Title
@onready var hint_label: Label = %Hint
@onready var brush_button: Button = %Brush
@onready var fill_button: Button = %Fill
@onready var eraser_button: Button = %Eraser
@onready var current_chip: Button = %Current
@onready var recent_row: HBoxContainer = %Recent
@onready var palette: Control = %Palette
@onready var picker: ColorPicker = %Picker
@onready var size_slider: HSlider = %BrushSize
@onready var size_small: Label = %SizeSmall
@onready var size_large: Label = %SizeLarge
@onready var undo_button: Button = %Undo
@onready var done_button: Button = %Done
@onready var brush_cursor: PaintCursor = %BrushCursor


func _ready() -> void:
	if appearance == null:
		appearance = Appearance.new()
	MouseCursor.release()
	_rig = target_rig
	if _rig == null:
		_rig = RIG_SCENE.instantiate() as Node3D
		preview.add_child(_rig)
	for path: NodePath in [BODY_PATH, BOARD_PATH]:
		var part := _rig.get_node_or_null(path) as Node3D
		if part != null:
			_rig_visibility[path] = part.visible
	_recent = STARTER_COLORS.duplicate()
	_connect_ui()
	_refresh_mode()
	orbit.camera.make_current()
	if glide_from != null:
		orbit.glide_from(glide_from, glide_seconds)


func _exit_tree() -> void:
	# A creator that was never finished still gives the rig back. A finished one already
	# did; doing it again here (it is freed a frame later) would show the body again while
	# the next pass (the board) is painting.
	if not _finished:
		_restore_rig()


func _process(_delta: float) -> void:
	if canvas != null:
		canvas.flush()
		if not _pose_synced and canvas.has_drawn_pose():
			canvas.refresh_pose()
			_pose_synced = true
	_update_cursor()


## Motion and release of a drag are read here, before the tool strip can take them, so a
## drag that ends over the strip still ends (and never keeps painting on hover).
func _input(event: InputEvent) -> void:
	if not (_painting or _orbiting):
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _painting:
			_stroke_screen_to(motion.position)
		else:
			orbit.rotate_by(motion.relative)
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and not button.pressed and button.button_index in [
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_end_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		_handle_press(button)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and _handle_key(key):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_drag()


## Paints at the screen point [param pos]: inside an open stroke ([method begin_stroke]) the
## line goes on from the last point, otherwise it is a single dab (its own undo step).
## False when the point misses the shown model.
func paint_at_screen(pos: Vector2) -> bool:
	if canvas.is_stroke_open():
		return _stroke_screen_to(pos)
	var hit := pick(pos)
	if hit.is_empty():
		return false
	_dab(hit)
	return true


## Opens a stroke for [method paint_at_screen] calls (what a mouse drag does).
func begin_stroke() -> void:
	_apply_brush()
	canvas.begin_stroke()
	_has_last_screen = false


## Closes the stroke opened by [method begin_stroke]. True when it painted anything.
func end_stroke() -> bool:
	_has_last_screen = false
	var changed := canvas.end_stroke()
	if changed and tool == Tool.BRUSH:
		_remember_color(brush_color)
	return changed


## Paints a dab on the part [param part_name] at [param local_pos] facing [param normal]
## (both local to the part). Refused (false) for parts not shown or points off the part.
func paint_at(part_name: StringName, local_pos: Vector3, normal: Vector3) -> bool:
	var mesh := _shown_mesh(part_name)
	if mesh == null:
		return false
	var hit := canvas.hit_on(mesh, local_pos, normal)
	if hit.is_empty():
		return false
	_dab(hit)
	return true


## Floods the part under the screen point [param pos] with [member brush_color].
func fill_at_screen(pos: Vector2) -> bool:
	var hit := pick(pos)
	return not hit.is_empty() and fill_part(hit["part"])


## Floods the whole part [param part_name] with [member brush_color]. One undo step.
func fill_part(part_name: StringName) -> bool:
	var mesh := _shown_mesh(part_name)
	if mesh == null or not canvas.fill_mesh(mesh, brush_color):
		return false
	_remember_color(brush_color)
	return true


## Erases (paints back to white) a dab under the screen point [param pos]. Returns 1 when
## it changed anything, else 0.
func erase_at_screen(pos: Vector2) -> int:
	var hit := pick(pos)
	if hit.is_empty():
		return 0
	return 1 if _dab(hit, true) else 0


## Erases a dab on [param part_name] at [param local_pos] (local to the part). Returns 1
## when it changed anything, else 0.
func erase_at(part_name: StringName, local_pos: Vector3) -> int:
	var mesh := _shown_mesh(part_name)
	if mesh == null:
		return 0
	var outward := local_pos - mesh.get_aabb().get_center()
	var hit := canvas.hit_on(mesh, local_pos, outward if outward.length() > 0.0 else Vector3.UP)
	if hit.is_empty():
		return 0
	return 1 if _dab(hit, true) else 0


## Takes back the last stroke or fill. False when there is nothing to undo.
func undo() -> bool:
	_painting = false
	_has_last_screen = false
	return canvas.undo()


## Ends the session: stores the painted textures in [member appearance], saves it when
## [member save_path] is set and emits [signal finished].
func finish() -> void:
	if _finished:
		return
	_finished = true
	_end_drag()
	canvas.store_into(appearance)
	canvas.finalize_for_play()
	_restore_rig()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if not save_path.is_empty():
		appearance.save(save_path)
	finished.emit(appearance)


## The shown part under the screen point [param pos]: the [PaintCanvas] hit plus
## [code]part[/code] (the mesh's node name), or empty on a miss. Uses the meshes' own
## triangles, so it needs no physics bodies or physics frame.
func pick(pos: Vector2) -> Dictionary:
	var camera := orbit.camera
	var hit := canvas.pick_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos),
			_shown_meshes)
	if not hit.is_empty():
		hit["part"] = StringName((hit["layer"] as PaintLayer).mesh_instance.name)
	return hit


## How many pixels across the brush radius is at the world point [param at].
func brush_radius_px(at: Vector3) -> float:
	var camera := orbit.camera
	if camera.is_position_behind(at):
		return 0.0
	var side := camera.global_basis.x * brush_size * 0.5
	return camera.unproject_position(at).distance_to(camera.unproject_position(at + side))


func _dab(hit: Dictionary, erase: bool = false) -> bool:
	_apply_brush()
	canvas.erasing = erase
	if canvas.is_stroke_open():
		canvas.stroke_to(hit)
		return true
	canvas.begin_stroke()
	canvas.stroke_to(hit)
	var changed := canvas.end_stroke()
	if changed and not erase:
		_remember_color(brush_color)
	return changed


func _apply_brush() -> void:
	canvas.brush_size = brush_size
	canvas.color = brush_color
	canvas.erasing = tool == Tool.ERASER
	canvas.max_undo = max_undo


## Paints along the screen from the last point of the stroke to [param pos], a sample every
## few pixels, so fast drags stay continuous and seams between them break cleanly.
func _stroke_screen_to(pos: Vector2) -> bool:
	var targets: Array[Vector2] = [pos]
	if _has_last_screen:
		var first := pick(pos)
		var radius := brush_radius_px(first["world"] as Vector3) if not first.is_empty() \
				else brush_radius_px(orbit.global_position)
		var step := maxf(radius * STEP_OF_RADIUS, MIN_STEP_PX)
		var steps := ceili(_last_screen.distance_to(pos) / step)
		targets.clear()
		for i in range(1, steps + 1):
			targets.append(_last_screen.lerp(pos, float(i) / steps))
	var any := false
	for target in targets:
		var hit := pick(target)
		canvas.stroke_to(hit)
		any = any or not hit.is_empty()
	_last_screen = pos
	_has_last_screen = true
	return any


func _handle_press(button: InputEventMouseButton) -> void:
	_close_palette()
	match button.button_index:
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_orbiting = true
		MOUSE_BUTTON_WHEEL_UP:
			orbit.zoom_by(button.factor if button.factor > 0.0 else 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			orbit.zoom_by(-(button.factor if button.factor > 0.0 else 1.0))
		MOUSE_BUTTON_LEFT:
			_begin_left_drag(button.position)


func _begin_left_drag(pos: Vector2) -> void:
	canvas.refresh_pose()
	var hit := pick(pos)
	if hit.is_empty():
		_orbiting = true
		return
	if tool == Tool.FILL:
		fill_part(hit["part"])
		return
	begin_stroke()
	_painting = true
	_stroke_screen_to(pos)


func _end_drag() -> void:
	if _painting:
		end_stroke()
	_painting = false
	_orbiting = false


func _handle_key(key: InputEventKey) -> bool:
	if key.keycode == KEY_Z and key.is_command_or_control_pressed():
		undo()
		return true
	if key.is_command_or_control_pressed() or key.alt_pressed:
		return false
	match key.keycode:
		KEY_B:
			tool = Tool.BRUSH
		KEY_F:
			tool = Tool.FILL
		KEY_E:
			tool = Tool.ERASER
		KEY_BRACKETLEFT:
			_set_brush_size(brush_size / BRUSH_KEY_FACTOR)
		KEY_BRACKETRIGHT:
			_set_brush_size(brush_size * BRUSH_KEY_FACTOR)
		_:
			return false
	return true


## Moves the brush ring to the mouse; hidden over the tool strip and while turning the view.
func _update_cursor() -> void:
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var over_ui := viewport.gui_get_hovered_control() != null
	if over_ui or _orbiting or _finished:
		brush_cursor.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var hit := pick(mouse)
	var at: Vector3 = hit["world"] if not hit.is_empty() else orbit.global_position
	var shown := brush_color if tool != Tool.ERASER else Color.WHITE
	brush_cursor.show_at(mouse, brush_radius_px(at), shown, tool == Tool.FILL)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if not hit.is_empty()
			else Input.CURSOR_ARROW)


func _shown_mesh(part_name: StringName) -> MeshInstance3D:
	for mesh in _shown_meshes:
		if mesh.name == part_name:
			return mesh
	return null


## Shows the rig's body and board as they were before painting.
func _restore_rig() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	for path: NodePath in _rig_visibility:
		(_rig.get_node(path) as Node3D).visible = _rig_visibility[path]


func _refresh_mode() -> void:
	if canvas != null:
		canvas.end_stroke()
		canvas.store_into(appearance)
	var body := _rig.get_node_or_null(BODY_PATH) as Node3D
	var board := _rig.get_node_or_null(BOARD_PATH) as Node3D
	if body != null:
		body.visible = mode == Mode.PLAYER
	if board != null:
		board.visible = mode == Mode.BOARD
	var shown: Node3D = body if mode == Mode.PLAYER else board
	if shown == null:
		push_warning("PaintCreator: the rig has no %s" % [BODY_PATH if mode == Mode.PLAYER
				else BOARD_PATH])
		shown = _rig
	canvas = PaintCanvas.new(_rig, appearance, shown)
	canvas.max_undo = max_undo
	_pose_synced = false
	_shown_meshes = PaintCanvas.paintable_meshes(shown)
	title_label.text = TITLES[mode]
	hint_label.text = HINTS[mode]
	_frame_camera()


func _frame_camera() -> void:
	var bounds := AABB()
	var first := true
	for mesh in _shown_meshes:
		var mesh_bounds := mesh.global_transform * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	if first:
		bounds = AABB(_rig.global_position, Vector3.ONE)
	# The view yaw is relative to the rig, so it frames the rider's front however it stands.
	var rig_yaw := _rig.global_basis.get_euler().y
	var size := bounds.get_longest_axis_size()
	var pitch := VIEW_PITCH if mode == Mode.PLAYER else BOARD_VIEW_PITCH
	orbit.frame(bounds.get_center() + Vector3.DOWN * size * FOCUS_DROP, size * FRAME_MARGIN,
			rig_yaw + VIEW_YAW, pitch)


func _connect_ui() -> void:
	title_label.add_theme_font_override(&"font", FontLibrary.title_font())
	done_button.add_theme_font_override(&"font", FontLibrary.ui_font(DONE_WEIGHT))
	brush_button.text = ICON_BRUSH
	fill_button.text = ICON_FILL
	eraser_button.text = ICON_ERASER
	undo_button.text = ICON_UNDO
	size_small.text = ICON_DOT
	size_large.text = ICON_DOT
	brush_button.pressed.connect(func() -> void: tool = Tool.BRUSH)
	fill_button.pressed.connect(func() -> void: tool = Tool.FILL)
	eraser_button.pressed.connect(func() -> void: tool = Tool.ERASER)
	_sync_tool_buttons()
	current_chip.pressed.connect(_on_current_pressed)
	picker.color = brush_color
	picker.color_changed.connect(_on_picker_color_changed)
	size_slider.min_value = MIN_BRUSH
	size_slider.max_value = MAX_BRUSH
	size_slider.value = brush_size
	size_slider.value_changed.connect(_on_brush_size_value_changed)
	undo_button.pressed.connect(undo)
	done_button.pressed.connect(finish)
	palette.visible = false
	_rebuild_recent()
	_show_brush_color()


func _sync_tool_buttons() -> void:
	brush_button.set_pressed_no_signal(tool == Tool.BRUSH)
	fill_button.set_pressed_no_signal(tool == Tool.FILL)
	eraser_button.set_pressed_no_signal(tool == Tool.ERASER)


func _set_brush_size(value: float) -> void:
	brush_size = clampf(value, MIN_BRUSH, MAX_BRUSH)
	size_slider.set_value_no_signal(brush_size)


## Shows [member brush_color] on the current chip, the wheel and the recent colours.
func _show_brush_color() -> void:
	var color := brush_color
	_style_chip(current_chip, color, true)
	if not picker.color.is_equal_approx(color):
		picker.color = color
	for chip in recent_row.get_children():
		var chip_color: Color = chip.get_meta(META_CHIP_COLOR)
		_style_chip(chip as Button, chip_color, chip_color.is_equal_approx(color))


## Puts [param color] first in the recent colours.
func _remember_color(color: Color) -> void:
	for i in range(_recent.size() - 1, -1, -1):
		if _recent[i].is_equal_approx(color):
			_recent.remove_at(i)
	_recent.push_front(color)
	_recent.resize(mini(_recent.size(), RECENT_COUNT))
	_rebuild_recent()


func _rebuild_recent() -> void:
	for child in recent_row.get_children():
		recent_row.remove_child(child)
		child.queue_free()
	for color in _recent:
		var chip := Button.new()
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_NONE
		chip.tooltip_text = "#" + color.to_html(false)
		chip.set_meta(META_CHIP_COLOR, color)
		_style_chip(chip, color, color.is_equal_approx(brush_color))
		chip.pressed.connect(_on_recent_pressed.bind(color))
		recent_row.add_child(chip)


## A round colour chip; [param ringed] gives it a thin white ring.
static func _style_chip(chip: Button, color: Color, ringed: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(CHIP_RADIUS)
	style.set_border_width_all(CHIP_RING if ringed else 1)
	style.border_color = CHIP_RING_COLOR if ringed else CHIP_EDGE_COLOR
	style.anti_aliasing = true
	var hover := style.duplicate() as StyleBoxFlat
	hover.set_border_width_all(CHIP_RING)
	hover.border_color = CHIP_RING_COLOR
	for state: StringName in [&"normal", &"focus", &"disabled"]:
		chip.add_theme_stylebox_override(state, style)
	for state: StringName in [&"hover", &"pressed", &"hover_pressed"]:
		chip.add_theme_stylebox_override(state, hover)


func _close_palette() -> void:
	palette.visible = false


func _on_current_pressed() -> void:
	palette.visible = not palette.visible


func _on_picker_color_changed(color: Color) -> void:
	brush_color = color


func _on_recent_pressed(color: Color) -> void:
	brush_color = color
	if tool == Tool.ERASER:
		tool = Tool.BRUSH


func _on_brush_size_value_changed(value: float) -> void:
	brush_size = value
