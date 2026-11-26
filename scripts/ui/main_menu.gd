class_name MainMenu
extends Control
## Title screen: the god ([GodOrb]) at the top centre with light branching out of it across
## the top, "What do you wish for?" beneath in Cinzel, four wishes ([WishButton]s) in the
## bottom-left corner and the real levels panning by live behind ([MenuLivePan]) under a
## soft vignette.
##
## New game and load are signalled up for the game flow to handle; settings and credits open
## as sub-screens inside this scene. Set [member has_save] so loading is only offered when a
## save exists.

signal new_game_requested
signal load_game_requested

## Cinzel weight and letter spacing (px) of the title.
const TITLE_WEIGHT := 500
const TITLE_SPACING := 3

## Whether there is a save to load; the load wish is disabled without one.
@export var has_save: bool = false:
	set(value):
		has_save = value
		if is_node_ready():
			_load_button.disabled = not has_save

## File the title's font was loaded from (see [method FontLibrary.source_path]).
var title_font_path: String:
	get:
		return FontLibrary.source_path(_title_label.get_theme_font("font"))
## File the wishes' font was loaded from.
var wish_font_path: String:
	get:
		return FontLibrary.source_path(_new_game_button.get_theme_font("font"))

@onready var _main_panel: Control = %MainPanel
@onready var _title_label: Label = %TitleLabel
@onready var _new_game_button: BaseButton = %NewGameButton
@onready var _load_button: BaseButton = %LoadButton
@onready var _settings_button: BaseButton = %SettingsButton
@onready var _credits_button: BaseButton = %CreditsButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _credits_screen: CreditsScreen = %CreditsScreen
@onready var _orb: GodOrb = %MenuOrb
@onready var _light: ColorRect = %LightBranches
@onready var _light_material: ShaderMaterial = _light.material as ShaderMaterial
@onready var _shade_material: ShaderMaterial = (%Shade as CanvasItem).material as ShaderMaterial


func _ready() -> void:
	set_meta("verify_unit", "MainMenu")
	_apply_title_font()
	_load_button.disabled = not has_save
	_new_game_button.pressed.connect(_on_new_game_button_pressed)
	_load_button.pressed.connect(_on_load_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_credits_button.pressed.connect(_on_credits_button_pressed)
	_settings_menu.closed.connect(_on_sub_screen_closed)
	_credits_screen.closed.connect(_on_sub_screen_closed)
	resized.connect(_on_resized)
	_orb.snap_presence()
	_show_only(_main_panel)
	_on_resized()
	# Focus the first wish before the sounds are wired, so opening the menu is silent.
	_new_game_button.grab_focus()
	UiSounds.wire(self)


func _process(_delta: float) -> void:
	_light_material.set_shader_parameter(&"breath", _orb.breath)
	_light_material.set_shader_parameter(&"origin",
		_orb.global_position + _orb.size * 0.5 - _light.global_position)


func _apply_title_font() -> void:
	var font := FontLibrary.title_font(TITLE_WEIGHT)
	if font is FontVariation:
		(font as FontVariation).spacing_glyph = TITLE_SPACING
	_title_label.add_theme_font_override("font", font)


func _show_only(screen: Control) -> void:
	for candidate: Control in [_main_panel, _settings_menu, _credits_screen]:
		candidate.visible = candidate == screen


func _on_resized() -> void:
	_light_material.set_shader_parameter(&"rect_size", _light.size)
	if size.y > 0.0:
		_shade_material.set_shader_parameter(&"aspect", size.x / size.y)


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
