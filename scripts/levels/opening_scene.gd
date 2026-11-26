class_name OpeningScene
extends Node3D
## The opening: the player wakes in a hospital bed under a bright, pulsing light while God
## speaks to them (dialogue [code]opening[/code]).
##
## The heart monitor's trace blinks with every beat. The first time God speaks the beep is
## tweened down to [member quiet_beep_db]. Each line brightens the light a little and fades
## the doctor's voice by the same amount. When the dialogue ends the light expands into a
## white flash and [signal finished] is emitted for the game flow.
## [br]Audio players ship without streams; sound is filled in later and every call here is
## safe without one.

## The white flash is complete: move on to the intro.
signal finished

const DIALOGUE_ID := &"opening"
## Treated as silence when fading a player out (dB).
const SILENT_DB := -60.0
## The trace stays lit for this part of each beat.
const TRACE_ON_FRACTION := 0.25
## How much bigger the light's glowing orb grows during the flash.
const FLASH_ORB_SCALE := 6.0

## Seconds for the light to expand into the white flash.
@export var flash_seconds: float = 2.0
## Seconds for the beep and doctor volume changes.
@export var volume_fade_seconds: float = 1.5
## Seconds between heartbeats.
@export var beat_seconds: float = 0.9
## Beep volume once God has spoken (dB).
@export var quiet_beep_db: float = -18.0
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
@export var monitor_beep: AudioStreamPlayer = null
@export var doctor_voice: AudioStreamPlayer = null

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


func _ready() -> void:
	set_meta("verify_unit", "Opening")
	_flash.color.a = 0.0
	_light.light_energy = light_start_energy
	_dialogue_box.line_started.connect(_on_dialogue_box_line_started)
	_dialogue_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
	_play(doctor_voice)
	_sequence = DialogueLibrary.load_directory().get(DIALOGUE_ID) as DialogueSequence
	if _sequence == null:
		push_error("OpeningScene: dialogue '%s' is missing" % DIALOGUE_ID)
		return
	_dialogue_box.play(_sequence)


func _process(delta: float) -> void:
	_time += delta
	_tick_heartbeat(delta)
	if not _flashing:
		var energy := lerpf(light_start_energy, light_end_energy, light_growth)
		var wobble := 1.0 + light_wobble * sin(TAU * light_wobble_hz * _time)
		_light.light_energy = energy * wobble


func _tick_heartbeat(delta: float) -> void:
	_beat_time += delta
	if _beat_time >= beat_seconds:
		_beat_time = fmod(_beat_time, beat_seconds)
		_play(monitor_beep)
	_trace.visible = _beat_time < beat_seconds * TRACE_ON_FRACTION


func _fade_volume(player: AudioStreamPlayer, volume_db: float) -> void:
	if player == null:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", volume_db, volume_fade_seconds)


func _flash_to_white() -> void:
	_flashing = true
	_fade_volume(monitor_beep, SILENT_DB)
	_fade_volume(doctor_voice, SILENT_DB)
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


static func _play(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	_lines_seen += 1
	light_growth = clampf(float(_lines_seen) / float(maxi(_sequence.lines.size(), 1)), 0.0, 1.0)
	_fade_volume(doctor_voice, linear_to_db(maxf(1.0 - light_growth, db_to_linear(SILENT_DB))))
	if not god_has_spoken and DialogueSpeakers.is_god(line.speaker):
		god_has_spoken = true
		_fade_volume(monitor_beep, quiet_beep_db)


func _on_dialogue_box_sequence_finished() -> void:
	_flash_to_white()
