class_name IntroLevel
extends LevelController
## The intro: the player arrives in the intro level art (the upper echelon) with no body yet.
##
## The level art is whatever scene the intro instances as [code]Art[/code]; this script only
## needs a [code]SpawnPoint[/code], a [code]Portal[/code], a [code]TitleCross[/code] and the
## [code]UI/DialogueBox[/code]. The skater starts invisible and the [code]intro[/code]
## dialogue plays as a cutscene (skater frozen, HUD hidden). A line's event fires once the
## player has read the line and pressed on (it moves to an empty cue line after it), so God's
## words are always seen before what they set off. The [code]open_player_paint[/code]
## and [code]open_board_paint[/code] events open the [PaintCreator] in place: it paints the
## real skater where it stands, starting from the white mannequin, while its camera glides
## from the skater's view into an orbit around the rig. The dialogue box hides until the
## creator's [signal PaintCreator.finished], then the skater's camera takes the view back.
## The creator frees the mouse while open; the skater takes it back once it may skate.
## Without a paint creator the dialogue simply carries on. The art's own cross (at
## [member art_cross_path]) is taken into [code]TitleCross[/code], so it stays hidden until
## the dialogue ends; then the cross with its "Shifting fates" banner flies across the sky
## face-on, on a shallow arc and banking with it, a glow trailing behind ([code]TitleCross/Trail
## [/code]), and is hidden again once it has flown, the player skates freely (HUD
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
## Name the art's cross takes under [code]TitleCross[/code].
const ART_CROSS_NAME := &"Cross"

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
## How far the flight path rises above the straight line at its middle.
@export var cross_arc_height: float = 6.0
## Roll at the ends of the arc: the cross leans into the climb and out of the descent.
@export var cross_bank_degrees: float = 8.0
## The level art's cross. It becomes the flying cross (with its look kept, standing upright at
## [member art_cross_scale]); without one, [code]TitleCross[/code]'s own stand-in cross flies.
@export var art_cross_path: NodePath = ^"Art/Objects/Cross"
@export var art_cross_scale: float = 0.48

## True while the paint creator is open.
var painting: bool:
	get:
		return _paint != null

var _appearance: Appearance = null
var _paint: PaintCreator = null
var _intro_over: bool = false

@onready var _title_cross: Node3D = $TitleCross
@onready var _stand_in_cross: Node3D = $TitleCross/StandIn
@onready var _cross_trail: CPUParticles3D = $TitleCross/Trail


func _ready() -> void:
	_title_cross.visible = false
	_adopt_art_cross()
	super._ready()
	# The dialogue may already have opened the painter (and shown the mannequin) on ready.
	if not painting and not _intro_over:
		skater.visible = false


func _begin_dialogue() -> void:
	skater.visible = false
	var sequence := find_dialogue(dialogue_id)
	if sequence != null:
		sequence = _events_after_lines(sequence)
		if start_step == StartStep.PAINT:
			sequence = _from_event(sequence, EVENT_PLAYER_PAINT)
	play_dialogue(sequence, true)


func _handle_dialogue_event(event: StringName) -> void:
	var opened := false
	match event:
		EVENT_PLAYER_PAINT:
			skater.visible = true
			opened = _open_paint(PaintCreator.Mode.PLAYER)
		EVENT_BOARD_PAINT:
			opened = _open_paint(PaintCreator.Mode.BOARD)
	if not opened:
		# Nothing to wait for: move past the empty cue line once it is done.
		dialogue_box.advance.call_deferred()


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
	# The cue line that opened the painter is still on; the next line follows.
	dialogue_box.advance()


## Moves the art's cross into [code]TitleCross[/code] (standing, scaled, no collision), so it
## only shows while the title cross flies. Keeps the stand-in when the art has no cross.
func _adopt_art_cross() -> void:
	var art_cross := get_node_or_null(art_cross_path) as Node3D
	if art_cross == null:
		return
	art_cross.get_parent().remove_child(art_cross)
	art_cross.name = ART_CROSS_NAME
	art_cross.transform = Transform3D(Basis.from_scale(Vector3.ONE * art_cross_scale))
	var body := art_cross as CollisionObject3D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0
	_title_cross.add_child(art_cross)
	_stand_in_cross.queue_free()


func _fly_title_cross() -> void:
	_place_title_cross(0.0)
	_title_cross.visible = true
	_cross_trail.emitting = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_place_title_cross, 0.0, 1.0, cross_seconds)
	tween.tween_callback(_land_title_cross)
	tween.finished.connect(_on_title_cross_flown)


## Puts the title cross at [param progress] (0..1) along its arc, banked with the slope.
func _place_title_cross(progress: float) -> void:
	var lift := cross_arc_height * 4.0 * progress * (1.0 - progress)
	_title_cross.position = cross_start.lerp(cross_end, progress) + Vector3.UP * lift
	_title_cross.rotation.z = -deg_to_rad(cross_bank_degrees) * (1.0 - 2.0 * progress)


func _land_title_cross() -> void:
	_cross_trail.emitting = false
	_title_cross.visible = false


## A copy of [param sequence] where every line with an event is followed by an empty cue line
## carrying that event instead, so it fires only once the line has been read.
static func _events_after_lines(sequence: DialogueSequence) -> DialogueSequence:
	var spaced := DialogueSequence.new()
	spaced.id = sequence.id
	var lines: Array[DialogueLine] = []
	for line: DialogueLine in sequence.lines:
		if line.event == &"" or line.text.is_empty():
			lines.append(line)
			continue
		var read := line.duplicate() as DialogueLine
		read.event = &""
		lines.append(read)
		var cue := DialogueLine.new()
		cue.event = line.event
		lines.append(cue)
	spaced.lines = lines
	return spaced


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
