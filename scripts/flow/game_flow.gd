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

## A new screen is on show. [param screen_id] is one of the [code]SCREEN_*[/code] ids.
signal screen_changed(screen_id: StringName)

const GAME_STATE := preload("res://autoload/game_state.gd")
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
]
## Seconds for each half of a transition (cover, then reveal). 0 swaps at once.
@export var fade_seconds: float = 0.6
@export var fade_color: Color = Color.BLACK
## The opening ends in a white flash, so the way out of it fades through white.
@export var opening_exit_color: Color = Color.WHITE

## Progress store. Defaults to the [code]GameState[/code] autoload; tests inject their own.
var game_state: GAME_STATE = null
## The screen on show.
var current_screen: Node = null
## Id of [member current_screen], one of the [code]SCREEN_*[/code] constants.
var current_screen_id: StringName = &""

var _switching: bool = false

@onready var _screens: Node = $Screens
@onready var _fade: ScreenFade = $Fade


func _ready() -> void:
	set_meta("verify_unit", "GameFlow")
	if game_state == null:
		game_state = GameState
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
	await _fade.cover(color, fade_seconds)
	_swap_to(screen_id, path)
	await _fade.reveal(fade_seconds)
	_switching = false


func _swap_to(screen_id: StringName, path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("GameFlow: cannot load screen '%s'" % path)
		return
	_retire(current_screen)
	var screen := scene.instantiate()
	_wire(screen)
	screen.add_to_group(SCREEN_GROUP)
	current_screen = screen
	current_screen_id = screen_id
	_screens.add_child(screen)
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif screen is OpeningScene:
		(screen as OpeningScene).finished.connect(_on_opening_finished)
	elif screen is LevelController:
		var level := screen as LevelController
		level.game_state = game_state
		level.level_completed.connect(_on_level_completed)


func _on_opening_finished() -> void:
	_transition.call_deferred(SCREEN_INTRO, intro_scene_path, opening_exit_color)


func _on_level_completed() -> void:
	_transition.call_deferred(
		SCREEN_LEVEL, _level_scene_path(game_state.current_level), fade_color)
