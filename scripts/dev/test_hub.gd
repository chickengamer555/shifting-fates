class_name TestHub
extends Node
## Developer test hub: pick any playable scene and go there with every ability unlocked.
##
## Not part of the shipped flow. Open [code]scenes/dev/test_hub.tscn[/code] directly, or press
## F1 ([code]toggle_test_hub[/code]) anywhere in a debug build (see [code]DevHotkeys[/code]).
## The hub runs on a GameState of its own with [member GameState.unlock_all] on and its own
## save and paint files, so the player's real save and look are never touched.
## [br]It shows one screen at a time under [code]Screens[/code], swapped behind a fade, and
## wires each the way the game flow would: levels get the hub's GameState, finishing one goes
## on to the next listed level (or back to the hub), the opening leads into the intro, and the
## main menu entry runs the whole game flow ([code]scenes/game.tscn[/code]) on the hub's
## GameState. The hub's pause menu (Esc) offers Quit, which returns to the hub list; inside
## the full game flow its own pause menu applies and F1 comes back here.
## [br]Scenes are listed in [constant ENTRIES], one line each; entries whose scene file is
## missing are left out.
## [br]Dev arg (after [code]--[/code]): [code]--go=<scene path or entry title>[/code] opens
## that entry at once, e.g. [code]--go=intro[/code] or [code]--go="Intro: paint step"[/code].

const GAME_STATE := preload("res://autoload/game_state.gd")
const MENU_SCENE_PATH := "res://scenes/dev/test_hub_menu.tscn"
const GAME_FLOW_PATH := "res://scenes/game.tscn"
const INTRO_PATH := "res://scenes/levels/intro.tscn"
const SAVE_PATH := "user://test_hub_save.cfg"
const APPEARANCE_PATH := "user://test_hub_appearance.tres"
## Keys of an entry in [constant ENTRIES].
const KEY_TITLE := "title"
const KEY_PATH := "path"
const KEY_NOTE := "note"
## GameState level set while the scene plays; 0 leaves it as it is.
const KEY_LEVEL := "level"
## True for the numbered level scenes: finishing level N goes on to level N + 1's entry.
const KEY_RUN := "run"
## User arg that opens an entry at start (see the class docs).
const GO_ARG := "--go="
## Every scene on offer, in list order.
const ENTRIES: Array[Dictionary] = [
	{"title": "Main menu", "path": GAME_FLOW_PATH, "level": 1,
		"note": "the full game flow from the title screen"},
	{"title": "Opening", "path": "res://scenes/levels/opening.tscn", "level": 1,
		"note": "the story opening, then the intro"},
	{"title": "Intro", "path": INTRO_PATH, "level": 1,
		"note": "dialogue, painting, the title cross"},
	{"title": "Intro: paint step", "path": "res://scenes/dev/intro_paint.tscn", "level": 1,
		"note": "straight to painting the skater"},
	{"title": "Level 1", "path": "res://scenes/levels/level_1.tscn", "level": 1, "run": true,
		"note": "tutorial"},
	{"title": "Level 2", "path": "res://scenes/levels/level_2.tscn", "level": 2, "run": true,
		"note": "the god lights"},
	{"title": "Level 3", "path": "res://scenes/levels/level_3.tscn", "level": 3, "run": true,
		"note": "the torii gate"},
	{"title": "Skate test", "path": "res://scenes/main.tscn", "level": 0,
		"note": "rails, kicker, towers, spectator camera (Tab)"},
]

## Seconds for each half of a swap (cover, then reveal). 0 swaps at once.
@export var fade_seconds: float = 0.3
@export var fade_color: Color = Color.BLACK

## The hub's own progress store: everything unlocked, its own save files.
var game_state: GAME_STATE = null
## The screen on show (the hub list or a chosen scene).
var current_screen: Node = null

var _switching: bool = false

@onready var _screens: Node = $Screens
@onready var _fade: ScreenFade = $Fade
@onready var _pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	set_meta("verify_unit", "TestHub")
	game_state = GAME_STATE.new()
	game_state.name = "HubGameState"
	game_state.save_path = SAVE_PATH
	game_state.appearance_path = APPEARANCE_PATH
	game_state.unlock_all = true
	add_child(game_state)
	_pause_menu.quit_to_menu_requested.connect(_on_pause_menu_quit_to_menu_requested)
	_swap_to(MENU_SCENE_PATH)
	var go := _go_arg_path()
	if not go.is_empty():
		open_entry.call_deferred(go)


## Scene paths on offer, in list order (entries whose scene is missing are left out).
func entry_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for entry: Dictionary in _available_entries():
		paths.append(entry[KEY_PATH])
	return paths


## Goes to the listed scene at [param path] with its entry's level set.
func open_entry(path: String) -> void:
	var entry := _entry_for(path)
	if entry.is_empty():
		push_warning("TestHub: %s is not listed" % path)
		return
	var level: int = entry[KEY_LEVEL]
	if level > 0:
		game_state.current_level = level
	_transition(path)


## Back to the hub list.
func show_hub() -> void:
	if _pause_menu.is_open:
		_pause_menu.resume()
	_transition(MENU_SCENE_PATH)


## The entry path named by a [constant GO_ARG] user arg (a path, or a title matched
## without case), or empty.
static func _go_arg_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(GO_ARG):
			continue
		var wanted := arg.trim_prefix(GO_ARG)
		for entry: Dictionary in _available_entries():
			var title: String = entry[KEY_TITLE]
			if entry[KEY_PATH] == wanted or title.to_lower() == wanted.to_lower():
				return entry[KEY_PATH]
		push_warning("TestHub: no entry '%s'" % wanted)
	return ""


static func _available_entries() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for entry: Dictionary in ENTRIES:
		if ResourceLoader.exists(entry[KEY_PATH]):
			available.append(entry)
	return available


static func _entry_for(path: String) -> Dictionary:
	for entry: Dictionary in _available_entries():
		if entry[KEY_PATH] == path:
			return entry
	return {}


## The numbered level entry for [param level], or empty past the last one.
static func _level_entry(level: int) -> Dictionary:
	for entry: Dictionary in _available_entries():
		if entry.get(KEY_RUN, false) and entry[KEY_LEVEL] == level:
			return entry
	return {}


func _transition(path: String) -> void:
	if _switching:
		return
	_switching = true
	_pause_menu.enabled = false
	await _fade.cover(fade_color, fade_seconds)
	_swap_to(path)
	await _fade.reveal(fade_seconds)
	_switching = false


func _swap_to(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("TestHub: cannot load '%s'" % path)
		return
	_retire(current_screen)
	AudioDirector.stop_all()
	var screen := scene.instantiate()
	_wire(screen)
	current_screen = screen
	_screens.add_child(screen)
	# The hub list needs no pause; the full game flow brings its own pause menu.
	_pause_menu.enabled = not (screen is TestHubMenu or screen is GameFlow)


func _retire(screen: Node) -> void:
	if screen == null:
		return
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	if screen is CanvasItem:
		(screen as CanvasItem).visible = false
	elif screen is Node3D:
		(screen as Node3D).visible = false
	screen.queue_free()


func _wire(screen: Node) -> void:
	if screen is TestHubMenu:
		var menu := screen as TestHubMenu
		menu.entries = _available_entries()
		menu.entry_picked.connect(open_entry)
		MouseCursor.release()
	elif screen is GameFlow:
		(screen as GameFlow).game_state = game_state
	elif screen is OpeningScene:
		(screen as OpeningScene).finished.connect(_on_opening_finished)
	elif screen is LevelController:
		var level := screen as LevelController
		level.game_state = game_state
		level.level_completed.connect(_on_level_completed)


func _on_pause_menu_quit_to_menu_requested() -> void:
	show_hub()


func _on_opening_finished() -> void:
	open_entry.call_deferred(INTRO_PATH)


func _on_level_completed() -> void:
	var next := _level_entry(game_state.current_level)
	if next.is_empty():
		show_hub.call_deferred()
	else:
		open_entry.call_deferred(next[KEY_PATH])
