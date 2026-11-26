class_name DialogueBox
extends Control
## On-screen dialogue at the top of the screen, with no box: the gods are balls of light
## ([GodOrb]s in the %Orbs row) and their words appear under them; the player answers in
## rough marker type off to one side ([code]you >  ...[/code]).
##
## Lines come from the %Runner. Gods use [member god_style]: their words fade in word by word,
## glow in their orb's colour and flicker with its light, and the readable font now and then
## flashes into glyphs (see [GodTextFlash]). The player uses [member player_style]; everyone
## else uses [member neutral_style]. A line's own [member DialogueLine.style] overrides this.
## A god joins the row the first time it speaks; scenes can also set presence themselves.
## Hidden until [method play]; hides again when the sequence ends.

## Re-emitted from the runner so parents only need to know about the box.
signal event_triggered(event: StringName)
## The last line of the sequence was dismissed and the box has closed.
signal sequence_finished
## A new line appeared on screen (re-emitted from the runner), e.g. to react to who speaks.
signal line_started(line: DialogueLine)
## A word of the current line began to appear; [param speaker] is the line's speaker.
signal word_revealed(speaker: StringName)

const STYLE_GOD := &"god"
const STYLE_PLAYER := &"player"
const STYLE_NEUTRAL := &"neutral"
## Input action that advances the dialogue (Enter / Space / gamepad A by default).
const ADVANCE_ACTION := &"ui_accept"
## Shown after the speaker's name in a speaker tag: [code]you >[/code].
const TAG_SUFFIX := " >"
## How much a god's text dims at the low point of its orb's breath (fraction).
const SHIMMER_DEPTH := 0.12
## Seconds for the top shade to fade in when the box opens.
const SHADE_FADE_SECONDS := 0.6

@export var god_style: DialogueBoxStyle = null
@export var player_style: DialogueBoxStyle = null
@export var neutral_style: DialogueBoxStyle = null
## Show the row of god orbs. A scene that draws its own god light (the opening) turns it off.
@export var orbs_visible: bool = true:
	set(value):
		orbs_visible = value
		if is_node_ready():
			_orbs.visible = value

## [member DialogueBoxStyle.style_id] of the style on screen; empty before any line.
var active_style_id: StringName = &""
## How many times the font has flashed to the next one since [method play].
var font_cycles: int = 0
## The god whose orb is talking now; empty while no god speaks.
var speaking_god: StringName:
	get:
		return _orbs.speaking_speaker
## File the line's current font was loaded from (see [method FontLibrary.source_path]).
var line_font_path: String:
	get:
		return FontLibrary.source_path(_text_label.font)

var _style: DialogueBoxStyle = null
var _flash := GodTextFlash.new()
var _flashing_fonts: bool = false
var _line_text: String = ""
var _speaker: StringName = &""

@onready var _runner: DialogueRunner = %Runner
@onready var _orbs: GodOrbRow = %Orbs
@onready var _shade: CanvasItem = %TopShade
@onready var _content: Control = %Content
@onready var _name_plate: Control = %NamePlate
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _text_label: DialogueText = %TextLabel


func _ready() -> void:
	set_meta("verify_unit", "DialogueBox")
	visible = false
	_orbs.visible = orbs_visible
	_runner.line_started.connect(_on_runner_line_started)
	_runner.line_completed.connect(_on_runner_line_completed)
	_runner.event_triggered.connect(_on_runner_event_triggered)
	_runner.sequence_finished.connect(_on_runner_sequence_finished)
	_text_label.word_revealed.connect(_on_text_label_word_revealed)


func _process(delta: float) -> void:
	if not _runner.is_running:
		return
	_text_label.visible_characters = _runner.visible_characters
	if _flashing_fonts:
		_tick_font_flash(delta)
		_shimmer_with_orb()


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
	if not visible:
		_shade.modulate.a = 0.0
		create_tween().tween_property(_shade, "modulate:a", 1.0, SHADE_FADE_SECONDS)
	visible = true
	_runner.play(sequence)


## Finishes the line being typed, or shows the next one.
func advance() -> void:
	_runner.advance()


## True while a sequence is playing.
func is_playing() -> bool:
	return _runner.is_running


## Fades [param god]'s orb to [param amount] (0 gone, 1 fully there), e.g. a distant god.
func set_god_presence(god: StringName, amount: float) -> void:
	_orbs.set_presence(god, amount)


## Extra brightness for [param god]'s orb (0 = none), e.g. while the gods flash.
func set_god_flare(god: StringName, amount: float) -> void:
	_orbs.set_flare(god, amount)


## Global centre of [param god]'s place in the orb row (even while the row is hidden).
func god_slot_center(god: StringName) -> Vector2:
	return _orbs.slot_center(god)


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
		_flash = GodTextFlash.new()
		return
	_runner.characters_per_second = style.characters_per_second
	_content.anchor_left = style.left
	_content.anchor_right = style.right
	_content.offset_left = 0.0
	_content.offset_right = 0.0
	_content.offset_top = style.drop
	_text_label.color = style.text_color
	_text_label.glow_color = _glow_for(style, speaker)
	_text_label.shade_color = style.shade_color
	_text_label.font_size = style.font_size
	_text_label.alignment = style.alignment
	_text_label.reveal = style.reveal
	_text_label.shimmer = 1.0
	_speaker_label.add_theme_color_override("font_color", style.tag_color)
	_speaker_label.add_theme_font_size_override("font_size", style.font_size)
	_flash.readable_fonts = style.resolved_fonts()
	_flash.glyph_fonts = style.resolved_glyph_fonts()
	_flash.font_step_seconds = style.font_cycle_seconds
	_flash.flash_cycle_seconds = style.flash_cycle_seconds
	_flash.glyph_share = style.glyph_share
	_flash.reset()
	_apply_font()


## A god's glow takes its orb's colour at the style's strength.
func _glow_for(style: DialogueBoxStyle, speaker: StringName) -> Color:
	var orbs := _orbs.orbs_for(speaker)
	if orbs.is_empty():
		return style.glow_color
	return Color(orbs[0].tint, style.glow_color.a)


## Shows the flash's current font, or its glyphs over the line during a flash.
func _apply_font() -> void:
	var readable := _flash.readable_fonts
	var readable_font: Font = null
	if _style != null and not readable.is_empty():
		readable_font = readable[0]
	if _flash.is_showing_glyphs():
		_text_label.show_glyphs(_flash.current_font(), _flash.display_text(_line_text))
	else:
		_text_label.clear_glyphs()
		var current := _flash.current_font() if _style != null else null
		readable_font = current if current != null else readable_font
		_text_label.font = readable_font
	if readable_font == null:
		_speaker_label.remove_theme_font_override("font")
	else:
		_speaker_label.add_theme_font_override("font", readable_font)


func _tick_font_flash(delta: float) -> void:
	if _style == null or not _flash.advance(delta):
		return
	font_cycles += 1
	_apply_font()


## A god's words breathe with its light; glyph flashes ghost at the style's glyph alpha.
func _shimmer_with_orb() -> void:
	var orbs := _orbs.orbs_for(_speaker)
	var breath := orbs[0].breath if not orbs.is_empty() else 0.0
	var shimmer := 1.0 - SHIMMER_DEPTH * (0.5 - 0.5 * breath)
	if _style != null and _flash.is_showing_glyphs():
		shimmer *= _style.glyph_alpha
	_text_label.shimmer = shimmer


func _on_runner_line_started(line: DialogueLine) -> void:
	_speaker = line.speaker
	_flashing_fonts = DialogueSpeakers.is_god(line.speaker)
	if _flashing_fonts:
		_orbs.ensure_present(line.speaker)
	_orbs.set_speaking(line.speaker if _flashing_fonts else &"")
	_line_text = line.text
	var style := _style_for(line)
	_apply_style(style, line.speaker)
	var speaker_name := DialogueSpeakers.display_name(line.speaker)
	var tagged := style != null and style.show_speaker_tag and not speaker_name.is_empty()
	_speaker_label.text = speaker_name.to_lower() + TAG_SUFFIX if tagged else ""
	_name_plate.visible = tagged
	_text_label.visible_characters = 0
	_text_label.text = _line_text
	line_started.emit(line)


func _on_runner_line_completed(line: DialogueLine) -> void:
	_text_label.visible_characters = line.text.length()
	_orbs.set_speaking(&"")


func _on_runner_event_triggered(event: StringName) -> void:
	event_triggered.emit(event)


func _on_runner_sequence_finished() -> void:
	visible = false
	_flashing_fonts = false
	_orbs.set_speaking(&"")
	sequence_finished.emit()


func _on_text_label_word_revealed(_index: int) -> void:
	if DialogueSpeakers.is_god(_speaker):
		_orbs.pulse_speaking()
	word_revealed.emit(_speaker)
