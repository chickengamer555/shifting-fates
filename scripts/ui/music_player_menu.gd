class_name MusicPlayerMenu
extends Control
## The music player: shows what is playing, lets the player pick one track (or Auto: the intro
## theme on the intro, shuffle elsewhere) and skip to the next track.
##
## The choice goes to a Settings node ([member settings]; the [code]Settings[/code] autoload by
## default), which the AudioDirector ([member director]; the autoload by default) follows at
## once. Back (or ui_cancel) saves and emits [signal closed]. One [WishButton] per choice is
## built at ready under [code]%Tracks[/code]: [code]Auto[/code] first, then each track named by
## its [MusicTracks] id; the chosen one is pressed.

## The player left the screen. The owner decides what to show next.
signal closed

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")
const DIRECTOR_SCRIPT := preload("res://autoload/audio_director.gd")
const WISH_BUTTON := preload("res://scripts/ui/wish_button.gd")
const AUTO_BUTTON_NAME := "Auto"
const NOW_PLAYING_FORMAT := "Now playing: %s"
const SILENT_TEXT := "No music here"

## The preferences holding the choice. Null at ready means the [code]Settings[/code] autoload.
var settings: SETTINGS_SCRIPT = null
## Plays the music. Null at ready means the [code]AudioDirector[/code] autoload.
var director: DIRECTOR_SCRIPT = null

## Track id (or [constant MusicTracks.AUTO]) -> its button.
var _buttons: Dictionary[StringName, BaseButton] = {}
var _group := ButtonGroup.new()

@onready var _now_playing: Label = %NowPlaying
@onready var _tracks: Container = %Tracks
@onready var _skip_button: BaseButton = %SkipButton
@onready var _back_button: BaseButton = %BackButton


func _ready() -> void:
	set_meta("verify_unit", "MusicPlayerMenu")
	if settings == null:
		settings = Settings
	if director == null:
		director = AudioDirector
	_add_choice(MusicTracks.AUTO, AUTO_BUTTON_NAME)
	for track: StringName in MusicTracks.IDS:
		_add_choice(track, String(track))
	_skip_button.pressed.connect(_on_skip_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	director.music_changed.connect(_on_director_music_changed)
	visibility_changed.connect(_on_visibility_changed)
	UiSounds.wire_back(_back_button)
	UiSounds.wire(self)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Shows the stored choice and what is playing, without counting as a change.
func refresh() -> void:
	var chosen: StringName = settings.music_track
	for track: StringName in _buttons:
		_buttons[track].set_pressed_no_signal(track == chosen)
	_update_now_playing()


## Picks [param track] (a [MusicTracks] id, or AUTO) as if its button were pressed.
func choose(track: StringName) -> void:
	settings.set_music_track(track)
	refresh()


## Saves any change and emits [signal closed].
func close() -> void:
	if settings.is_dirty:
		settings.save_settings()
	closed.emit()


func _add_choice(track: StringName, node_name: String) -> void:
	var button: Button = WISH_BUTTON.new()
	button.name = node_name
	button.text = MusicTracks.title(track)
	button.toggle_mode = true
	button.button_group = _group
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(choose.bind(track))
	_tracks.add_child(button)
	_buttons[track] = button


func _update_now_playing() -> void:
	var track: StringName = director.music_track
	var playing: bool = director.music_playing and MusicTracks.is_track(track)
	_now_playing.text = NOW_PLAYING_FORMAT % MusicTracks.title(track) if playing else SILENT_TEXT
	_skip_button.disabled = not playing


func _on_skip_button_pressed() -> void:
	director.skip_track()
	refresh()


func _on_back_button_pressed() -> void:
	close()


func _on_director_music_changed(_track: StringName) -> void:
	_update_now_playing()


func _on_visibility_changed() -> void:
	if visible:
		refresh()
