class_name IntroLevel
extends LevelController
## The intro: the player arrives in the heavenly void with no body yet.
##
## The skater starts invisible and frozen while the [code]intro[/code] dialogue plays. The
## [code]open_player_paint[/code] and [code]open_board_paint[/code] events open the
## [PaintCreator] (when [member paint_creator_scene] is set) in player and board mode;
## the dialogue is hidden until the creator's [signal PaintCreator.finished], and the look is
## applied to the skater. The creator frees the mouse while it is open; closing it hands the
## mouse back to the skater. Without a paint creator the dialogue simply carries on. When the
## dialogue ends a cross with a "Shifting fates" billboard flies across the sky and the
## player skates freely until the goal opens the portal to level 1.

const EVENT_PLAYER_PAINT := &"open_player_paint"
const EVENT_BOARD_PAINT := &"open_board_paint"
const PAINT_CREATOR_SCENE := preload("res://scenes/paint/paint_creator.tscn")
const PAINT_NODE_NAME := &"PaintCreator"
const CLOSED_PAINT_NODE_NAME := &"PaintCreatorClosing"
## The paint creator's own little stage is built far below the void, out of sight.
const PAINT_STAGE_OFFSET := Vector3(0.0, -500.0, 0.0)
## Turns the cross makes about its vertical axis while it flies.
const CROSS_TURNS := 1.0

## The body/board painter. Set it to null to skip painting.
@export var paint_creator_scene: PackedScene = PAINT_CREATOR_SCENE
## Where the finished look is saved for later levels. Empty: not saved.
@export var appearance_save_path: String = Appearance.DEFAULT_PATH
## Seconds the title cross takes to cross the sky.
@export var cross_seconds: float = 7.0
## Where the cross starts and ends its flight (local to the level).
@export var cross_start: Vector3 = Vector3(-45.0, 14.0, -30.0)
@export var cross_end: Vector3 = Vector3(45.0, 14.0, -30.0)

var _appearance: Appearance = null
var _paint: PaintCreator = null

@onready var _title_cross: Node3D = $TitleCross


func _ready() -> void:
	_title_cross.visible = false
	super._ready()
	skater.visible = false


func _handle_dialogue_event(event: StringName) -> void:
	match event:
		EVENT_PLAYER_PAINT:
			if not _open_paint(PaintCreator.Mode.PLAYER):
				skater.visible = true
		EVENT_BOARD_PAINT:
			_open_paint(PaintCreator.Mode.BOARD)


func _handle_dialogue_finished() -> void:
	skater.visible = true
	_fly_title_cross()


## Opens the paint creator in [param mode]. Returns false when none is available.
func _open_paint(mode: PaintCreator.Mode) -> bool:
	if paint_creator_scene == null:
		return false
	_paint = paint_creator_scene.instantiate() as PaintCreator
	if _paint == null:
		push_warning("IntroLevel: paint creator scene is not a PaintCreator")
		return false
	_paint.name = PAINT_NODE_NAME
	_paint.mode = mode
	_paint.save_path = appearance_save_path
	if _appearance != null:
		_paint.appearance = _appearance
	_paint.position = PAINT_STAGE_OFFSET
	_paint.finished.connect(_on_paint_creator_finished)
	add_child(_paint)
	dialogue_box.visible = false
	return true


func _close_paint() -> void:
	# Free the name now so the next pass can take it in the same frame.
	_paint.name = CLOSED_PAINT_NODE_NAME
	_paint.visible = false
	_paint.queue_free()
	_paint = null
	skater.camera.make_current()
	skater.refresh_mouse()
	dialogue_box.visible = true


func _fly_title_cross() -> void:
	_title_cross.position = cross_start
	_title_cross.visible = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title_cross, "position", cross_end, cross_seconds)
	tween.tween_property(_title_cross, "rotation:y", TAU * CROSS_TURNS, cross_seconds) \
		.as_relative()
	tween.chain().tween_property(_title_cross, "visible", false, 0.0)


func _on_paint_creator_finished(appearance: Appearance) -> void:
	_appearance = appearance
	appearance.apply_to(skater.rig)
	skater.visible = true
	_close_paint()
