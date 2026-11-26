class_name MainMenu
extends Control
## Title screen: "What do you wish for?" under a branching white light, four wishes in the
## bottom-left corner and the real levels panning by live behind ([MenuLivePan]).
## The title and wishes use the player's font ([method FontLibrary.player_font]).
##
## New game and load are signalled up for the game flow to handle; settings and credits open
## as sub-screens inside this scene. Set [member has_save] so loading is only offered when a
## save exists.

signal new_game_requested
signal load_game_requested

## Whether there is a save to load; the load wish is disabled without one.
@export var has_save: bool = false:
	set(value):
		has_save = value
		if is_node_ready():
			_load_button.disabled = not has_save

@onready var _main_panel: Control = %MainPanel
@onready var _title_label: Label = %TitleLabel
@onready var _new_game_button: BaseButton = %NewGameButton
@onready var _load_button: BaseButton = %LoadButton
@onready var _settings_button: BaseButton = %SettingsButton
@onready var _credits_button: BaseButton = %CreditsButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _credits_screen: CreditsScreen = %CreditsScreen


func _ready() -> void:
	set_meta("verify_unit", "MainMenu")
	_apply_player_font()
	_load_button.disabled = not has_save
	_new_game_button.pressed.connect(_on_new_game_button_pressed)
	_load_button.pressed.connect(_on_load_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_credits_button.pressed.connect(_on_credits_button_pressed)
	_settings_menu.closed.connect(_on_sub_screen_closed)
	_credits_screen.closed.connect(_on_sub_screen_closed)
	_show_only(_main_panel)
	_new_game_button.grab_focus.call_deferred()


func _apply_player_font() -> void:
	var font := FontLibrary.player_font()
	for control: Control in [
		_title_label, _new_game_button, _load_button, _settings_button, _credits_button,
	]:
		control.add_theme_font_override("font", font)


func _show_only(screen: Control) -> void:
	for candidate: Control in [_main_panel, _settings_menu, _credits_screen]:
		candidate.visible = candidate == screen


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()


func _on_load_button_pressed() -> void:
	if has_save:
		load_game_requested.emit()


func _on_settings_button_pressed() -> void:
	_show_only(_settings_menu)


func _on_credits_button_pressed() -> void:
	_show_only(_credits_screen)


func _on_sub_screen_closed() -> void:
	_show_only(_main_panel)
	_new_game_button.grab_focus.call_deferred()
