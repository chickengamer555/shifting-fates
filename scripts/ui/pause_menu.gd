class_name PauseMenu
extends CanvasLayer
## In-game pause menu: Esc (the [code]pause[/code] action) pauses the game and shows Resume,
## Repaint (in a level), Settings, Music and Quit to main menu.
##
## The menu processes while the tree is paused. Opening it pauses the tree and frees the mouse
## ([MouseCursor]); Resume (or Esc again) unpauses and captures the mouse again if it was captured
## when the menu opened (gameplay), leaving it free otherwise (dialogue). Settings swaps the
## buttons for the shared [SettingsMenu], Music for the [MusicPlayerMenu] (their Back, or Esc,
## returns here). In a level Repaint swaps the buttons for Yourself, Your board and Back;
## choosing one hides the menu and the level on show ([method LevelController.open_repaint])
## opens the paint screen on the skater where it stands, with the game still paused. When
## the player presses Done the menu comes back.
## Quit unpauses and emits
## [signal quit_to_menu_requested]; the game flow decides what to show. The game flow turns
## [member enabled] off where pausing makes no sense (the main menu, mid-transition).

## The menu opened and the tree is paused.
signal opened
## The player resumed play; the tree is running again.
signal resumed
## The player chose Quit to main menu. The tree is already running again.
signal quit_to_menu_requested
## Repaint opened the paint screen on [param creator] (the menu is hidden meanwhile).
signal repaint_opened(creator: PaintCreator)

const PAUSE_ACTION := &"pause"

## While false the pause action is ignored (a menu already open still closes normally).
@export var enabled: bool = true

## True while the menu is showing and the tree is paused.
var is_open: bool = false
## True while Repaint's paint screen is open (the menu is hidden, the tree still paused).
var repainting: bool = false

var _repaint_creator: PaintCreator = null

var _mouse_was_captured: bool = false

@onready var _panel: Control = %Panel
@onready var _resume_button: BaseButton = %ResumeButton
@onready var _settings_button: BaseButton = %SettingsButton
@onready var _repaint_button: BaseButton = %RepaintButton
@onready var _repaint_choices: Control = %RepaintChoices
@onready var _buttons: Control = %ResumeButton.get_parent()
@onready var _music_button: BaseButton = %MusicButton
@onready var _quit_button: BaseButton = %QuitButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _music_menu: MusicPlayerMenu = %MusicPlayerMenu


func _ready() -> void:
	set_meta("verify_unit", "PauseMenu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_music_button.pressed.connect(_on_music_button_pressed)
	_quit_button.pressed.connect(_on_quit_button_pressed)
	_settings_menu.closed.connect(_on_settings_menu_closed)
	_repaint_button.pressed.connect(_on_repaint_button_pressed)
	(%RepaintBody as BaseButton).pressed.connect(open_repaint.bind(PaintCreator.Mode.PLAYER))
	(%RepaintBoard as BaseButton).pressed.connect(open_repaint.bind(PaintCreator.Mode.BOARD))
	(%RepaintBack as BaseButton).pressed.connect(_show_panel)
	_music_menu.closed.connect(_on_settings_menu_closed)
	UiSounds.wire(self)


func _exit_tree() -> void:
	# Never leave the game frozen behind a menu that is gone.
	if is_open:
		is_open = false
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(PAUSE_ACTION):
		return
	if repainting:
		# Esc on the paint screen is Done: the paint is kept and the menu comes back.
		get_viewport().set_input_as_handled()
		if is_instance_valid(_repaint_creator):
			_repaint_creator.finish()
		return
	if not is_open and not enabled:
		return
	get_viewport().set_input_as_handled()
	if is_open and _repaint_choices.visible:
		_show_panel()
		return
	toggle()


## Opens the menu when closed, resumes when open.
func toggle() -> void:
	if is_open:
		resume()
	else:
		open()


## Pauses the tree and shows the menu, with the mouse free. Does nothing while disabled.
func open() -> void:
	if is_open or not enabled:
		return
	is_open = true
	visible = true
	_show_panel()
	get_tree().paused = true
	_mouse_was_captured = MouseCursor.is_captured()
	MouseCursor.release()
	opened.emit()


## Hides the menu and unpauses the tree, capturing the mouse again if play had it captured.
func resume() -> void:
	if not is_open:
		return
	_close()
	if _mouse_was_captured:
		MouseCursor.capture()
	resumed.emit()


## Hides the menu, unpauses and asks the game flow to go back to the main menu.
func quit_to_menu() -> void:
	_close()
	quit_to_menu_requested.emit()


## The level on show that can open Repaint now, or null (no level, or it is painting).
func repaint_level() -> LevelController:
	for node in get_tree().get_nodes_in_group(LevelController.LEVEL_GROUP):
		var level := node as LevelController
		if level != null and level.can_repaint():
			return level
	return null


## Opens Repaint on [param mode] (body or board) from the open menu: hides the menu and
## has the level on show open the paint screen. Returns the paint screen, or null when
## there is none to open.
func open_repaint(mode: PaintCreator.Mode) -> PaintCreator:
	if not is_open or repainting:
		return null
	var level := repaint_level()
	if level == null:
		return null
	var creator := level.open_repaint(mode)
	if creator == null:
		return null
	repainting = true
	_repaint_creator = creator
	visible = false
	level.repaint_finished.connect(_on_level_repaint_finished, CONNECT_ONE_SHOT)
	repaint_opened.emit(creator)
	return creator


func _close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false


func _show_panel() -> void:
	_settings_menu.visible = false
	_music_menu.visible = false
	_repaint_choices.visible = false
	_buttons.visible = true
	_repaint_button.visible = repaint_level() != null
	_panel.visible = true
	_resume_button.grab_focus.call_deferred()


func _on_repaint_button_pressed() -> void:
	_buttons.visible = false
	_repaint_choices.visible = true
	(%RepaintBody as Control).grab_focus.call_deferred()


func _on_resume_button_pressed() -> void:
	resume()


func _on_settings_button_pressed() -> void:
	_panel.visible = false
	_settings_menu.visible = true


func _on_music_button_pressed() -> void:
	_panel.visible = false
	_music_menu.visible = true


func _on_settings_menu_closed() -> void:
	_show_panel()


func _on_quit_button_pressed() -> void:
	quit_to_menu()


func _on_level_repaint_finished() -> void:
	repainting = false
	_repaint_creator = null
	if not is_open:
		return
	visible = true
	MouseCursor.release()
	_show_panel()
