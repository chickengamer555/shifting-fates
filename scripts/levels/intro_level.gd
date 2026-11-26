class_name IntroLevel
extends LevelController
## The intro: the player arrives in the intro level art (the upper echelon) with no body yet.
##
## The level art is whatever scene the intro instances as [code]Art[/code]; this script only
## needs a [code]SpawnPoint[/code], a [code]Portal[/code], a [code]TitleCross[/code] and the
## [code]UI/DialogueBox[/code]. The skater starts invisible and the [code]intro[/code]
## dialogue plays as a cutscene (skater frozen, HUD hidden). The [code]open_player_paint[/code]
## and [code]open_board_paint[/code] events open the [PaintCreator] in place: it paints the
## real skater where it stands, starting from the white mannequin, while its camera glides
## from the skater's view into an orbit around the rig. The dialogue box hides until the
## creator's [signal PaintCreator.finished], then the skater's camera takes the view back.
## The creator frees the mouse while open; the skater takes it back once it may skate.
## Without a paint creator the dialogue simply carries on. When the dialogue ends a cross
## with a "Shifting fates" billboard flies across the sky, the player skates freely (HUD
## shown) and, when [member follow_up_dialogue_id] is set, that dialogue starts once the
## cross has flown. The goal opens the portal to the next level.

## Where the intro begins. [constant PAINT] (dev hub, previews) skips the lines before the
## player paint.
enum StartStep { INTRO, PAINT }

const EVENT_PLAYER_PAINT := &"open_player_paint"
const EVENT_BOARD_PAINT := &"open_board_paint"
const PAINT_CREATOR_SCENE := preload("res://scenes/paint/paint_creator.tscn")
const PAINT_NODE_NAME := &"PaintCreator"
const CLOSED_PAINT_NODE_NAME := &"PaintCreatorClosing"
## Turns the cross makes about its vertical axis while it flies.
const CROSS_TURNS := 1.0

## The body/board painter. Set it to null to skip painting.
@export var paint_creator_scene: PackedScene = PAINT_CREATOR_SCENE
## Where the intro begins (see [enum StartStep]).
@export var start_step: StartStep = StartStep.INTRO
## Dialogue played while skating once the title cross has flown. Empty: none.
@export var follow_up_dialogue_id: StringName = &""
## Seconds the title cross takes to cross the sky.
@export var cross_seconds: float = 7.0
## Where the cross starts and ends its flight (local to the level).
@export var cross_start: Vector3 = Vector3(-45.0, 14.0, -30.0)
@export var cross_end: Vector3 = Vector3(45.0, 14.0, -30.0)

## True while the paint creator is open.
var painting: bool:
	get:
		return _paint != null

var _appearance: Appearance = null
var _paint: PaintCreator = null
var _intro_over: bool = false

@onready var _title_cross: Node3D = $TitleCross


func _ready() -> void:
	_title_cross.visible = false
	super._ready()
	# The dialogue may already have opened the painter (and shown the mannequin) on ready.
	if not painting and not _intro_over:
		skater.visible = false


func _begin_dialogue() -> void:
	skater.visible = false
	var sequence := find_dialogue(dialogue_id)
	if start_step == StartStep.PAINT and sequence != null:
		sequence = _from_event(sequence, EVENT_PLAYER_PAINT)
	play_dialogue(sequence, true)


func _handle_dialogue_event(event: StringName) -> void:
	match event:
		EVENT_PLAYER_PAINT:
			skater.visible = true
			_open_paint(PaintCreator.Mode.PLAYER)
		EVENT_BOARD_PAINT:
			_open_paint(PaintCreator.Mode.BOARD)


func _handle_dialogue_finished() -> void:
	if _intro_over:
		return
	_intro_over = true
	skater.visible = true
	_fly_title_cross()


## Opens the paint creator on the skater in [param mode]. Returns false when none is available.
func _open_paint(mode: PaintCreator.Mode) -> bool:
	if paint_creator_scene == null:
		return false
	_paint = paint_creator_scene.instantiate() as PaintCreator
	if _paint == null:
		push_warning("IntroLevel: paint creator scene is not a PaintCreator")
		return false
	_paint.name = PAINT_NODE_NAME
	_paint.mode = mode
	_paint.save_path = game_state.appearance_path
	_paint.target_rig = skater.rig
	_paint.glide_from = skater.camera
	if _appearance != null:
		_paint.appearance = _appearance
	_paint.finished.connect(_on_paint_creator_finished)
	add_child(_paint)
	dialogue_box.visible = false
	if hud != null:
		hud.visible = false
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
	tween.finished.connect(_on_title_cross_flown)


## A copy of [param sequence] that starts at the first line carrying [param event].
static func _from_event(sequence: DialogueSequence, event: StringName) -> DialogueSequence:
	var trimmed := DialogueSequence.new()
	trimmed.id = sequence.id
	trimmed.lines = sequence.lines
	for index: int in sequence.lines.size():
		if sequence.lines[index].event == event:
			trimmed.lines = sequence.lines.slice(index)
			break
	return trimmed


func _on_paint_creator_finished(appearance: Appearance) -> void:
	_appearance = appearance
	skater.visible = true
	_close_paint()


func _on_title_cross_flown() -> void:
	if follow_up_dialogue_id != &"":
		play_dialogue(find_dialogue(follow_up_dialogue_id), false)
