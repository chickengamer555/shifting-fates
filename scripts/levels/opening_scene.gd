class_name OpeningScene
extends Node3D
## The opening: the player wakes in a hospital bed under a bright, pulsing light while God
## speaks to them (dialogue [code]opening[/code]).
##
## The heart monitor's trace blinks with every beat. All sound goes through the
## [code]AudioDirector[/code] ([member audio_director]): the heart monitor loop and the
## doctor's voice start with the scene; the first time God speaks the ambience (heart monitor
## and wind) is ducked by [member god_duck_amount]; each line brightens the light a little
## and lowers the doctor's voice by the same amount. A [DialogueVoice] gives God a voice.
## When the dialogue ends the light expands into a white flash while the doctor and the
## ambience fade out, and [signal finished] is emitted for the game flow.
## [br]The stream-less [code]Audio/MonitorBeep[/code] and [code]Audio/DoctorVoice[/code]
## players only mirror the director's heart and doctor levels (their volume_db is what the
## scene's tests read); they never play.

## The white flash is complete: move on to the intro.
signal finished

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
const DIALOGUE_ID := &"opening"
## The trace stays lit for this part of each beat.
const TRACE_ON_FRACTION := 0.25
## How much bigger the light's glowing orb grows during the flash.
const FLASH_ORB_SCALE := 6.0

## Seconds for the light to expand into the white flash.
@export var flash_seconds: float = 2.0
## Seconds for the ambience duck and each doctor volume change.
@export var volume_fade_seconds: float = 2.0
## Seconds between heartbeats (the trace blink).
@export var beat_seconds: float = 0.9
## How far the ambience is ducked once God has spoken (0 = not at all, 1 = silent).
@export_range(0.0, 1.0) var god_duck_amount: float = 0.5
## Light energy at the start, before any line.
@export var light_start_energy: float = 1.5
## Light energy reached on the last line, before the flash.
@export var light_end_energy: float = 5.0
## Light energy at the peak of the flash.
@export var light_flash_energy: float = 24.0
## How far the light swings around its energy, as a fraction of it.
@export_range(0.0, 1.0) var light_wobble: float = 0.3
## Light oscillations per second.
@export var light_wobble_hz: float = 0.6

## Sound output. Null at ready means the [code]AudioDirector[/code] autoload; tests inject
## their own before the scene enters the tree.
var audio_director: AUDIO_DIRECTOR = null
## True once God's first line has started.
var god_has_spoken: bool = false
## How far through the dialogue we are, 0..1; drives the light and the doctor's voice.
var light_growth: float = 0.0

var _sequence: DialogueSequence = null
var _lines_seen: int = 0
var _time: float = 0.0
var _beat_time: float = 0.0
var _flashing: bool = false
var _finished: bool = false

@onready var _light: OmniLight3D = $BrightLight
@onready var _orb: MeshInstance3D = $BrightLight/Orb
@onready var _trace: Node3D = $Room/HeartMonitor/Trace
@onready var _dialogue_box: DialogueBox = $UI/DialogueBox
@onready var _flash: ColorRect = $UI/WhiteFlash
@onready var _monitor_meter: AudioStreamPlayer = $Audio/MonitorBeep
@onready var _doctor_meter: AudioStreamPlayer = $Audio/DoctorVoice


func _ready() -> void:
	set_meta("verify_unit", "Opening")
	if audio_director == null:
		audio_director = AudioDirector
	_flash.color.a = 0.0
	_light.light_energy = light_start_energy
	_start_audio()
	var voice := DialogueVoice.new()
	voice.name = "DialogueVoice"
	voice.director = audio_director
	add_child(voice)
	voice.bind(_dialogue_box)
	_dialogue_box.line_started.connect(_on_dialogue_box_line_started)
	_dialogue_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
	_sequence = DialogueLibrary.load_directory().get(DIALOGUE_ID) as DialogueSequence
	if _sequence == null:
		push_error("OpeningScene: dialogue '%s' is missing" % DIALOGUE_ID)
		return
	_dialogue_box.play(_sequence)


func _process(delta: float) -> void:
	_time += delta
	_tick_heartbeat(delta)
	_mirror_levels()
	if not _flashing:
		var energy := lerpf(light_start_energy, light_end_energy, light_growth)
		var wobble := 1.0 + light_wobble * sin(TAU * light_wobble_hz * _time)
		_light.light_energy = energy * wobble


func _start_audio() -> void:
	audio_director.duck_ambience(0.0)
	audio_director.set_heart_monitor(true)
	audio_director.set_voice_level(SoundBank.SPEAKER_DOCTOR, 1.0)
	audio_director.start_voice(SoundBank.SPEAKER_DOCTOR)


func _tick_heartbeat(delta: float) -> void:
	_beat_time = fmod(_beat_time + delta, beat_seconds)
	_trace.visible = _beat_time < beat_seconds * TRACE_ON_FRACTION


## Copies the director's heart and doctor levels onto the stream-less meter players.
func _mirror_levels() -> void:
	var heart := audio_director.ambience_level if audio_director.heart_monitor_active else 0.0
	_monitor_meter.volume_db = maxf(linear_to_db(heart), AudioLevels.SILENT_DB)
	var doctor := audio_director.voice_player(SoundBank.SPEAKER_DOCTOR)
	if doctor != null:
		_doctor_meter.volume_db = doctor.volume_db


func _flash_to_white() -> void:
	_flashing = true
	audio_director.set_voice_level(SoundBank.SPEAKER_DOCTOR, 0.0, volume_fade_seconds)
	audio_director.stop_voice(SoundBank.SPEAKER_DOCTOR)
	audio_director.duck_ambience(1.0, flash_seconds)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_light, "light_energy", light_flash_energy, flash_seconds)
	tween.tween_property(_orb, "scale", Vector3.ONE * FLASH_ORB_SCALE, flash_seconds)
	tween.tween_property(_flash, "color:a", 1.0, flash_seconds) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	_lines_seen += 1
	light_growth = clampf(float(_lines_seen) / float(maxi(_sequence.lines.size(), 1)), 0.0, 1.0)
	audio_director.set_voice_level(
		SoundBank.SPEAKER_DOCTOR, 1.0 - light_growth, volume_fade_seconds)
	if not god_has_spoken and DialogueSpeakers.is_god(line.speaker):
		god_has_spoken = true
		audio_director.duck_ambience(god_duck_amount, volume_fade_seconds)


func _on_dialogue_box_sequence_finished() -> void:
	_flash_to_white()
