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
## ([member LevelController.exit_handoff], [member LevelController.arrival_handoff]). It
## works both ways: riding back through a level's way in returns to the previous level, out
## of its exit. A [LevelRide] keeps the previous level (the one just left) and the next one
## (built in the background once the exit opens) built and asleep, so the swap needs no
## loading and nothing freezes. Past the last level, or without a handoff, it fades as usual.
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
## Scene path of the screen on show.
var current_path: String = ""
var _ride: LevelRide = null

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
	_ride = LevelRide.new()
	_ride.name = "LevelRide"
	add_child(_ride)
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
	else:
		_ride.keep_only([])
	screen.add_to_group(SCREEN_GROUP)
	current_screen = screen
	current_screen_id = screen_id
	current_path = path
	if screen is LevelController:
		_ride.host(screen as LevelController)
	else:
		_screens.add_child(screen)
	_pause_menu.enabled = screen_id != SCREEN_MENU
	_tell_audio()
	screen_changed.emit(screen_id)
	if screen is LevelController:
		_stage_previous.call_deferred()


## Rides from the level on show into the level from [param path] through a portal: forwards
## out of its way in, or with [param back] out of its exit. The level left is kept asleep to
## ride back into; the one entered comes from the [LevelRide] when it was built ahead.
func _ride_into(path: String, handoff: Dictionary, back: bool) -> void:
	if _switching:
		return
	var old := current_screen as LevelController
	var old_path := current_path
	var level := _ride.take(path)
	if old != null:
		old.remove_from_group(SCREEN_GROUP)
		_ride.keep(old, old_path)
	audio_director.stop_all()
	current_screen_id = SCREEN_INTRO if path == intro_scene_path else SCREEN_LEVEL
	current_path = path
	if level == null:
		var scene := _load_scene(path)
		level = scene.instantiate() as LevelController if scene != null else null
		if level == null:
			push_error("GameFlow: cannot load level '%s'" % path)
			return
		_wire(level)
		level.arrival_handoff = handoff
		level.arrival_via_exit = back
		current_screen = level
		level.add_to_group(SCREEN_GROUP)
		_ride.host(level)
	else:
		current_screen = level
		level.add_to_group(SCREEN_GROUP)
		_ride.show_level(level)
		level.activate(handoff, back)
	_ride.keep_only([old_path])
	_pause_menu.enabled = true
	_tell_audio()
	screen_changed.emit(current_screen_id)
	_stage_previous.call_deferred()


## Starts building the level before the one on show, so riding back costs no loading.
func _stage_previous() -> void:
	var level := current_screen as LevelController
	if level == null:
		return
	var previous := _previous_path(level)
	if not previous.is_empty() and not _ride.has_level(previous):
		_ride.prepare(previous, _wire_kept)


## Path of the level after [param level] (level 1 after the intro); empty past the last.
func _next_path(level: LevelController) -> String:
	return _level_scene_path(level.level_number + 1)


## Path of the level before [param level] (the intro before level 1); empty before the intro.
func _previous_path(level: LevelController) -> String:
	if level.level_number <= 0:
		return ""
	if level.level_number == GAME_STATE.FIRST_LEVEL:
		return intro_scene_path
	return _level_scene_path(level.level_number - 1)


## Lets the audio director follow the screen (music per screen), once it can.
func _tell_audio() -> void:
	if audio_director.has_method(&"on_screen"):
		audio_director.call(&"on_screen", current_screen_id)


func _wire_kept(level: LevelController) -> void:
	_wire(level)


## Takes [param screen] off show at once and frees it at the end of the frame. Not removed
## from the tree right away: a swap can be triggered from inside a physics callback.
func _retire(screen: Node) -> void:
	if screen == null:
		return
	if screen is LevelController:
		screen.remove_from_group(SCREEN_GROUP)
		_ride.discard(screen as LevelController)
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
		level.level_completed.connect(_on_level_completed.bind(level))
		level.level_left_back.connect(_on_level_left_back.bind(level))
		level.exit_opened.connect(_on_level_exit_opened.bind(level))


func _on_pause_menu_quit_to_menu_requested() -> void:
	show_menu()


func _on_opening_finished() -> void:
	_transition_through_red.call_deferred(SCREEN_INTRO, intro_scene_path)


## [param path] loaded, from the background load when one was started.
static func _load_scene(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	return load(path) as PackedScene


func _on_level_exit_opened(level: LevelController) -> void:
	if level != current_screen:
		return
	# Build the level the exit leads to now, so riding through needs no loading.
	var path := _next_path(level)
	if not path.is_empty():
		_ride.prepare(path, _wire_kept)


func _on_level_completed(finished: LevelController) -> void:
	if finished != current_screen:
		return
	var path := _next_path(finished)
	var handoff: Dictionary = finished.exit_handoff
	if path.is_empty() or handoff.is_empty():
		_transition.call_deferred(SCREEN_LEVEL, path, fade_color)
	else:
		_ride_into.call_deferred(path, handoff, false)


func _on_level_left_back(left: LevelController) -> void:
	if left != current_screen:
		return
	var path := _previous_path(left)
	if path.is_empty() or left.back_handoff.is_empty():
		return
	_ride_into.call_deferred(path, left.back_handoff, true)
