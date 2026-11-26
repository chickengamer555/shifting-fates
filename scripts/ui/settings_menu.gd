class_name SettingsMenu
extends Control
## Settings screen: volume sliders, mouse sensitivity and display options
## (fullscreen, 4:3 or widescreen, CRT filter on/off and its intensity).
##
## Edits a Settings node: the [code]Settings[/code] autoload unless [member settings] is set
## before the menu enters the tree. Changes apply live; Back (or ui_cancel) saves and emits
## [signal closed].

## The player left the screen. The owner decides what to show next.
signal closed

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")
const PERCENT := 100.0
const VOLUME_STEP := 0.01
const SENSITIVITY_STEP := 0.05
const INTENSITY_STEP := 0.05
const ASPECT_STANDARD_TEXT := "4:3"
const ASPECT_WIDESCREEN_TEXT := "Widescreen (16:9)"
## Inter weight of the value read-outs (numbers stay in the clean UI font).
const VALUE_WEIGHT := 500

## The preferences this menu edits. Null at ready means the [code]Settings[/code] autoload.
var settings: SETTINGS_SCRIPT = null

## Slider -> bus it controls.
var _volume_sliders: Dictionary[Range, StringName] = {}
## Slider -> label showing its value as a percentage.
var _value_labels: Dictionary[Range, Label] = {}

@onready var _master_slider: Range = %MasterSlider
@onready var _music_slider: Range = %MusicSlider
@onready var _sfx_slider: Range = %SfxSlider
@onready var _sensitivity_slider: Range = %SensitivitySlider
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _fullscreen_check: BaseButton = %FullscreenCheck
@onready var _aspect_button: Button = %AspectButton
@onready var _crt_check: BaseButton = %CrtCheck
@onready var _crt_intensity_slider: Range = %CrtIntensitySlider
@onready var _crt_intensity_value: Label = %CrtIntensityValue
@onready var _back_button: BaseButton = %BackButton


func _ready() -> void:
	set_meta("verify_unit", "SettingsMenu")
	if settings == null:
		settings = Settings
	_volume_sliders = {
		_master_slider: SETTINGS_SCRIPT.BUS_MASTER,
		_music_slider: SETTINGS_SCRIPT.BUS_MUSIC,
		_sfx_slider: SETTINGS_SCRIPT.BUS_SFX,
	}
	_value_labels = {
		_master_slider: _master_value,
		_music_slider: _music_value,
		_sfx_slider: _sfx_value,
		_crt_intensity_slider: _crt_intensity_value,
	}
	var value_font := FontLibrary.ui_font(VALUE_WEIGHT)
	for label: Label in _value_labels.values():
		label.add_theme_font_override("font", value_font)
	_sensitivity_value.add_theme_font_override("font", value_font)
	for slider: Range in _volume_sliders:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = VOLUME_STEP
		slider.value_changed.connect(_on_volume_slider_value_changed.bind(slider))
	_sensitivity_slider.min_value = SETTINGS_SCRIPT.MIN_MOUSE_SENSITIVITY
	_sensitivity_slider.max_value = SETTINGS_SCRIPT.MAX_MOUSE_SENSITIVITY
	_sensitivity_slider.step = SENSITIVITY_STEP
	_sensitivity_slider.value_changed.connect(_on_sensitivity_slider_value_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_check_toggled)
	_aspect_button.toggled.connect(_on_aspect_button_toggled)
	_crt_check.toggled.connect(_on_crt_check_toggled)
	_crt_intensity_slider.min_value = 0.0
	_crt_intensity_slider.max_value = 1.0
	_crt_intensity_slider.step = INTENSITY_STEP
	_crt_intensity_slider.value_changed.connect(_on_crt_intensity_slider_value_changed)
	_back_button.pressed.connect(_on_back_button_pressed)
	visibility_changed.connect(_on_visibility_changed)
	UiSounds.wire_back(_back_button)
	UiSounds.wire(self)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Shows the stored values without counting as a change.
func refresh() -> void:
	for slider: Range in _volume_sliders:
		slider.set_value_no_signal(settings.get_volume(_volume_sliders[slider]))
	_sensitivity_slider.set_value_no_signal(settings.mouse_sensitivity)
	_fullscreen_check.set_pressed_no_signal(settings.fullscreen)
	_aspect_button.set_pressed_no_signal(settings.widescreen)
	_crt_check.set_pressed_no_signal(settings.crt_enabled)
	_crt_intensity_slider.set_value_no_signal(settings.crt_intensity)
	_update_value_labels()


## Saves any changes and emits [signal closed].
func close() -> void:
	if settings.is_dirty:
		settings.save_settings()
	closed.emit()


func _update_value_labels() -> void:
	_sensitivity_value.text = "%.2fx" % _sensitivity_slider.value
	for slider: Range in _value_labels:
		_value_labels[slider].text = "%d%%" % roundi(slider.value * PERCENT)
	_aspect_button.text = (
		ASPECT_WIDESCREEN_TEXT if _aspect_button.button_pressed else ASPECT_STANDARD_TEXT)
	_crt_intensity_slider.editable = _crt_check.button_pressed


func _on_volume_slider_value_changed(value: float, slider: Range) -> void:
	settings.set_volume(_volume_sliders[slider], value)
	_update_value_labels()


func _on_sensitivity_slider_value_changed(value: float) -> void:
	settings.set_mouse_sensitivity(value)
	_update_value_labels()


func _on_fullscreen_check_toggled(enabled: bool) -> void:
	settings.set_fullscreen(enabled)


func _on_aspect_button_toggled(enabled: bool) -> void:
	settings.set_widescreen(enabled)
	_update_value_labels()


func _on_crt_check_toggled(enabled: bool) -> void:
	settings.set_crt_enabled(enabled)
	_update_value_labels()


func _on_crt_intensity_slider_value_changed(value: float) -> void:
	settings.set_crt_intensity(value)
	_update_value_labels()


func _on_back_button_pressed() -> void:
	close()


func _on_visibility_changed() -> void:
	if visible:
		refresh()
