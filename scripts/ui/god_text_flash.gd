class_name GodTextFlash
extends RefCounted
## The flicker of a god's speech: readable fonts most of the time, glyph fonts in brief flashes.
##
## Time is split into flash cycles of [member flash_cycle_seconds]. For the last
## [member glyph_share] of each cycle the line flashes into one of [member glyph_fonts]
## (a different one each cycle); the rest of the time it shows [member readable_fonts], moving
## to the next every [member font_step_seconds]. During a flash, [method display_text] swaps
## the letters for religion icons when the glyph font has no letters (Font Awesome), and keeps
## the text when it maps letters to pictures itself (KR Lynda's Christian Dings). Spaces and
## length are kept, so a typewriter reveal still lines up.
## [br]State follows from the elapsed time alone, so a long frame never skips a return to text.

## Font Awesome 5 Solid religion icons (codepoints in its private use area).
const ICON_CROSS := 0xF654
const ICON_PRAYING_HANDS := 0xF684
const ICON_CHURCH := 0xF51D
const ICON_DOVE := 0xF4BA
const ICON_ANKH := 0xF644
const ICON_OM := 0xF679
const ICON_STAR_AND_CRESCENT := 0xF699
const ICON_STAR_OF_DAVID := 0xF69A
const ICON_PLACE_OF_WORSHIP := 0xF67F
const ICON_HAMSA := 0xF665
const ICON_BIBLE := 0xF647
const ICON_PRAY := 0xF683
const DEFAULT_ICONS: PackedInt32Array = [
	ICON_CROSS, ICON_PRAYING_HANDS, ICON_CHURCH, ICON_DOVE, ICON_ANKH, ICON_OM,
	ICON_STAR_AND_CRESCENT, ICON_STAR_OF_DAVID, ICON_PLACE_OF_WORSHIP, ICON_HAMSA,
	ICON_BIBLE, ICON_PRAY,
]
const DEFAULT_FLASH_CYCLE_SECONDS := 2.5
const DEFAULT_GLYPH_SHARE := 0.15
const DEFAULT_FONT_STEP_SECONDS := 0.6
## Letter probed to tell an icon font (no letters) from a letter-mapped dingbat font.
const LETTER_PROBE := "a"

## Readable fonts, cycled while not flashing. Empty keeps whatever font the label has.
var readable_fonts: Array[Font] = []
## Fonts flashed into, one per flash cycle. Empty turns the flashes off.
var glyph_fonts: Array[Font] = []
## Icons that replace letters in a glyph font without letters.
var icon_codepoints: PackedInt32Array = DEFAULT_ICONS
var flash_cycle_seconds: float = DEFAULT_FLASH_CYCLE_SECONDS
## Fraction (0 to 1) of every flash cycle spent showing glyphs.
var glyph_share: float = DEFAULT_GLYPH_SHARE
## Seconds each readable font stays before the next one.
var font_step_seconds: float = DEFAULT_FONT_STEP_SECONDS

var _elapsed: float = 0.0
var _readable_seconds: float = 0.0
var _glyph_seconds: float = 0.0


## Starts again from the first readable font (call at the start of each line).
func reset() -> void:
	_elapsed = 0.0
	_readable_seconds = 0.0
	_glyph_seconds = 0.0


## Moves the flash on by [param delta] seconds. Returns true if the font or the text mode
## changed, i.e. the label needs [method current_font] and [method display_text] again.
func advance(delta: float) -> bool:
	var font_before := current_font()
	var glyphs_before := is_showing_glyphs()
	_elapsed += delta
	if is_showing_glyphs():
		_glyph_seconds += delta
	else:
		_readable_seconds += delta
	return current_font() != font_before or is_showing_glyphs() != glyphs_before


## True during the glyph part of a flash cycle.
func is_showing_glyphs() -> bool:
	if glyph_fonts.is_empty() or glyph_share <= 0.0 or flash_cycle_seconds <= 0.0:
		return false
	var in_cycle := fmod(_elapsed, flash_cycle_seconds)
	return in_cycle >= flash_cycle_seconds * (1.0 - clampf(glyph_share, 0.0, 1.0))


## The font to draw with now; null when there is nothing to choose from.
func current_font() -> Font:
	if is_showing_glyphs():
		return glyph_fonts[_cycle_index() % glyph_fonts.size()]
	if readable_fonts.is_empty():
		return null
	if font_step_seconds <= 0.0:
		return readable_fonts[0]
	return readable_fonts[int(_elapsed / font_step_seconds) % readable_fonts.size()]


## [param text] as it should read now: unchanged unless flashing into a glyph font without
## letters, where every non-space character becomes an icon.
func display_text(text: String) -> String:
	if not is_showing_glyphs():
		return text
	return glyph_text(text, current_font(), icon_codepoints)


## Share of the time so far spent on readable text (1.0 before any time passed).
func readable_share() -> float:
	var total := _readable_seconds + _glyph_seconds
	return 1.0 if total <= 0.0 else _readable_seconds / total


## [param text] for [param font]: kept when the font has letters, otherwise each non-space
## character is swapped for one of [param icons], picked by the character so it is stable.
static func glyph_text(text: String, font: Font, icons: PackedInt32Array) -> String:
	if font == null or icons.is_empty() or font.has_char(LETTER_PROBE.unicode_at(0)):
		return text
	var shown := ""
	for index: int in text.length():
		var code := text.unicode_at(index)
		if char(code).strip_edges().is_empty():
			shown += char(code)
		else:
			shown += char(icons[code % icons.size()])
	return shown


func _cycle_index() -> int:
	return int(_elapsed / flash_cycle_seconds)
