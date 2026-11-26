class_name GameFlow
extends Node
## Owns the one screen on show and moves between them behind a fade.
##
## Lives in the persistent boot scene [code]scenes/game.tscn[/code]; every screen (menu,
## opening, levels) is a child of [code]Screens[/code] and is freed when the next one comes in.
## Order: main menu -> (new game) opening -> intro -> level 1 (tutorial) -> level 2 -> ...
## Load game reads the save and jumps straight to [member GameState.current_level]. Past the
## last level scene the flow returns to the menu.
## [br]Screens only signal up ([signal MainMenu.new_game_requested],
## [signal OpeningScene.finished], [signal LevelController.level_completed]); the flow decides.
## [br]The way out of the opening is one continuous shot: its white flash is taken over by
## the fade, burns to [member intro_reveal_color] (the intro's red sky), and the red unveils
## the intro. Never a black frame in between.
## [br]Riding through a level's exit portal is seamless, the GDD's "portals displaying next
## area that player gets to seamlessly fly through": no fade, the next level (loaded in the
## background from the moment the exit opened) comes in at once and the player rides on out
## of its way in with the speed and view they went in with
## ([member LevelController.exit_handoff], [member LevelController.arrival_handoff]). Past the
## last level, or without a handoff, it fades as usual.
## [br]Every swap calls [method AudioDirector.stop_all], so loops from one screen never play
## on into the next. The flow also owns the [PauseMenu]: enabled on the opening and levels,
## off on the menu and during transitions; its quit request returns to the menu.

## A new screen is on show. [param screen_id] is one of the [code]SCREEN_*[/code] ids.
signal screen_changed(screen_id: StringName)

const GAME_STATE := preload("res://autoload/game_state.gd")
const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
## Every current screen is in this group, so a leak shows up as a second member.
const SCREEN_GROUP := &"flow_screen"
const SCREEN_MENU := &"menu"
const SCREEN_OPENING := &"opening"
const SCREEN_INTRO := &"intro"
const SCREEN_LEVEL := &"level"

@export_file("*.tscn") var menu_scene_path: String = "res://scenes/ui/main_menu.tscn"
@export_file("*.tscn") var opening_scene_path: String = "res://scenes/levels/opening.tscn"
@export_file("*.tscn") var intro_scene_path: String = "res://scenes/levels/intro.tscn"
## Gameplay level scenes by level number: index 0 is [constant GAME_STATE.FIRST_LEVEL].
@export_file("*.tscn") var level_scene_paths: PackedStringArray = [
	"res://scenes/levels/level_1.tscn",
	"res://scenes/levels/level_2.tscn",
	"res://scenes/levels/level_3.tscn",
]
## Seconds for each half of a transition (cover, then reveal). 0 swaps at once.
@export var fade_seconds: float = 0.6
@export var fade_color: Color = Color.BLACK
## The opening ends in a white flash, so the way out of it starts from white...
@export var opening_exit_color: Color = Color.WHITE
## ...burns to this red and unveils the intro (the upper echelon's red sky) from it.
@export var intro_reveal_color: Color = Color(0.62, 0.02, 0.13)
## How much longer than [member fade_seconds] each half of the opening's exit takes.
@export var opening_exit_stretch: float = 2.5

## Progress store. Defaults to the [code]GameState[/code] autoload; tests inject their own.
var game_state: GAME_STATE = null
## Sound output. Defaults to the [code]AudioDirector[/code] autoload; tests inject their own.
var audio_director: AUDIO_DIRECTOR = null
## The screen on show.
var current_screen: Node = null
## Id of [member current_screen], one of the [code]SCREEN_*[/code] constants.
var current_screen_id: StringName = &""

var _switching: bool = false

@onready var _screens: Node = $Screens
@onready var _fade: ScreenFade = $Fade
@onready var _pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	set_meta("verify_unit", "GameFlow")
	if game_state == null:
		game_state = GameState
	if audio_director == null:
		audio_director = AudioDirector
	_pause_menu.quit_to_menu_requested.connect(_on_pause_menu_quit_to_menu_requested)
	_swap_to(SCREEN_MENU, menu_scene_path)


## Back to level 1 and on to the opening.
func start_new_game() -> void:
	game_state.reset_progress()
	_transition(SCREEN_OPENING, opening_scene_path, fade_color)


## Loads the save and goes straight to the saved level.
func continue_game() -> void:
	game_state.load_game()
	_transition(SCREEN_LEVEL, _level_scene_path(game_state.current_level, true), fade_color)


## Returns to the main menu.
func show_menu() -> void:
	_transition(SCREEN_MENU, menu_scene_path, fade_color)


## Path of the scene for [param level]; empty past the last one unless [param clamp_to_last].
func _level_scene_path(level: int, clamp_to_last: bool = false) -> String:
	if level_scene_paths.is_empty():
		return ""
	var index := level - GAME_STATE.FIRST_LEVEL
	if clamp_to_last:
		index = clampi(index, 0, level_scene_paths.size() - 1)
	if index < 0 or index >= level_scene_paths.size():
		return ""
	return level_scene_paths[index]


func _transition(screen_id: StringName, path: String, color: Color) -> void:
	if _switching:
		return
	if path.is_empty():
		screen_id = SCREEN_MENU
		path = menu_scene_path
	_switching = true
	_pause_menu.enabled = false
	await _fade.cover(color, fade_seconds)
	await _swap_and_reveal(screen_id, path, fade_seconds)


## From the opening's white to red, then the red unveils [param path].
func _transition_through_red(screen_id: StringName, path: String) -> void:
	if _switching:
		return
	_switching = true
	_pause_menu.enabled = false
	var seconds := fade_seconds * opening_exit_stretch
	await _fade.cover_through(opening_exit_color, intro_reveal_color, seconds)
	await _swap_and_reveal(screen_id, path, seconds)


func _swap_and_reveal(screen_id: StringName, path: String, seconds: float) -> void:
	_swap_to(screen_id, path)
	await _fade.reveal(seconds)
	_switching = false


## Straight into the next level through the portal: no fade, the ride carries on.
func _ride_through(path: String, handoff: Dictionary) -> void:
	if _switching:
		return
	_swap_to(SCREEN_LEVEL, path, handoff)


func _swap_to(screen_id: StringName, path: String, handoff: Dictionary = {}) -> void:
	var scene := _load_scene(path)
	if scene == null:
		push_error("GameFlow: cannot load screen '%s'" % path)
		return
	_retire(current_screen)
	audio_director.stop_all()
	var screen := scene.instantiate()
	_wire(screen)
	if screen is LevelController:
		(screen as LevelController).arrival_handoff = handoff
	screen.add_to_group(SCREEN_GROUP)
	current_screen = screen
	current_screen_id = screen_id
	_screens.add_child(screen)
	_pause_menu.enabled = screen_id != SCREEN_MENU
	screen_changed.emit(screen_id)


## Takes [param screen] off show at once and frees it at the end of the frame. Not removed
## from the tree right away: a swap can be triggered from inside a physics callback.
func _retire(screen: Node) -> void:
	if screen == null:
		return
	screen.remove_from_group(SCREEN_GROUP)
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	if screen is CanvasItem:
		(screen as CanvasItem).visible = false
	elif screen is Node3D:
		(screen as Node3D).visible = false
	screen.queue_free()


func _wire(screen: Node) -> void:
	if screen is MainMenu:
		var menu := screen as MainMenu
		menu.has_save = FileAccess.file_exists(game_state.save_path)
		menu.new_game_requested.connect(start_new_game)
		menu.load_game_requested.connect(continue_game)
		MouseCursor.release()
	elif screen is OpeningScene:
		(screen as OpeningScene).finished.connect(_on_opening_finished)
	elif screen is LevelController:
		var level := screen as LevelController
		level.game_state = game_state
		level.level_completed.connect(_on_level_completed)
		level.exit_opened.connect(_on_level_exit_opened)


func _on_pause_menu_quit_to_menu_requested() -> void:
	show_menu()


func _on_opening_finished() -> void:
	_transition_through_red.call_deferred(SCREEN_INTRO, intro_scene_path)


## [param path] loaded, from the background load when one was started.
static func _load_scene(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	return load(path) as PackedScene


func _on_level_exit_opened() -> void:
	# The level the exit leads to: the next one, or level 1 from the intro (not numbered).
	var level := current_screen as LevelController
	var next := game_state.current_level + (1 if level != null and level.advances_level else 0)
	var path := _level_scene_path(next)
	if not path.is_empty():
		ResourceLoader.load_threaded_request(path)


func _on_level_completed() -> void:
	var path := _level_scene_path(game_state.current_level)
	var finished := current_screen as LevelController
	var handoff: Dictionary = finished.exit_handoff if finished != null else {}
	if path.is_empty() or handoff.is_empty():
		_transition.call_deferred(SCREEN_LEVEL, path, fade_color)
	else:
		_ride_through.call_deferred(path, handoff)
