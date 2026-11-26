extends Node
## Player preferences: bus volumes, mouse sensitivity and fullscreen, saved to a config file.
##
## Volumes are 0 to 1 per bus and reach the AudioServer through a perceptual curve. The Music
## and SFX buses are created at startup if the project's bus layout lacks them, so sliders work
## before any audio is authored. Changes apply at once; [method save_settings] writes them
## (the settings menu calls it when closed). Read [member mouse_sensitivity] for camera look.

## Any preference changed (set, loaded or reset).
signal changed

const DEFAULT_PATH := "user://settings.cfg"
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUSES: Array[StringName] = [BUS_MASTER, BUS_MUSIC, BUS_SFX]

const SECTION_AUDIO := "audio"
const SECTION_CONTROLS := "controls"
const SECTION_DISPLAY := "display"
const KEY_MOUSE_SENSITIVITY := "mouse_sensitivity"
const KEY_FULLSCREEN := "fullscreen"

const DEFAULT_VOLUME := 1.0
const DEFAULT_MOUSE_SENSITIVITY := 1.0
const MIN_MOUSE_SENSITIVITY := 0.05
const MAX_MOUSE_SENSITIVITY := 5.0
## Decibels at volume 0+; volume 0 mutes the bus instead.
const SILENCE_DB := -40.0
const HEADLESS_DISPLAY := "headless"

## Where preferences are saved. Set before the node enters the tree to use another file.
@export var settings_path: String = DEFAULT_PATH

## Multiplier for mouse-look speed; 1 is the camera's tuned default.
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var fullscreen: bool = false
## True when something changed since the last save or load.
var is_dirty: bool = false

var master_volume: float:
	get:
		return get_volume(BUS_MASTER)
var music_volume: float:
	get:
		return get_volume(BUS_MUSIC)
var sfx_volume: float:
	get:
		return get_volume(BUS_SFX)

var _volumes: Dictionary[StringName, float] = {}


func _init() -> void:
	_reset_values()


func _ready() -> void:
	set_meta("verify_unit", "Settings")
	ensure_buses()
	load_settings()


## Converts a 0 to 1 volume to decibels: 0 -> -40 dB, 0.5 -> -30 dB, 1 -> 0 dB.
static func volume_to_db(volume: float) -> float:
	return SILENCE_DB - SILENCE_DB * volume * volume


## Adds the Music and SFX buses, routed to Master, if the bus layout lacks them.
static func ensure_buses() -> void:
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, BUS_MASTER)


## The 0 to 1 volume of [param bus]; unknown buses read as full volume.
func get_volume(bus: StringName) -> float:
	return _volumes.get(bus, DEFAULT_VOLUME)


## Sets and applies a bus volume, clamped to 0 to 1. Returns false for a bus not in
## [constant BUSES], which is ignored.
func set_volume(bus: StringName, volume: float) -> bool:
	if not BUSES.has(bus):
		return false
	_volumes[bus] = clampf(volume, 0.0, 1.0)
	_apply_volume(bus)
	_mark_changed()
	return true


## Sets the camera mouse sensitivity multiplier, clamped to
## [constant MIN_MOUSE_SENSITIVITY]..[constant MAX_MOUSE_SENSITIVITY].
func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	_mark_changed()


## Switches the window between fullscreen and windowed and applies it at once.
func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_fullscreen()
	_mark_changed()


## Writes every preference to [member settings_path].
func save_settings() -> void:
	var config := ConfigFile.new()
	for bus: StringName in BUSES:
		config.set_value(SECTION_AUDIO, String(bus), get_volume(bus))
	config.set_value(SECTION_CONTROLS, KEY_MOUSE_SENSITIVITY, mouse_sensitivity)
	config.set_value(SECTION_DISPLAY, KEY_FULLSCREEN, fullscreen)
	var result := config.save(settings_path)
	if result != OK:
		push_warning("Couldn't save settings to %s: %s" % [settings_path, error_string(result)])
		return
	mark_clean()


## Reads [member settings_path] and applies it. A missing file keeps the current values;
## a value of the wrong type is skipped.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		for bus: StringName in BUSES:
			var saved: Variant = _read(config, SECTION_AUDIO, String(bus))
			if _is_number(saved):
				_volumes[bus] = clampf(float(saved), 0.0, 1.0)
		var sensitivity: Variant = _read(config, SECTION_CONTROLS, KEY_MOUSE_SENSITIVITY)
		if _is_number(sensitivity):
			mouse_sensitivity = clampf(
				float(sensitivity), MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
		var saved_fullscreen: Variant = _read(config, SECTION_DISPLAY, KEY_FULLSCREEN)
		if saved_fullscreen is bool:
			fullscreen = saved_fullscreen
	apply_all()
	mark_clean()
	changed.emit()


## Restores the defaults in memory and applies them. Does not save.
func reset_to_defaults() -> void:
	_reset_values()
	apply_all()
	_mark_changed()


## Sends every stored value to the AudioServer and the window.
func apply_all() -> void:
	for bus: StringName in BUSES:
		_apply_volume(bus)
	_apply_fullscreen()


## Marks the current values as saved.
func mark_clean() -> void:
	is_dirty = false


func _reset_values() -> void:
	for bus: StringName in BUSES:
		_volumes[bus] = DEFAULT_VOLUME
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	fullscreen = false


func _mark_changed() -> void:
	is_dirty = true
	changed.emit()


func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	var volume := get_volume(bus)
	AudioServer.set_bus_volume_db(index, volume_to_db(volume))
	AudioServer.set_bus_mute(index, volume <= 0.0)


func _apply_fullscreen() -> void:
	# A headless run (tests, servers) has no window to resize.
	if not is_inside_tree() or DisplayServer.get_name() == HEADLESS_DISPLAY:
		return
	var window := get_window()
	var wanted := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	var is_fullscreen := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	if is_fullscreen != fullscreen:
		window.mode = wanted


## The stored value, or null when the file lacks it.
static func _read(config: ConfigFile, section: String, key: String) -> Variant:
	if not config.has_section_key(section, key):
		return null
	return config.get_value(section, key)


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
