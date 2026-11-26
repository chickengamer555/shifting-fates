class_name DialogueText
extends Control
## A dialogue line drawn straight onto the screen, with no box behind it.
##
## [member text] is wrapped to the control's width and revealed up to
## [member visible_characters] (set by the [DialogueBox] from its runner). With
## [constant Reveal.FADE_WORDS] each word fades in (and drifts up a little) as the reveal
## reaches it; with [constant Reveal.TYPE_CHARACTERS] letters simply appear. A soft dark halo
## keeps the text readable over bright skies, and a coloured glow sits over it.
## [br][method show_glyphs] briefly draws another text in another font in the same place
## (the god glyph flashes) while [member text] stays the readable line.

## A word became visible (its fade started). [param index] counts words from 0.
signal word_revealed(index: int)

enum Reveal {
	FADE_WORDS, ## Words fade in one by one.
	TYPE_CHARACTERS, ## Letters appear one by one.
}

const DEFAULT_FONT_SIZE := 26
const WORD_SEPARATOR := " "
## Dark halo under the text: outline sizes (px) and the share of the halo alpha each gets.
const SHADE_OUTLINES: PackedInt32Array = [16, 10, 5]
const SHADE_SHARES: PackedFloat32Array = [0.2, 0.3, 0.55]
## Coloured glow over the halo: outline sizes and alpha shares.
const GLOW_OUTLINES: PackedInt32Array = [9, 4]
const GLOW_SHARES: PackedFloat32Array = [0.35, 0.6]

## The readable line. Setting it starts the reveal again.
@export_multiline var text: String = "":
	set(value):
		text = value
		_restart()
## Characters revealed; -1 shows them all.
@export var visible_characters: int = -1:
	set(value):
		visible_characters = value
		_reveal_words()
@export var font: Font = null:
	set(value):
		font = value
		_relayout()
@export var font_size: int = DEFAULT_FONT_SIZE:
	set(value):
		font_size = value
		_relayout()
@export var color: Color = Color.WHITE
## Glow drawn around the letters; alpha sets its strength (0 = none).
@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.0)
## Dark halo behind everything for contrast; alpha sets its strength (0 = none).
@export var shade_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER:
	set(value):
		alignment = value
		queue_redraw()
@export var reveal: Reveal = Reveal.FADE_WORDS
## Seconds a word takes to fade in.
@export var fade_seconds: float = 0.45
## How far (px) a word drifts up while it fades in.
@export var rise_pixels: float = 5.0
## Extra space between wrapped lines (px).
@export var line_spacing: float = 4.0
## Overall alpha, e.g. to flicker the text with a god's light (1 = steady).
@export_range(0.0, 1.0) var shimmer: float = 1.0:
	set(value):
		shimmer = value
		queue_redraw()

## Seconds since the line started; word fades are timed against it.
var _time: float = 0.0
## Start index in [member text] of every word.
var _word_starts: PackedInt32Array = []
## [member _time] at which each word was revealed; negative while hidden.
var _shown_at: PackedFloat32Array = []
## The wrapped layout: one entry per line, each an Array of [word index, x offset].
var _lines: Array[Array] = []
var _line_widths: PackedFloat32Array = []
var _glyph_font: Font = null
var _glyph_text: String = ""


func _ready() -> void:
	resized.connect(_relayout)
	_restart()


func _process(delta: float) -> void:
	_time += delta
	if _is_fading():
		queue_redraw()


func _get_minimum_size() -> Vector2:
	if _active_font() == null:
		return Vector2.ZERO
	return Vector2(0.0, maxf(1.0, float(_lines.size())) * _line_height())


func _draw() -> void:
	var draw_font := _active_font()
	if draw_font == null:
		return
	var words := _shown_text().split(WORD_SEPARATOR)
	var ascent := _readable_font().get_ascent(font_size)
	for line_index: int in _lines.size():
		var start_x := _line_start_x(_line_widths[line_index])
		var baseline := float(line_index) * _line_height() + ascent
		for entry: Array in _lines[line_index]:
			var word_index: int = entry[0]
			var shown := _visible_part(words, word_index)
			var alpha := _word_alpha(word_index) * shimmer
			if shown.is_empty() or alpha <= 0.0:
				continue
			var rise := rise_pixels * (1.0 - _word_alpha(word_index))
			_draw_word(draw_font, Vector2(start_x + float(entry[1]), baseline + rise), shown, alpha)


## Draws [param glyphs] in [param glyph_font] instead of [member text] until
## [method clear_glyphs]. Same length as the text, so the reveal still lines up.
func show_glyphs(glyph_font: Font, glyphs: String) -> void:
	_glyph_font = glyph_font
	_glyph_text = glyphs
	_relayout()


## Back to drawing [member text] in [member font].
func clear_glyphs() -> void:
	if _glyph_font == null and _glyph_text.is_empty():
		return
	_glyph_font = null
	_glyph_text = ""
	_relayout()


## True while words are still fading in.
func is_revealing() -> bool:
	return _is_fading()


func _restart() -> void:
	_time = 0.0
	_word_starts = PackedInt32Array()
	var index := 0
	for word: String in text.split(WORD_SEPARATOR):
		_word_starts.append(index)
		index += word.length() + WORD_SEPARATOR.length()
	_shown_at = PackedFloat32Array()
	_shown_at.resize(_word_starts.size())
	_shown_at.fill(-1.0)
	_relayout()
	_reveal_words()


func _reveal_words() -> void:
	var limit := text.length() if visible_characters < 0 else visible_characters
	for index: int in _word_starts.size():
		if _shown_at[index] < 0.0 and _word_starts[index] < limit:
			_shown_at[index] = _time
			word_revealed.emit(index)
	queue_redraw()


func _relayout() -> void:
	var lines_before := _lines.size()
	_lines.clear()
	_line_widths = PackedFloat32Array()
	var draw_font := _active_font()
	if draw_font != null:
		_wrap(draw_font, _shown_text().split(WORD_SEPARATOR))
	if _lines.size() != lines_before:
		update_minimum_size()
	queue_redraw()


## Greedy word wrap to the control's width (no wrap while it has no width yet).
func _wrap(draw_font: Font, words: PackedStringArray) -> void:
	var space := _width_of(draw_font, WORD_SEPARATOR)
	var line: Array = []
	var x := 0.0
	for index: int in words.size():
		var width := _width_of(draw_font, words[index])
		if not line.is_empty() and size.x > 0.0 and x + space + width > size.x:
			_lines.append(line)
			_line_widths.append(x)
			line = []
			x = 0.0
		if not line.is_empty():
			x += space
		line.append([index, x])
		x += width
	_lines.append(line)
	_line_widths.append(x)


func _draw_word(draw_font: Font, pos: Vector2, word: String, alpha: float) -> void:
	for layer: int in SHADE_OUTLINES.size():
		var shade := Color(shade_color, shade_color.a * SHADE_SHARES[layer] * alpha)
		if shade.a > 0.0:
			draw_font.draw_string_outline(get_canvas_item(), pos, word, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size, SHADE_OUTLINES[layer], shade)
	for layer: int in GLOW_OUTLINES.size():
		var glow := Color(glow_color, glow_color.a * GLOW_SHARES[layer] * alpha)
		if glow.a > 0.0:
			draw_font.draw_string_outline(get_canvas_item(), pos, word, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size, GLOW_OUTLINES[layer], glow)
	draw_font.draw_string(get_canvas_item(), pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, Color(color, color.a * alpha))


## The part of word [param index] to draw: all of it when fading words, else the typed part.
func _visible_part(words: PackedStringArray, index: int) -> String:
	if index >= words.size() or index >= _word_starts.size():
		return ""
	var word := words[index]
	if reveal == Reveal.FADE_WORDS or visible_characters < 0:
		return word
	return word.left(clampi(visible_characters - _word_starts[index], 0, word.length()))


func _word_alpha(index: int) -> float:
	if index >= _shown_at.size() or _shown_at[index] < 0.0:
		return 0.0
	if reveal == Reveal.TYPE_CHARACTERS or fade_seconds <= 0.0:
		return 1.0
	return smoothstep(0.0, fade_seconds, _time - _shown_at[index])


func _is_fading() -> bool:
	if reveal == Reveal.TYPE_CHARACTERS:
		return false
	for shown_at: float in _shown_at:
		if shown_at >= 0.0 and _time - shown_at < fade_seconds:
			return true
	return false


func _line_start_x(line_width: float) -> float:
	match alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return (size.x - line_width) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - line_width
	return 0.0


## Lines keep the readable font's height during glyph flashes, so nothing jumps.
func _line_height() -> float:
	var readable := _readable_font()
	return readable.get_height(font_size) + line_spacing if readable != null else 0.0


func _active_font() -> Font:
	return _glyph_font if _glyph_font != null else _readable_font()


func _readable_font() -> Font:
	return font if font != null else get_theme_default_font()


func _shown_text() -> String:
	return _glyph_text if not _glyph_text.is_empty() else text


func _width_of(draw_font: Font, part: String) -> float:
	return draw_font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
