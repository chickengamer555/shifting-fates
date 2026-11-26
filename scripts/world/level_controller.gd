class_name LevelController
extends Node3D
## Root script of a gameplay level: puts the skater at the spawn, runs the level's dialogue
## and opens the portal once the gods are appeased.
##
## A level scene instances its art (from [code]Assets/[/code]) and adds a [Marker3D]
## [code]SpawnPoint[/code], a [Portal], an optional [code]UI/DialogueBox[/code] and any
## [InvisibleBarrier]s on top. On ready the controller:
## [br]- reuses a [Skater] found in the art, or instances one, places it at the spawn and
##   binds it to [member game_state] for its ability unlocks;
## [br]- turns off any camera the art brought along and looks through the skater's camera;
## [br]- hands the skater to every [InvisibleBarrier] so their dots react to it;
## [br]- creates [member goal] from [member game_state] and a [ScoreKeeper] scoring the
##   skater into it, and binds the [Hud] (when its scene exists) to both;
## [br]- mounts an [AudioBridge] so the skater and combo are heard;
## [br]- plays the [DialogueSequence] [member dialogue_id], with a [DialogueVoice] for the gods.
## [br]The HUD is hidden while any dialogue is on screen, so it never sits under the text.
## With [member freeze_during_dialogue] the opening dialogue is also a cutscene
## ([method set_cutscene]): the skater is frozen until it ends.
## [br]Reaching the goal opens the portal. Riding through it advances the level (when
## [member advances_level]), saves, and emits [signal level_completed] for the game flow.

## The player rode through the open portal. Progress is already saved.
signal level_completed

const GAME_STATE := preload("res://autoload/game_state.gd")
const SKATER_SCENE := preload("res://scenes/player/skater.tscn")
## Instanced into the UI layer only if the file exists.
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"

## Id of the [DialogueSequence] played on entering, e.g. [code]&"level_1"[/code]. Empty: none.
@export var dialogue_id: StringName = &""
## False for levels before the first numbered level (the intro), which must not advance.
@export var advances_level: bool = true
## Instance the HUD when its scene exists. Tests turn it off.
@export var show_hud: bool = true
## Play the opening dialogue as a cutscene: skater frozen, HUD hidden.
@export var freeze_during_dialogue: bool = false
@export var spawn_point_path: NodePath = ^"SpawnPoint"
@export var portal_path: NodePath = ^"Portal"
@export var ui_layer_path: NodePath = ^"UI"
@export var dialogue_box_path: NodePath = ^"UI/DialogueBox"

## Progress store. Defaults to the [code]GameState[/code] autoload; tests inject their own.
var game_state: GAME_STATE = null
## The player's body in this level.
var skater: Skater = null
## Points needed to open the portal on this level.
var goal: LevelGoal = null
## Scores the skater's moves into [member goal].
var score_keeper: ScoreKeeper = null
var portal: Portal = null
var dialogue_box: DialogueBox = null
## The HUD instance, when one was mounted.
var hud: Hud = null
## Forwards the skater and the combo to the [code]AudioDirector[/code].
var audio_bridge: AudioBridge = null
## Voices the gods' lines of the level's dialogue, once the dialogue starts.
var dialogue_voice: DialogueVoice = null

var _completed: bool = false
## True while the dialogue playing was started as a cutscene.
var _dialogue_is_cutscene: bool = false


func _ready() -> void:
	if game_state == null:
		game_state = GameState
	portal = get_node_or_null(portal_path) as Portal
	dialogue_box = get_node_or_null(dialogue_box_path) as DialogueBox
	_place_skater()
	_use_skater_camera()
	_track_barriers()
	goal = game_state.create_level_goal()
	goal.goal_reached.connect(_on_goal_reached)
	_mount_score_keeper()
	_mount_audio_bridge()
	if show_hud:
		_mount_hud()
	if portal != null:
		portal.entered.connect(_on_portal_entered)
	_start_dialogue()


## Banks [param amount] extra points towards [member goal], e.g. from a level event.
func add_points(amount: int) -> void:
	goal.add_points(amount)


## Opens the portal. Called when the goal is met; levels may also call it from a cutscene.
func open_portal() -> void:
	if portal != null:
		portal.open()


## Starts or ends a cutscene: the skater loses (or gets back) its controls and the HUD hides
## (or shows again). The HUD is only on screen while the player is free to skate.
func set_cutscene(active: bool) -> void:
	skater.set_input_enabled(not active)
	if hud != null:
		hud.visible = not active


## Plays [param sequence] in the dialogue box with the HUD hidden until it ends. With
## [param as_cutscene] the skater is frozen as well ([method set_cutscene]).
func play_dialogue(sequence: DialogueSequence, as_cutscene: bool) -> void:
	if dialogue_box == null or sequence == null:
		return
	_dialogue_is_cutscene = as_cutscene
	if as_cutscene:
		set_cutscene(true)
	elif hud != null:
		hud.visible = false
	dialogue_box.play(sequence)


## The [DialogueSequence] with [param id] from the dialogue library, or null (with a warning).
func find_dialogue(id: StringName) -> DialogueSequence:
	var sequence := DialogueLibrary.load_directory().get(id) as DialogueSequence
	if sequence == null:
		push_warning("LevelController: no dialogue sequence '%s'" % id)
	return sequence


## Hook for subclasses: the level's dialogue starts. By default plays [member dialogue_id].
func _begin_dialogue() -> void:
	if dialogue_id != &"":
		play_dialogue(find_dialogue(dialogue_id), freeze_during_dialogue)


## Hook for subclasses: [param line] of the level's dialogue appeared on screen.
func _handle_dialogue_line_started(_line: DialogueLine) -> void:
	pass


## Hook for subclasses: a dialogue line carrying [param event] started.
func _handle_dialogue_event(_event: StringName) -> void:
	pass


## Hook for subclasses: the level's dialogue ended.
func _handle_dialogue_finished() -> void:
	pass


func _place_skater() -> void:
	skater = _find_skater(self)
	var spawn := get_node_or_null(spawn_point_path) as Node3D
	if skater == null:
		skater = SKATER_SCENE.instantiate() as Skater
		skater.name = "Skater"
		if spawn != null:
			skater.transform = global_transform.affine_inverse() * spawn.global_transform
		add_child(skater)
	elif spawn != null:
		skater.global_transform = spawn.global_transform
		skater.set_heading(-spawn.global_basis.z)
		skater.camera_rig.snap_behind(skater.global_position, skater.heading)
	skater.bind_progress(game_state)


func _use_skater_camera() -> void:
	for node: Node in find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if camera.get_viewport() == get_viewport() and camera != skater.camera:
			camera.current = false
	skater.camera.make_current()


func _track_barriers() -> void:
	for node: Node in get_tree().get_nodes_in_group(InvisibleBarrier.GROUP):
		if is_ancestor_of(node):
			(node as InvisibleBarrier).track(skater)


func _mount_score_keeper() -> void:
	score_keeper = ScoreKeeper.new()
	score_keeper.name = "ScoreKeeper"
	score_keeper.set_goal(goal)
	add_child(score_keeper)
	score_keeper.bind(skater)


func _mount_audio_bridge() -> void:
	audio_bridge = AudioBridge.new()
	audio_bridge.name = "AudioBridge"
	add_child(audio_bridge)
	audio_bridge.bind(skater, score_keeper)


func _mount_hud() -> void:
	if not ResourceLoader.exists(HUD_SCENE_PATH):
		return
	var hud_scene := load(HUD_SCENE_PATH) as PackedScene
	hud = hud_scene.instantiate() as Hud if hud_scene != null else null
	if hud == null:
		push_warning("LevelController: %s is not a Hud scene" % HUD_SCENE_PATH)
		return
	var layer := get_node_or_null(ui_layer_path)
	(layer if layer != null else self).add_child(hud)
	hud.bind(skater, score_keeper)


func _start_dialogue() -> void:
	if dialogue_box == null:
		return
	dialogue_box.line_started.connect(_on_dialogue_box_line_started)
	dialogue_box.event_triggered.connect(_on_dialogue_box_event_triggered)
	dialogue_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
	dialogue_voice = DialogueVoice.new()
	dialogue_voice.name = "DialogueVoice"
	add_child(dialogue_voice)
	dialogue_voice.bind(dialogue_box)
	_begin_dialogue()


static func _find_skater(node: Node) -> Skater:
	for child: Node in node.get_children():
		if child is Skater:
			return child as Skater
		var found := _find_skater(child)
		if found != null:
			return found
	return null


func _on_goal_reached() -> void:
	open_portal()


func _on_portal_entered() -> void:
	if _completed:
		return
	_completed = true
	if advances_level:
		game_state.advance_level()
	game_state.save_game()
	level_completed.emit()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	_handle_dialogue_line_started(line)


func _on_dialogue_box_event_triggered(event: StringName) -> void:
	_handle_dialogue_event(event)


func _on_dialogue_box_sequence_finished() -> void:
	if _dialogue_is_cutscene:
		_dialogue_is_cutscene = false
		set_cutscene(false)
	elif hud != null:
		hud.visible = true
	_handle_dialogue_finished()
