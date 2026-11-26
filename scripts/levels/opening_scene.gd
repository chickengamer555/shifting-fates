class_name OpeningScene
extends Node3D
## The opening: darkness, the heart monitor and a doctor somewhere far away, and a light.
## The light is God ([code]UI/GodLight[/code], a [GodOrb]); the player wakes and God speaks to
## them (dialogue [code]opening[/code]).
##
## The light fades in large at the centre of the dark screen and, the first time God speaks,
## rises to its place at the top of the screen, where the [DialogueBox] writes God's words
## under it (the box's own orb row is turned off). It breathes faster while God talks and
## kicks with every word. All sound goes through the [code]AudioDirector[/code]
## ([member audio_director]): the heart monitor loop and the doctor's voice start with the
## scene; the first time God speaks the ambience is ducked by [member god_duck_amount]; each
## line brightens the light a little and lowers the doctor's voice by the same amount. A
## [DialogueVoice] gives God a voice. When the dialogue ends the light swells until the screen
## is white while the doctor and the ambience fade out, and [signal finished] is emitted.
## Finishing, or leaving the tree any other way, turns the heart monitor off and stops the
## doctor, so neither carries into the next screen.
## [br]The stream-less [code]Audio/MonitorBeep[/code] and [code]Audio/DoctorVoice[/code]
## players only mirror the director's heart and doctor levels (their volume_db is what the
## scene's tests read); they never play.

## The white flash is complete: move on to the intro.
signal finished

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
const DIALOGUE_ID := &"opening"

## Seconds for the white flash at the end.
@export var flash_seconds: float = 2.0
## Seconds for the ambience duck and each doctor volume change.
@export var volume_fade_seconds: float = 2.0
## Seconds for the light to come up out of the darkness.
@export var fade_in_seconds: float = 2.5
## Seconds for the light to rise to the top once God first speaks.
@export var settle_seconds: float = 1.8
## How much bigger the light is while it hangs in the middle of the screen.
@export var start_scale: float = 1.8
## Extra orb brightness reached on the last line, before the flash.
@export var growth_flare: float = 0.35
## Orb brightness added and orb size reached at the peak of the flash.
@export var flash_flare: float = 2.5
@export var flash_scale: float = 16.0
## How far the ambience is ducked once God has spoken (0 = not at all, 1 = silent).
@export_range(0.0, 1.0) var god_duck_amount: float = 0.5

## Sound output. Null at ready means the [code]AudioDirector[/code] autoload; tests inject
## their own before the scene enters the tree.
var audio_director: AUDIO_DIRECTOR = null
## True once God's first line has started.
var god_has_spoken: bool = false
## How far through the dialogue we are, 0..1; drives the light and the doctor's voice.
var light_growth: float = 0.0
## True once the light has risen to its place at the top.
var light_settled: bool = false

var _sequence: DialogueSequence = null
var _lines_seen: int = 0
var _flashing: bool = false
var _finished: bool = false

@onready var _light: GodOrb = $UI/GodLight
@onready var _dialogue_box: DialogueBox = $UI/DialogueBox
@onready var _flash: ColorRect = $UI/WhiteFlash
@onready var _monitor_meter: AudioStreamPlayer = $Audio/MonitorBeep
@onready var _doctor_meter: AudioStreamPlayer = $Audio/DoctorVoice


func _ready() -> void:
	set_meta("verify_unit", "Opening")
	if audio_director == null:
		audio_director = AudioDirector
	_flash.color.a = 0.0
	_dialogue_box.orbs_visible = false
	_light.presence_seconds = fade_in_seconds
	_light.presence = 1.0
	_light.scale = Vector2.ONE * start_scale
	_start_audio()
	var voice := DialogueVoice.new()
	voice.name = "DialogueVoice"
	voice.director = audio_director
	add_child(voice)
	voice.bind(_dialogue_box)
	_dialogue_box.line_started.connect(_on_dialogue_box_line_started)
	_dialogue_box.word_revealed.connect(_on_dialogue_box_word_revealed)
	_dialogue_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
	_sequence = DialogueLibrary.load_directory().get(DIALOGUE_ID) as DialogueSequence
	if _sequence == null:
		push_error("OpeningScene: dialogue '%s' is missing" % DIALOGUE_ID)
		return
	_dialogue_box.play(_sequence)


func _exit_tree() -> void:
	_stop_audio()


func _process(_delta: float) -> void:
	_mirror_levels()
	if not _flashing:
		_light.speaking = _dialogue_box.speaking_god == DialogueSpeakers.GOD
		_light.flare = growth_flare * light_growth


func _start_audio() -> void:
	audio_director.duck_ambience(0.0)
	audio_director.set_heart_monitor(true)
	audio_director.set_voice_level(SoundBank.SPEAKER_DOCTOR, 1.0)
	audio_director.start_voice(SoundBank.SPEAKER_DOCTOR)


func _stop_audio() -> void:
	if audio_director == null:
		return
	audio_director.set_heart_monitor(false)
	audio_director.stop_voice(SoundBank.SPEAKER_DOCTOR)


## Copies the director's heart and doctor levels onto the stream-less meter players.
func _mirror_levels() -> void:
	var heart := audio_director.ambience_level if audio_director.heart_monitor_active else 0.0
	_monitor_meter.volume_db = maxf(linear_to_db(heart), AudioLevels.SILENT_DB)
	var doctor := audio_director.voice_player(SoundBank.SPEAKER_DOCTOR)
	if doctor != null:
		_doctor_meter.volume_db = doctor.volume_db


## Lifts the light from the middle of the screen to God's place above the dialogue. The
## light and the box share one canvas layer, so the box's global slot is the light's position.
func _settle_light() -> void:
	var target := _dialogue_box.god_slot_center(DialogueSpeakers.GOD) - _light.size * 0.5
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_light, "position", target, settle_seconds)
	tween.tween_property(_light, "scale", Vector2.ONE, settle_seconds)
	tween.chain().tween_callback(func() -> void: light_settled = true)


## The light swells from its place to fill the screen (centring as it grows), then the
## screen burns to white: the glow arrives first, the white overlay catches up at the end.
func _flash_to_white() -> void:
	_flashing = true
	_light.speaking = false
	audio_director.set_voice_level(SoundBank.SPEAKER_DOCTOR, 0.0, volume_fade_seconds)
	audio_director.stop_voice(SoundBank.SPEAKER_DOCTOR)
	audio_director.duck_ambience(1.0, flash_seconds)
	var centre := get_viewport().get_visible_rect().size * 0.5 - _light.size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_light, "flare", flash_flare, flash_seconds)
	tween.tween_property(_light, "position", centre, flash_seconds) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_light, "scale", Vector2.ONE * flash_scale, flash_seconds) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_flash, "color:a", 1.0, flash_seconds) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tween.chain().tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_stop_audio()
	finished.emit()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	_lines_seen += 1
	light_growth = clampf(float(_lines_seen) / float(maxi(_sequence.lines.size(), 1)), 0.0, 1.0)
	audio_director.set_voice_level(
		SoundBank.SPEAKER_DOCTOR, 1.0 - light_growth, volume_fade_seconds)
	if not god_has_spoken and DialogueSpeakers.is_god(line.speaker):
		god_has_spoken = true
		audio_director.duck_ambience(god_duck_amount, volume_fade_seconds)
		_settle_light()


func _on_dialogue_box_word_revealed(speaker: StringName) -> void:
	if speaker == DialogueSpeakers.GOD:
		_light.pulse()


func _on_dialogue_box_sequence_finished() -> void:
	_flash_to_white()
