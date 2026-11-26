class_name DialogueVoice
extends Node
## Gives the gods a voice while they speak: binds to a [DialogueBox] and drives the sustained
## god voice of the [code]AudioDirector[/code].
##
## The voice sounds only while a god's words are being revealed. The first line by any god
## ([method DialogueSpeakers.is_god]) starts it; once that line is fully revealed (waiting for
## input) it fades out over [constant REVEALED_FADE_SECONDS] and then stops. A god line that
## starts before the fade is over picks the voice back up in its loop, so consecutive god lines
## sound like one held voice (started once). A line by anyone else ends it with its outro,
## faded the same way, as does the end of the sequence or leaving the tree.
## [br]"Fully revealed" is the box's [code]line_revealed[/code] signal when it has one, else the
## box's own %Runner [signal DialogueRunner.line_completed].

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
## Seconds the voice takes to fade once a line is fully revealed or the voice is stopped.
const REVEALED_FADE_SECONDS := 0.35
## Seconds to come back to full level when a god line starts during a fade.
const RESUME_FADE_SECONDS := 0.08
## The box signal for "line fully revealed", used when the box offers it.
const REVEALED_SIGNAL := &"line_revealed"

## Where the voice plays. Null at ready means the [code]AudioDirector[/code] autoload; tests
## inject a fresh instance.
var director: AUDIO_DIRECTOR = null
## True while the god voice has been started and not yet stopped.
var god_voice_active: bool = false
## Times the god voice has been started (once per run of consecutive god lines).
var voice_starts: int = 0

var _box: DialogueBox = null
var _revealed_source: Object = null
## Bumped on every start or stop, so a stale fade timer knows it was overtaken.
var _fade_serial: int = 0


func _ready() -> void:
	set_meta("verify_unit", "DialogueVoice")
	if director == null:
		director = AudioDirector


## A freed screen takes its voice with it, so a god line never drones on behind the next one.
func _exit_tree() -> void:
	_stop_god_voice()


## Follows [param box]'s lines from now on, letting go of any box bound before.
func bind(box: DialogueBox) -> void:
	if _box != null:
		_box.line_started.disconnect(_on_dialogue_box_line_started)
		_box.sequence_finished.disconnect(_on_dialogue_box_sequence_finished)
	if _revealed_source != null:
		_revealed_signal(_revealed_source).disconnect(_on_line_revealed)
	_box = box
	_revealed_source = null
	if _box != null:
		_box.line_started.connect(_on_dialogue_box_line_started)
		_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
		if _box.has_signal(REVEALED_SIGNAL):
			_revealed_source = _box
		else:
			_revealed_source = _box.get_node_or_null(^"%Runner") as DialogueRunner
		if _revealed_source != null:
			_revealed_signal(_revealed_source).connect(_on_line_revealed)
		else:
			push_warning("DialogueVoice: the box has no reveal-finished signal")


static func _revealed_signal(source: Object) -> Signal:
	if source is DialogueRunner:
		return (source as DialogueRunner).line_completed
	return Signal(source, REVEALED_SIGNAL)


func _start_god_voice() -> void:
	_fade_serial += 1
	if god_voice_active:
		director.set_voice_level(SoundBank.SPEAKER_GOD, 1.0, RESUME_FADE_SECONDS)
		return
	god_voice_active = true
	voice_starts += 1
	director.set_voice_level(SoundBank.SPEAKER_GOD, 1.0)
	director.start_voice(SoundBank.SPEAKER_GOD)


func _stop_god_voice() -> void:
	if not god_voice_active:
		return
	_fade_serial += 1
	god_voice_active = false
	director.stop_voice(SoundBank.SPEAKER_GOD)
	director.set_voice_level(SoundBank.SPEAKER_GOD, 0.0, REVEALED_FADE_SECONDS)


## The god line is fully revealed and waits for input: fade the voice, then stop it unless
## another god line starts first.
func _fade_out_god_voice() -> void:
	if not god_voice_active:
		return
	_fade_serial += 1
	director.set_voice_level(SoundBank.SPEAKER_GOD, 0.0, REVEALED_FADE_SECONDS)
	if not is_inside_tree():
		_stop_god_voice()
		return
	get_tree().create_timer(REVEALED_FADE_SECONDS).timeout.connect(
		_on_fade_timer_timeout.bind(_fade_serial))


func _on_fade_timer_timeout(serial: int) -> void:
	if serial == _fade_serial:
		_stop_god_voice()


func _on_line_revealed(_line: DialogueLine) -> void:
	_fade_out_god_voice()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	if DialogueSpeakers.is_god(line.speaker):
		_start_god_voice()
	else:
		_stop_god_voice()


func _on_dialogue_box_sequence_finished() -> void:
	_stop_god_voice()
