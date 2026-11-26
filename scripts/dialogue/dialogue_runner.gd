class_name DialogueRunner
extends Node
## Plays a [DialogueSequence] with a typewriter reveal. Pure logic: it holds no UI, so a
## [DialogueBox] (or anything else) listens to its signals and reads [member visible_characters].
##
## [method advance] finishes the line being typed, or moves to the next line once it is shown.
## After the last line it emits [signal sequence_finished].

## A new line began; [member visible_characters] is back to 0.
signal line_started(line: DialogueLine)
## The current line is fully revealed (typed out or skipped).
signal line_completed(line: DialogueLine)
## A line carrying an event started.
signal event_triggered(event: StringName)
## The last line was advanced past, or an empty sequence was played.
signal sequence_finished

const DEFAULT_CHARACTERS_PER_SECOND := 40.0
const MIN_CHARACTERS_PER_SECOND := 1.0

## Reveal speed. Takes effect immediately, even mid-line.
@export var characters_per_second: float = DEFAULT_CHARACTERS_PER_SECOND:
	set(value):
		characters_per_second = maxf(value, MIN_CHARACTERS_PER_SECOND)

var sequence: DialogueSequence = null
## Index of the line on screen within [member sequence].
var line_index: int = 0
## How many characters of the current line are revealed.
var visible_characters: int = 0
var is_running: bool = false
var is_typing: bool = false
## The most recent event fired, for listeners that join late. Empty before any.
var last_event: StringName = &""

## Fractional characters carried between frames.
var _reveal_progress: float = 0.0


func _ready() -> void:
	set_meta("verify_unit", "DialogueRunner")


func _process(delta: float) -> void:
	if not is_typing:
		return
	_reveal_progress += delta * characters_per_second
	var total := current_line().text.length()
	visible_characters = mini(int(_reveal_progress), total)
	if visible_characters >= total:
		_complete_line()


## Starts [param new_sequence] from its first line, replacing anything playing.
func play(new_sequence: DialogueSequence) -> void:
	sequence = new_sequence
	is_running = true
	_show_line(0)


## Finishes the typing line, or goes to the next line. Does nothing when idle.
func advance() -> void:
	if not is_running:
		return
	if is_typing:
		visible_characters = current_line().text.length()
		_complete_line()
	else:
		_show_line(line_index + 1)


## Ends the sequence at once, as if the last line had been advanced past.
func stop() -> void:
	if is_running:
		_finish()


## The line on screen, or null when idle.
func current_line() -> DialogueLine:
	if not is_running or sequence == null or line_index >= sequence.lines.size():
		return null
	return sequence.lines[line_index]


func _show_line(index: int) -> void:
	line_index = index
	if sequence == null or index >= sequence.lines.size():
		_finish()
		return
	var line := sequence.lines[index]
	visible_characters = 0
	_reveal_progress = 0.0
	is_typing = true
	line_started.emit(line)
	if line.event != &"":
		last_event = line.event
		event_triggered.emit(line.event)
	if line.text.is_empty():
		_complete_line()


func _complete_line() -> void:
	is_typing = false
	line_completed.emit(current_line())


func _finish() -> void:
	is_running = false
	is_typing = false
	visible_characters = 0
	sequence_finished.emit()
