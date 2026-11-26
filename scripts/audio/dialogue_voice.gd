class_name DialogueVoice
extends Node
## Gives the gods a voice while they speak: binds to a [DialogueBox] and drives the sustained
## god voice of the [code]AudioDirector[/code].
##
## The first line by any god ([method DialogueSpeakers.is_god]) starts the voice; following
## god lines keep it going (it is started once, not per line, and holds its loop). A line by
## anyone else ends it with its outro, as does the end of the sequence.

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")

## Where the voice plays. Null at ready means the [code]AudioDirector[/code] autoload; tests
## inject a fresh instance.
var director: AUDIO_DIRECTOR = null
## True while the god voice has been started and not yet stopped.
var god_voice_active: bool = false
## Times the god voice has been started (once per run of consecutive god lines).
var voice_starts: int = 0

var _box: DialogueBox = null


func _ready() -> void:
	set_meta("verify_unit", "DialogueVoice")
	if director == null:
		director = AudioDirector


## Follows [param box]'s lines from now on, letting go of any box bound before.
func bind(box: DialogueBox) -> void:
	if _box != null:
		_box.line_started.disconnect(_on_dialogue_box_line_started)
		_box.sequence_finished.disconnect(_on_dialogue_box_sequence_finished)
	_box = box
	if _box != null:
		_box.line_started.connect(_on_dialogue_box_line_started)
		_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)


func _start_god_voice() -> void:
	if god_voice_active:
		return
	god_voice_active = true
	voice_starts += 1
	director.start_voice(SoundBank.SPEAKER_GOD)


func _stop_god_voice() -> void:
	if not god_voice_active:
		return
	god_voice_active = false
	director.stop_voice(SoundBank.SPEAKER_GOD)


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	if DialogueSpeakers.is_god(line.speaker):
		_start_god_voice()
	else:
		_stop_god_voice()


func _on_dialogue_box_sequence_finished() -> void:
	_stop_god_voice()
