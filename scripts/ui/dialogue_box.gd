class_name DialogueBox
extends Control
## On-screen dialogue: shows the speaker and the typewriter text of its [DialogueRunner].
##
## Gods use [member god_style] (gold with a white light sweep) and flash through that style's
## fonts while they talk; the player uses [member player_style] (rough skater look); everyone
## else uses [member neutral_style]. A line's own [member DialogueLine.style] overrides this.
## Hidden until [method play]; hides again when the sequence ends.

## Re-emitted from the runner so parents only need to know about the box.
signal event_triggered(event: StringName)
## The last line of the sequence was dismissed and the box has closed.
signal sequence_finished
## A new line appeared on screen (re-emitted from the runner), e.g. to react to who speaks.
signal line_started(line: DialogueLine)

const STYLE_GOD := &"god"
const STYLE_PLAYER := &"player"
const STYLE_NEUTRAL := &"neutral"
## Input action that advances the dialogue (Enter / Space / gamepad A by default).
const ADVANCE_ACTION := &"ui_accept"

@export var god_style: DialogueBoxStyle = null
@export var player_style: DialogueBoxStyle = null
@export var neutral_style: DialogueBoxStyle = null
## Name label colour per speaker, applied over the style's colour (e.g. the red god in red).
@export var speaker_name_colors: Dictionary[StringName, Color] = {}

## [member DialogueBoxStyle.style_id] of the style on screen; empty before any line.
var active_style_id: StringName = &""
## How many times the font has flashed to the next one since [method play].
var font_cycles: int = 0

var _style: DialogueBoxStyle = null
var _font_index: int = 0
var _font_timer: float = 0.0
var _flashing_fonts: bool = false

@onready var _runner: DialogueRunner = %Runner
@onready var _panel: PanelContainer = %Panel
@onready var _overlay: ColorRect = %Overlay
@onready var _name_plate: Control = %NamePlate
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _text_label: Label = %TextLabel


func _ready() -> void:
	set_meta("verify_unit", "DialogueBox")
	visible = false
	_runner.line_started.connect(_on_runner_line_started)
	_runner.line_completed.connect(_on_runner_line_completed)
	_runner.event_triggered.connect(_on_runner_event_triggered)
	_runner.sequence_finished.connect(_on_runner_sequence_finished)


func _process(delta: float) -> void:
	if not _runner.is_running:
		return
	_text_label.visible_characters = _runner.visible_characters
	if _flashing_fonts:
		_tick_font_flash(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _runner.is_running:
		return
	var clicked := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if clicked or event.is_action_pressed(ADVANCE_ACTION):
		advance()
		get_viewport().set_input_as_handled()


## Shows the box and plays [param sequence] from its first line.
func play(sequence: DialogueSequence) -> void:
	font_cycles = 0
	visible = true
	_runner.play(sequence)


## Finishes the line being typed, or shows the next one.
func advance() -> void:
	_runner.advance()


## True while a sequence is playing.
func is_playing() -> bool:
	return _runner.is_running


func _style_for(line: DialogueLine) -> DialogueBoxStyle:
	var wanted := line.style
	if wanted == &"":
		if DialogueSpeakers.is_god(line.speaker):
			wanted = STYLE_GOD
		elif line.speaker == DialogueSpeakers.PLAYER:
			wanted = STYLE_PLAYER
	match wanted:
		STYLE_GOD:
			return god_style
		STYLE_PLAYER:
			return player_style
	return neutral_style


func _apply_style(style: DialogueBoxStyle, speaker: StringName) -> void:
	_style = style
	active_style_id = style.style_id if style != null else &""
	if style == null:
		return
	if style.panel != null:
		_panel.add_theme_stylebox_override("panel", style.panel)
	else:
		_panel.remove_theme_stylebox_override("panel")
	_overlay.material = style.overlay_material
	_overlay.visible = style.overlay_material != null
	_speaker_label.add_theme_color_override(
		"font_color", speaker_name_colors.get(speaker, style.name_color))
	_text_label.add_theme_color_override("font_color", style.text_color)
	for label: Label in [_speaker_label, _text_label]:
		label.add_theme_font_size_override("font_size", style.font_size)
	_font_index = 0
	_font_timer = 0.0
	_apply_font()


func _apply_font() -> void:
	for label: Label in [_speaker_label, _text_label]:
		if _style == null or _style.fonts.is_empty():
			label.remove_theme_font_override("font")
		else:
			label.add_theme_font_override("font", _style.fonts[_font_index])


func _tick_font_flash(delta: float) -> void:
	if _style == null or _style.fonts.is_empty() or _style.font_cycle_seconds <= 0.0:
		return
	_font_timer += delta
	if _font_timer < _style.font_cycle_seconds:
		return
	_font_timer -= _style.font_cycle_seconds
	_font_index = (_font_index + 1) % _style.fonts.size()
	font_cycles += 1
	_apply_font()


func _on_runner_line_started(line: DialogueLine) -> void:
	_flashing_fonts = DialogueSpeakers.is_god(line.speaker)
	_apply_style(_style_for(line), line.speaker)
	var speaker_name := DialogueSpeakers.display_name(line.speaker)
	_speaker_label.text = speaker_name
	_name_plate.visible = not speaker_name.is_empty()
	_text_label.text = line.text
	_text_label.visible_characters = 0
	line_started.emit(line)


func _on_runner_line_completed(line: DialogueLine) -> void:
	_text_label.visible_characters = line.text.length()


func _on_runner_event_triggered(event: StringName) -> void:
	event_triggered.emit(event)


func _on_runner_sequence_finished() -> void:
	visible = false
	_flashing_fonts = false
	sequence_finished.emit()
