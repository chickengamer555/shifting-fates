class_name PauseMenu
extends CanvasLayer
## In-game pause menu: Esc (the [code]pause[/code] action) pauses the game and shows Resume,
## Settings and Quit to main menu.
##
## The menu processes while the tree is paused. Opening it pauses the tree and frees the mouse
## ([MouseCursor]); Resume (or Esc again) unpauses and captures the mouse again if it was captured
## when the menu opened (gameplay), leaving it free otherwise (dialogue). Settings swaps the
## buttons for the shared [SettingsMenu] (its Back, or Esc, returns here). Quit unpauses and emits
## [signal quit_to_menu_requested]; the game flow decides what to show. The game flow turns
## [member enabled] off where pausing makes no sense (the main menu, mid-transition).

## The menu opened and the tree is paused.
signal opened
## The player resumed play; the tree is running again.
signal resumed
## The player chose Quit to main menu. The tree is already running again.
signal quit_to_menu_requested

const PAUSE_ACTION := &"pause"

## While false the pause action is ignored (a menu already open still closes normally).
@export var enabled: bool = true

## True while the menu is showing and the tree is paused.
var is_open: bool = false

var _mouse_was_captured: bool = false

@onready var _panel: Control = %Panel
@onready var _resume_button: BaseButton = %ResumeButton
@onready var _settings_button: BaseButton = %SettingsButton
@onready var _quit_button: BaseButton = %QuitButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	set_meta("verify_unit", "PauseMenu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_quit_button.pressed.connect(_on_quit_button_pressed)
	_settings_menu.closed.connect(_on_settings_menu_closed)
	UiSounds.wire(self)


func _exit_tree() -> void:
	# Never leave the game frozen behind a menu that is gone.
	if is_open:
		is_open = false
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(PAUSE_ACTION):
		return
	if not is_open and not enabled:
		return
	get_viewport().set_input_as_handled()
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


func _close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false


func _show_panel() -> void:
	_settings_menu.visible = false
	_panel.visible = true
	_resume_button.grab_focus.call_deferred()


func _on_resume_button_pressed() -> void:
	resume()


func _on_settings_button_pressed() -> void:
	_panel.visible = false
	_settings_menu.visible = true


func _on_settings_menu_closed() -> void:
	_show_panel()


func _on_quit_button_pressed() -> void:
	quit_to_menu()
