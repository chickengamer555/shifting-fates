class_name PaintCreator
extends Node3D
## The god's paint screen: the player paints their body or their board, freely.
##
## Painting happens in place: set [member target_rig] to the real skater's rig before adding
## the creator and it paints that rig where it stands in the level (the body in [enum Mode]
## PLAYER, the board in BOARD; the other half is hidden until Done). The rig is held still
## while the creator is open (its animation and pose springs stop), so paint lands where the
## model is drawn; its skeleton keeps drawing even while the game is paused (Repaint opens
## the creator from the pause menu). Its orbit camera glides in from [member glide_from] and
## circles the rig; a short-range work light on the camera keeps the rig readable without
## relighting the level. Without a target (standalone use, tests) it paints a rig of its own
## under [code]Preview[/code].
## [br]Paint goes into each paintable mesh's texture ([PaintCanvas]) and carries on from the
## paint the rig already shows. Tools: the brush draws a continuous line (opacity, edge
## softness and a mirror that paints the other side too), the bucket floods the connected
## area of one colour (or the whole part, [enum FillMode]), the eraser paints back to the
## unpainted look, the eyedropper takes a colour off the model and the finish tool gives the
## clicked part a material finish ([PaintFinish]) and then goes back to the paint tool.
## Each stroke, fill or finish is one undo step (Ctrl+Z). A left drag off the model, or a
## right drag anywhere, turns the view; the wheel zooms. A ring under the mouse shows the
## brush at the size it paints. Keys: B brush, F fill, E eraser, I eyedropper (or
## Alt+click), M finish, X mirror, [ and ] brush size.
## [br]Done stores the painted textures and finishes in [member appearance] (loaded from
## [member save_path] when none is given, so the whole saved look is kept), saves it when
## [member save_path] is set and emits [signal finished].
## [br]The tools sit in a side panel in the gods' style (Cinzel headings, warm light);
## [code]UI/Palette[/code] is the colour wheel that opens beside it.
## [br]Mouse handling only turns screen points into hits; the work is done by public methods
## ([method paint_at_screen], [method paint_at], [method fill_at], ...) that tests call
## headless. While open the cursor is free ([method MouseCursor.release]) and the clicks and
## drags the creator uses are marked handled, so nothing behind it grabs the mouse.

## The player pressed Done. [param appearance] is the edited appearance.
signal finished(appearance: Appearance)

enum Mode { PLAYER, BOARD }
enum Tool { BRUSH, FILL, ERASER, PICK, FINISH }
## What the fill tool floods: the connected area of the clicked colour, or the whole part.
enum FillMode { CONNECTED, WHOLE_PART }

## The tools that put paint on (the eyedropper and finish tool go back to the last of them).
const PAINT_TOOLS: Array[Tool] = [Tool.BRUSH, Tool.FILL, Tool.ERASER]
const RIG_SCENE := preload("res://scenes/player/skater_rig.tscn")
const BODY_PATH := ^"TrickPivot/Body"
const BOARD_PATH := ^"TrickPivot/Board"
const TITLES: Dictionary[Mode, String] = {
	Mode.PLAYER: "Paint yourself",
	Mode.BOARD: "Paint your board",
}
const HINT_TURN := "drag the sky or right drag to turn  ·  wheel to zoom"
const HINTS: Dictionary[Mode, String] = {
	Mode.PLAYER: "Drag on yourself to paint  ·  " + HINT_TURN,
	Mode.BOARD: "Drag on the board to paint  ·  " + HINT_TURN,
}
## What the panel says once a finish went on: the whole shown half, or one part.
const FINISH_DONE_TEXT: Dictionary[Mode, String] = {
	Mode.PLAYER: "Whole body is now %s",
	Mode.BOARD: "Whole board is now %s",
}
const PART_FINISH_DONE_TEXT := "That part is now %s"
## Seconds a confirmation stays in the hint line.
const CONFIRM_SECONDS := 2.5
## The studio sky lent to the view where the world has no sky of its own, so glossy, metal
## and chrome finishes have something to reflect: its top, horizon and ground colours.
const STUDIO_SKY_TOP := Color(0.62, 0.64, 0.7)
const STUDIO_SKY_HORIZON := Color(0.95, 0.92, 0.86)
const STUDIO_GROUND := Color(0.08, 0.08, 0.1)
const FINISH_ALL_TEXT: Dictionary[Mode, String] = {
	Mode.PLAYER: "Whole body %s",
	Mode.BOARD: "Whole board %s",
}
const TOOL_NAMES: Dictionary[Tool, String] = {
	Tool.BRUSH: "Brush  ·  B",
	Tool.FILL: "Paint bucket  ·  F",
	Tool.ERASER: "Eraser  ·  E",
	Tool.PICK: "Eyedropper  ·  I",
	Tool.FINISH: "Click a part to make it %s  ·  M",
}
## The two parts that mirror each other in each mode: the mirror plane runs between them.
const MIRROR_PAIRS: Dictionary[Mode, Array] = {
	Mode.PLAYER: [&"ArmL", &"ArmR"],
	Mode.BOARD: [&"WheelFL", &"WheelFR"],
}
## Recent colours offered before the player has used any.
const STARTER_COLORS: Array[Color] = [
	Color(0.08, 0.08, 0.09), Color(0.96, 0.95, 0.92), Color(0.85, 0.15, 0.15),
	Color(0.95, 0.55, 0.1), Color(0.95, 0.85, 0.2), Color(0.2, 0.65, 0.35),
	Color(0.2, 0.45, 0.9), Color(0.55, 0.3, 0.8), Color(0.83, 0.69, 0.22),
	Color(0.9, 0.45, 0.6),
]
const RECENT_COUNT := 10
const RECENT_COLUMNS := 5
const CHIP_SIZE := Vector2(24.0, 24.0)
const CHIP_RADIUS := 12
const CHIP_RING := 2
## The warm light of the gods' UI (as on the menu's wishes).
const LIGHT := Color(1.0, 0.96, 0.86, 1.0)
const CHIP_EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.22)
const CHIP_GLOW := 10
## Font Awesome glyphs of the tools.
const ICON_BRUSH := ""
const ICON_FILL := ""
const ICON_ERASER := ""
const ICON_PICK := ""
const ICON_FINISH := ""
const ICON_UNDO := ""
const ICON_DOT := ""
## Cinzel weight of the headings and Done.
const HEADING_WEIGHT := 600
## Metadata keys: a recent-colour chip's colour, a finish button's finish.
const META_CHIP_COLOR := &"chip_color"
const META_FINISH := &"finish"
## Brush diameter limits (m) and the change per [ or ] key press (a factor).
const MIN_BRUSH := 0.01
const MAX_BRUSH := 0.16
const BRUSH_KEY_FACTOR := 1.25
const MIN_OPACITY := 0.05
## Starting view: three-quarters from the rider's front (+X), a little from above. The board
## is looked at more from above, so its deck shows.
const VIEW_YAW := PI * 0.5 - 0.5
const VIEW_PITCH := -0.25
const BOARD_VIEW_PITCH := -0.7
## Camera distance per metre of the shown model's longest side.
const FRAME_MARGIN := 1.35
## The orbit centre sits this fraction of the model's size below its middle.
const FOCUS_DROP := 0.02
## Screen distance between brush samples along a drag: this fraction of the brush radius on
## screen, but never less than [constant MIN_STEP_PX] pixels.
const STEP_OF_RADIUS := 0.5
const MIN_STEP_PX := 2.0
## Times a drag halves the gap between two samples that land on different UV islands, to find
## a thin island between them.
const SEAM_SPLITS := 4
## A mirrored dab is found by a ray from this far outside the mirrored point (m).
const MIRROR_REACH := 0.03
## Gap (px) between the side panel and the colour wheel beside it.
const PALETTE_GAP := 12.0
## Microseconds per frame a paint-bucket click pours its fill for (the rest of the frame
## stays free, so a big fill flows in instead of freezing the game).
const FILL_STEP_USEC := 6000
## Finish buttons: their swatch ball's diameter (px) and text size.
const SWATCH_SIZE := 18
const FINISH_FONT_SIZE := 13

## Which part of the rig is painted.
@export var mode: Mode = Mode.PLAYER:
	set(value):
		mode = value
		if is_node_ready():
			_refresh_mode()
## Active tool for mouse clicks.
@export var tool: Tool = Tool.BRUSH:
	set(value):
		if value in PAINT_TOOLS:
			_paint_tool = value
		tool = value
		if is_node_ready():
			_sync_tool_buttons()
## What the fill tool floods.
@export var fill_mode: FillMode = FillMode.CONNECTED:
	set(value):
		fill_mode = value
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
## How much colour a brush stroke puts on (it never builds up within one stroke).
@export_range(0.05, 1.0) var brush_opacity: float = 1.0
## Brush edge: 0 crisp, 1 fades from the centre.
@export_range(0.0, 1.0) var brush_softness: float = 0.0
## Paint the mirrored point on the other side of the model too (left and right together).
@export var mirror: bool = false:
	set(value):
		mirror = value
		if is_node_ready():
			mirror_check.set_pressed_no_signal(value)
## The finish the finish tool gives a part ([PaintFinish] id).
@export var finish_choice: StringName = PaintFinish.GLOSS:
	set(value):
		finish_choice = value
		if is_node_ready():
			_sync_finish_buttons()
## Undo steps kept.
@export var max_undo: int = 32
## When set, Done also saves the appearance there (and a creator given no appearance starts
## from the one saved there).
@export var save_path: String = ""
## The appearance being edited; loaded from [member save_path] (or made fresh) when none is
## given.
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
## Strokes, fills and finishes that can still be undone.
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
## Hit of the last screen sample of the open stroke (empty: it missed the model).
var _last_stroke_hit: Dictionary = {}
## The colour the finish swatches show (they are redrawn only when the brush colour changes).
var _swatch_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Seconds the confirmation in the hint line has left (0: the hint shows).
var _confirm_left: float = 0.0
## Visibility of the rig's body and board before painting, put back by [method finish].
var _rig_visibility: Dictionary[NodePath, bool] = {}
## Process modes of the rig's animation players and skeletons before painting froze them,
## and whether the rig itself was processing; put back by [method finish].
var _frozen_modes: Dictionary[Node, Node.ProcessMode] = {}
var _rig_was_processing: bool = false
var _recent: Array[Color] = []
var _finished: bool = false
## False until picking has been switched to the pose the rig is drawn with (it is recorded
## on the rig's first skeleton update after the canvas is made).
var _pose_synced: bool = false
## The paint tool to go back to after the eyedropper took a colour or the finish tool gave
## a part its finish.
var _paint_tool: Tool = Tool.BRUSH
## Mirror plane of the shown half: its frame (the shown node) and the plane's axis and
## position in that frame. Axis -1: no mirror pair found.
var _mirror_frame: Node3D = null
var _mirror_axis: int = -1
var _mirror_at: float = 0.0
## Colour of the fill pouring in (remembered as a recent colour once it is in).
var _pouring_color: Color = Color.WHITE

@onready var preview: Node3D = $Preview
@onready var orbit: OrbitCamera = $CameraPivot
@onready var frame_panel: Control = $UI/Frame
@onready var title_label: Label = %Title
@onready var hint_label: Label = %Hint
@onready var brush_button: Button = %Brush
@onready var fill_button: Button = %Fill
@onready var eraser_button: Button = %Eraser
@onready var pick_button: Button = %Eyedropper
@onready var finish_tool_button: Button = %FinishTool
@onready var tool_name_label: Label = %ToolName
@onready var fill_modes: Control = %FillModes
@onready var connected_button: Button = %Connected
@onready var whole_part_button: Button = %WholePart
@onready var current_chip: Button = %Current
@onready var recent_row: GridContainer = %Recent
@onready var palette: Control = %Palette
@onready var picker: ColorPicker = %Picker
@onready var size_slider: HSlider = %BrushSize
@onready var size_small: Label = %SizeSmall
@onready var size_large: Label = %SizeLarge
@onready var opacity_slider: HSlider = %Opacity
@onready var softness_slider: HSlider = %Softness
@onready var mirror_check: BaseButton = %Mirror
@onready var finish_grid: GridContainer = %Finishes
@onready var finish_all_button: Button = %FinishAll
@onready var undo_button: Button = %Undo
@onready var done_button: Button = %Done
@onready var brush_cursor: PaintCursor = %BrushCursor


func _ready() -> void:
	if appearance == null:
		appearance = Appearance.load_from(save_path) if not save_path.is_empty() else null
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
	_freeze_rig()
	_recent = STARTER_COLORS.duplicate()
	_connect_ui()
	_refresh_mode()
	orbit.camera.make_current()
	_lend_studio_sky()
	if glide_from != null:
		orbit.glide_from(glide_from, glide_seconds)


func _exit_tree() -> void:
	# A creator that was never finished still gives the rig back. A finished one already
	# did; doing it again here (it is freed a frame later) would show the body again while
	# the next pass (the board) is painting.
	if not _finished:
		_restore_rig()
	if canvas != null:
		canvas.settle_warm_up(true)


func _process(delta: float) -> void:
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			hint_label.text = HINTS[mode]
	if canvas != null:
		canvas.settle_warm_up()
		canvas.flush()
		if not _pose_synced and canvas.has_drawn_pose():
			canvas.refresh_pose()
			_pose_synced = true
	if canvas != null and canvas.is_filling() and canvas.step_fill(FILL_STEP_USEC):
		_remember_color(_pouring_color)
	_centre_beside_panel()
	_update_cursor()


## Motion and release of a drag are read here, before the tool panel can take them, so a
## drag that ends over the panel still ends (and never keeps painting on hover).
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
	var hit := _hit_on_part(part_name, local_pos, normal)
	if hit.is_empty():
		return false
	_dab(hit)
	return true


## Fills at the screen point [param pos] the way [member fill_mode] says.
func fill_at_screen(pos: Vector2) -> bool:
	return _fill_hit(pick(pos))


## Fills on the part [param part_name] at [param local_pos] facing [param normal] (both
## local to the part) the way [member fill_mode] says. One undo step.
func fill_at(part_name: StringName, local_pos: Vector3, normal: Vector3) -> bool:
	return _fill_hit(_hit_on_part(part_name, local_pos, normal))


## Floods the whole part [param part_name] with [member brush_color]. One undo step.
func fill_part(part_name: StringName) -> bool:
	var mesh := _shown_mesh(part_name)
	if mesh == null or not canvas.fill_mesh(mesh, brush_color):
		return false
	_remember_color(brush_color)
	return true


## Erases (paints back to the unpainted look) a dab under the screen point [param pos].
## Returns 1 when it changed anything, else 0.
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


## Eyedropper: makes the colour painted under the screen point [param pos] the brush colour
## and goes back to the tool used before. False on a miss.
func pick_color_at_screen(pos: Vector2) -> bool:
	return _take_color(pick(pos))


## Eyedropper on the part [param part_name] at [param local_pos] facing [param normal].
func pick_color_at(part_name: StringName, local_pos: Vector3, normal: Vector3) -> bool:
	return _take_color(_hit_on_part(part_name, local_pos, normal))


## Gives the part [param part_name] the finish [member finish_choice]. One undo step.
func set_part_finish(part_name: StringName) -> bool:
	var mesh := _shown_mesh(part_name)
	return mesh != null and canvas.set_finish(mesh, finish_choice)


## Gives every shown part the finish [member finish_choice]. One undo step.
func set_finish_everywhere() -> bool:
	return canvas.set_finish_all(_shown_meshes, finish_choice)


## The finish the part [param part_name] wears now.
func part_finish(part_name: StringName) -> StringName:
	var mesh := _shown_mesh(part_name)
	if mesh == null:
		return PaintFinish.ORIGINAL
	var layers := canvas.layers_of(mesh)
	return layers[0].finish() if not layers.is_empty() else PaintFinish.ORIGINAL


## Takes back the last stroke, fill or finish. False when there is nothing to undo.
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


## Hides the paint screen's panel and cursor at once (e.g. while it is being freed).
func hide_ui() -> void:
	($UI as CanvasLayer).visible = false


## The shown part under the screen point [param pos]: the [PaintCanvas] hit plus
## [code]part[/code] (the mesh's node name), or empty on a miss. Uses the meshes' own
## triangles, so it needs no physics bodies or physics frame.
func pick(pos: Vector2) -> Dictionary:
	var camera := orbit.camera
	var hit := canvas.pick_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos),
			_shown_meshes)
	return _named(hit)


## The hit mirroring [param hit] across the shown half's mirror plane (left and right
## swapped), or empty when there is no mirror plane or the mirrored point is off the model.
## It is mirrored in the rest pose, where the model is symmetric, and then found where that
## point is drawn now, so it matches however the skater stands.
func mirror_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty() or _mirror_axis < 0 or not is_instance_valid(_mirror_frame):
		return {}
	var layer := hit["layer"] as PaintLayer
	var rest := layer.rest_point(hit)
	var to_frame := _mirror_frame.global_transform.affine_inverse()
	var from_mesh := to_frame * layer.mesh_instance.global_transform
	var point := _reflect(from_mesh * rest[0])
	var normal := _reflect_direction(from_mesh.basis * rest[1]).normalized()
	var best := {}
	var best_distance := INF
	for mesh in _shown_meshes:
		var to_mesh := (to_frame * mesh.global_transform).affine_inverse()
		var origin := to_mesh * (point + normal * MIRROR_REACH)
		var toward := (to_mesh.basis * -normal).normalized()
		for target in canvas.layers_of(mesh):
			var found := target.pick_rest(origin, toward)
			if found.is_empty():
				continue
			var distance := origin.distance_to(found["rest_position"] as Vector3)
			if distance < best_distance:
				best_distance = distance
				found["world"] = mesh.global_transform * (found["position"] as Vector3)
				best = found
	return _named(best)


## How many pixels across the brush radius is at the world point [param at].
func brush_radius_px(at: Vector3) -> float:
	var camera := orbit.camera
	if camera.is_position_behind(at):
		return 0.0
	var side := camera.global_basis.x * brush_size * 0.5
	return camera.unproject_position(at).distance_to(camera.unproject_position(at + side))


func _named(hit: Dictionary) -> Dictionary:
	if not hit.is_empty():
		hit["part"] = StringName((hit["layer"] as PaintLayer).mesh_instance.name)
	return hit


func _hit_on_part(part_name: StringName, local_pos: Vector3, normal: Vector3) -> Dictionary:
	var mesh := _shown_mesh(part_name)
	if mesh == null:
		return {}
	return _named(canvas.hit_on(mesh, local_pos, normal))


func _reflect(point: Vector3) -> Vector3:
	point[_mirror_axis] = _mirror_at * 2.0 - point[_mirror_axis]
	return point


func _reflect_direction(direction: Vector3) -> Vector3:
	direction[_mirror_axis] = -direction[_mirror_axis]
	return direction


func _dab(hit: Dictionary, erase: bool = false) -> bool:
	_apply_brush()
	canvas.erasing = erase
	var was_open := canvas.is_stroke_open()
	if not was_open:
		canvas.begin_stroke()
	canvas.stroke_to(hit)
	if mirror:
		canvas.stroke_to(mirror_hit(hit), 1)
	if was_open:
		return true
	var changed := canvas.end_stroke()
	if changed and not erase:
		_remember_color(brush_color)
	return changed


## Fills under [param hit] as [member fill_mode] says. With [param pour] a connected fill
## pours in over the next frames ([method _process] runs it) instead of all at once.
func _fill_hit(hit: Dictionary, pour: bool = false) -> bool:
	if hit.is_empty():
		return false
	if fill_mode == FillMode.WHOLE_PART:
		return fill_part(hit["part"])
	if pour:
		_pouring_color = brush_color
		return canvas.begin_fill(hit, brush_color)
	if not canvas.fill_connected(hit, brush_color):
		return false
	_remember_color(brush_color)
	return true


func _take_color(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var taken := canvas.color_under(hit)
	taken.a = 1.0
	brush_color = taken
	if tool == Tool.PICK:
		tool = _paint_tool
	return true


func _apply_brush() -> void:
	canvas.brush_size = brush_size
	canvas.color = brush_color
	canvas.erasing = tool == Tool.ERASER
	canvas.opacity = clampf(brush_opacity, MIN_OPACITY, 1.0)
	canvas.softness = clampf(brush_softness, 0.0, 1.0)
	canvas.max_undo = max_undo


## Paints along the screen from the last point of the stroke to [param pos], a sample every
## few pixels, so fast drags stay continuous and seams between them break cleanly. Where two
## samples land on different UV islands the gap between them is searched for any island in
## between (a thin strip of texture along a seam), so the line paints that too.
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
	var previous_screen := _last_screen
	var previous: Dictionary = _last_stroke_hit if _has_last_screen else {}
	for target in targets:
		var hit := pick(target)
		if not previous.is_empty() and not hit.is_empty() and not canvas.joins(previous, hit):
			for between in _seam_hits(previous_screen, previous, target, hit, SEAM_SPLITS):
				_stroke_hit(between)
		_stroke_hit(hit)
		any = any or not hit.is_empty()
		previous_screen = target
		previous = hit
	_last_screen = pos
	_last_stroke_hit = previous
	_has_last_screen = true
	return any


func _stroke_hit(hit: Dictionary) -> void:
	canvas.stroke_to(hit)
	if mirror:
		canvas.stroke_to(mirror_hit(hit), 1)


## The hits between screen points [param from] and [param to] (hits [param from_hit] and
## [param to_hit], which do not join), in order: halving the gap up to [param depth] times
## while the halves still do not join.
func _seam_hits(from: Vector2, from_hit: Dictionary, to: Vector2, to_hit: Dictionary,
		depth: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if depth <= 0:
		return found
	var middle := (from + to) * 0.5
	var middle_hit := pick(middle)
	if middle_hit.is_empty():
		return found
	if not canvas.joins(from_hit, middle_hit):
		found.append_array(_seam_hits(from, from_hit, middle, middle_hit, depth - 1))
	found.append(middle_hit)
	if not canvas.joins(middle_hit, to_hit):
		found.append_array(_seam_hits(middle, middle_hit, to, to_hit, depth - 1))
	return found


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
			_begin_left_drag(button.position, button.alt_pressed)


func _begin_left_drag(pos: Vector2, alt: bool = false) -> void:
	var hit := pick(pos)
	if hit.is_empty():
		_orbiting = true
		return
	if alt or tool == Tool.PICK:
		_take_color(hit)
		return
	match tool:
		Tool.FILL:
			_fill_hit(hit, true)
			return
		Tool.FINISH:
			# One part per click, then back to painting (so the next drag paints over it).
			set_part_finish(hit["part"])
			_confirm(PART_FINISH_DONE_TEXT % PaintFinish.display_name(finish_choice))
			tool = _paint_tool
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
		KEY_I:
			tool = Tool.PICK
		KEY_M:
			tool = Tool.FINISH
		KEY_X:
			mirror = not mirror
		KEY_BRACKETLEFT:
			_set_brush_size(brush_size / BRUSH_KEY_FACTOR)
		KEY_BRACKETRIGHT:
			_set_brush_size(brush_size * BRUSH_KEY_FACTOR)
		_:
			return false
	return true


## Moves the brush ring to the mouse; hidden over the panel and while turning the view.
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
	var shown := Color.WHITE if tool in [Tool.ERASER, Tool.FINISH] else brush_color
	var point_only := tool in [Tool.FILL, Tool.PICK, Tool.FINISH]
	brush_cursor.show_at(mouse, brush_radius_px(at), shown, point_only)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if not hit.is_empty()
			else Input.CURSOR_ARROW)


## Shifts the view so the model sits in the middle of the space right of the panel.
func _centre_beside_panel() -> void:
	var camera := orbit.camera
	var width := get_viewport().get_visible_rect().size.x
	if width <= 0.0 or not frame_panel.is_visible_in_tree():
		camera.h_offset = 0.0
		return
	var covered := frame_panel.get_global_rect().end.x
	var aspect := width / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var half_width := orbit.distance * tan(deg_to_rad(camera.fov) * 0.5) * aspect
	camera.h_offset = -half_width * clampf(covered / width, 0.0, 0.5)


func _shown_mesh(part_name: StringName) -> MeshInstance3D:
	for mesh in _shown_meshes:
		if mesh.name == part_name:
			return mesh
	return null


## Holds the rig still while painting: its animation players stop, its own pose springs stop
## and its skeletons keep drawing (also while the game is paused), so the drawn pose and the
## pose paint is aimed at stay the same.
func _freeze_rig() -> void:
	_rig_was_processing = _rig.is_processing()
	_rig.set_process(false)
	for node in _rig.find_children("*", "AnimationMixer", true, false):
		_frozen_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for node in _rig.find_children("*", "Skeleton3D", true, false):
		_frozen_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS


## Shows the rig's body and board as they were before painting and lets it move again.
func _restore_rig() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	for path: NodePath in _rig_visibility:
		(_rig.get_node(path) as Node3D).visible = _rig_visibility[path]
	for node: Node in _frozen_modes:
		if is_instance_valid(node):
			node.process_mode = _frozen_modes[node]
	_frozen_modes.clear()
	_rig.set_process(_rig_was_processing)


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
	if canvas != null:
		canvas.settle_warm_up(true)
	canvas = PaintCanvas.new(_rig, appearance, shown)
	canvas.max_undo = max_undo
	canvas.warm_up()
	_pose_synced = false
	_shown_meshes = PaintCanvas.paintable_meshes(shown)
	_find_mirror_plane(shown)
	title_label.text = TITLES[mode]
	hint_label.text = HINTS[mode]
	_sync_finish_buttons()
	_frame_camera()


## The mirror plane of [param shown]: halfway between its mirror pair, across the axis they
## differ along most (in the shown node's frame).
func _find_mirror_plane(shown: Node3D) -> void:
	_mirror_frame = shown
	_mirror_axis = -1
	var pair: Array = MIRROR_PAIRS[mode]
	var centres: Array[Vector3] = []
	for part_name: StringName in pair:
		var mesh := shown.find_child(String(part_name), true, false) as MeshInstance3D
		if mesh == null:
			return
		centres.append(shown.global_transform.affine_inverse()
				* (mesh.global_transform * mesh.get_aabb().get_center()))
	var apart := (centres[1] - centres[0]).abs()
	_mirror_axis = apart.max_axis_index()
	_mirror_at = (centres[0][_mirror_axis] + centres[1][_mirror_axis]) * 0.5


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
	var heading_font := FontLibrary.title_font(HEADING_WEIGHT)
	title_label.add_theme_font_override(&"font", heading_font)
	done_button.add_theme_font_override(&"font", heading_font)
	for heading: Node in get_tree().get_nodes_in_group(&"paint_heading"):
		if is_ancestor_of(heading):
			(heading as Control).add_theme_font_override(&"font", heading_font)
	var ui_font := FontLibrary.ui_font()
	for label: Node in get_tree().get_nodes_in_group(&"paint_text"):
		if is_ancestor_of(label):
			(label as Control).add_theme_font_override(&"font", ui_font)
	brush_button.text = ICON_BRUSH
	fill_button.text = ICON_FILL
	eraser_button.text = ICON_ERASER
	pick_button.text = ICON_PICK
	finish_tool_button.text = ICON_FINISH
	undo_button.text = ICON_UNDO
	size_small.text = ICON_DOT
	size_large.text = ICON_DOT
	brush_button.pressed.connect(func() -> void: tool = Tool.BRUSH)
	fill_button.pressed.connect(func() -> void: tool = Tool.FILL)
	eraser_button.pressed.connect(func() -> void: tool = Tool.ERASER)
	pick_button.pressed.connect(func() -> void: tool = Tool.PICK)
	finish_tool_button.pressed.connect(func() -> void: tool = Tool.FINISH)
	connected_button.pressed.connect(_choose_fill.bind(FillMode.CONNECTED))
	whole_part_button.pressed.connect(_choose_fill.bind(FillMode.WHOLE_PART))
	_sync_tool_buttons()
	current_chip.pressed.connect(_on_current_pressed)
	picker.color = brush_color
	picker.color_changed.connect(_on_picker_color_changed)
	size_slider.min_value = MIN_BRUSH
	size_slider.max_value = MAX_BRUSH
	size_slider.value = brush_size
	size_slider.value_changed.connect(_on_brush_size_value_changed)
	opacity_slider.min_value = MIN_OPACITY
	opacity_slider.max_value = 1.0
	opacity_slider.value = brush_opacity
	opacity_slider.value_changed.connect(func(value: float) -> void: brush_opacity = value)
	softness_slider.min_value = 0.0
	softness_slider.max_value = 1.0
	softness_slider.value = brush_softness
	softness_slider.value_changed.connect(func(value: float) -> void: brush_softness = value)
	mirror_check.set_pressed_no_signal(mirror)
	mirror_check.toggled.connect(func(on: bool) -> void: mirror = on)
	_build_finish_buttons()
	finish_all_button.pressed.connect(_on_finish_all_pressed)
	undo_button.pressed.connect(undo)
	done_button.pressed.connect(finish)
	palette.visible = false
	_rebuild_recent()
	_show_brush_color()
	UiSounds.wire(frame_panel)


func _sync_tool_buttons() -> void:
	brush_button.set_pressed_no_signal(tool == Tool.BRUSH)
	fill_button.set_pressed_no_signal(tool == Tool.FILL)
	eraser_button.set_pressed_no_signal(tool == Tool.ERASER)
	pick_button.set_pressed_no_signal(tool == Tool.PICK)
	finish_tool_button.set_pressed_no_signal(tool == Tool.FINISH)
	_show_tool_name()
	# The bucket's fill modes take the tool name's place (one slot of one height, so nothing
	# below jumps when the tool changes).
	fill_modes.visible = tool == Tool.FILL
	tool_name_label.visible = not fill_modes.visible
	connected_button.set_pressed_no_signal(fill_mode == FillMode.CONNECTED)
	whole_part_button.set_pressed_no_signal(fill_mode == FillMode.WHOLE_PART)


func _build_finish_buttons() -> void:
	for child in finish_grid.get_children():
		finish_grid.remove_child(child)
		child.queue_free()
	var font := FontLibrary.ui_font()
	for finish_id in PaintFinish.ORDER:
		var button := PaintChoiceButton.new()
		button.text = PaintFinish.display_name(finish_id)
		button.tooltip_text = "Give a part the %s finish" % button.text
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta(META_FINISH, finish_id)
		button.add_theme_font_override(&"font", font)
		button.add_theme_font_size_override(&"font_size", FINISH_FONT_SIZE)
		button.add_theme_constant_override(&"h_separation", 6)
		button.pressed.connect(_on_finish_pressed.bind(finish_id))
		finish_grid.add_child(button)
	_swatch_color = Color(0.0, 0.0, 0.0, 0.0)
	_sync_finish_buttons()


## Shows each finish on a ball in the brush colour, so the buttons preview the look.
func _paint_finish_swatches() -> void:
	if _swatch_color == brush_color:
		return
	_swatch_color = brush_color
	for child in finish_grid.get_children():
		var button := child as Button
		var finish_id := StringName(button.get_meta(META_FINISH))
		button.icon = ImageTexture.create_from_image(
				PaintFinish.swatch(finish_id, brush_color, SWATCH_SIZE))


func _on_finish_all_pressed() -> void:
	# Said even when it already wore that finish, so the press never seems to do nothing.
	set_finish_everywhere()
	_confirm(FINISH_DONE_TEXT[mode] % PaintFinish.display_name(finish_choice))


## Says [param text] in the hint line for a moment.
func _confirm(text: String) -> void:
	hint_label.text = text
	_confirm_left = CONFIRM_SECONDS


## Where the world has no sky of its own (the paint screen on its own, a level without one),
## gives the view a soft studio sky to reflect, so finishes show. The background stays
## as it was.
func _lend_studio_sky() -> void:
	var camera := orbit.camera
	var world := camera.get_world_3d()
	if camera.environment != null or (world != null and world.environment != null):
		return
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = STUDIO_SKY_TOP
	sky_material.sky_horizon_color = STUDIO_SKY_HORIZON
	sky_material.ground_horizon_color = STUDIO_SKY_HORIZON
	sky_material.ground_bottom_color = STUDIO_GROUND
	var sky := Sky.new()
	sky.sky_material = sky_material
	var studio := Environment.new()
	studio.background_mode = Environment.BG_CLEAR_COLOR
	studio.sky = sky
	studio.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	studio.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	camera.environment = studio


func _choose_fill(chosen: FillMode) -> void:
	fill_mode = chosen
	tool = Tool.FILL


func _show_tool_name() -> void:
	var text := TOOL_NAMES[tool]
	tool_name_label.text = text % PaintFinish.display_name(finish_choice) \
			if tool == Tool.FINISH else text


func _sync_finish_buttons() -> void:
	_show_tool_name()
	finish_all_button.text = FINISH_ALL_TEXT[mode] % PaintFinish.display_name(finish_choice)
	for child in finish_grid.get_children():
		var button := child as Button
		button.set_pressed_no_signal(StringName(button.get_meta(META_FINISH)) == finish_choice)


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
	_paint_finish_swatches()


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
	recent_row.columns = RECENT_COLUMNS
	for color in _recent:
		var chip := Button.new()
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_NONE
		chip.tooltip_text = "#" + color.to_html(false)
		chip.set_meta(META_CHIP_COLOR, color)
		_style_chip(chip, color, color.is_equal_approx(brush_color))
		chip.pressed.connect(_on_recent_pressed.bind(color))
		recent_row.add_child(chip)


## A round colour orb; [param lit] gives it a ring of warm light and a soft glow.
static func _style_chip(chip: Button, color: Color, lit: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(CHIP_RADIUS)
	style.set_border_width_all(CHIP_RING if lit else 1)
	style.border_color = LIGHT if lit else CHIP_EDGE_COLOR
	style.anti_aliasing = true
	if lit:
		style.shadow_color = Color(LIGHT, 0.35)
		style.shadow_size = CHIP_GLOW
	var hover := style.duplicate() as StyleBoxFlat
	hover.set_border_width_all(CHIP_RING)
	hover.border_color = LIGHT
	hover.shadow_color = Color(color.lightened(0.3), 0.45)
	hover.shadow_size = CHIP_GLOW
	for state: StringName in [&"normal", &"focus", &"disabled"]:
		chip.add_theme_stylebox_override(state, style)
	for state: StringName in [&"hover", &"pressed", &"hover_pressed"]:
		chip.add_theme_stylebox_override(state, hover)


func _close_palette() -> void:
	palette.visible = false


func _on_current_pressed() -> void:
	palette.visible = not palette.visible
	if palette.visible:
		var chip := current_chip.get_global_rect()
		palette.global_position = Vector2(frame_panel.get_global_rect().end.x + PALETTE_GAP,
				clampf(chip.position.y - palette.size.y * 0.5, PALETTE_GAP,
				get_viewport().get_visible_rect().size.y - palette.size.y - PALETTE_GAP))


func _on_picker_color_changed(color: Color) -> void:
	brush_color = color


func _on_recent_pressed(color: Color) -> void:
	brush_color = color
	if tool in [Tool.ERASER, Tool.PICK, Tool.FINISH]:
		tool = Tool.BRUSH


func _on_finish_pressed(finish_id: StringName) -> void:
	finish_choice = finish_id
	tool = Tool.FINISH


func _on_brush_size_value_changed(value: float) -> void:
	brush_size = value
