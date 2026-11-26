class_name DialogueBoxStyle
extends Resource
## How a [DialogueBox] shows one kind of speaker's line: font, colours, glow, placement and
## reveal. There is no panel: lines are drawn straight over the game.
##
## Fonts are plain [Font] slots. When [member fonts] is empty, [member font_set] picks them from
## [FontLibrary] instead (the licensed local fonts when present, bundled ones otherwise); with
## neither the box uses its theme's default font. God styles can also flash into glyph fonts
## (see [GodTextFlash]).

## Where the fonts come from when [member fonts] is empty.
enum FontSet {
	THEME, ## The theme's default font.
	PLAYER, ## [method FontLibrary.player_font].
	GOD, ## [method FontLibrary.god_fonts].
}

const DEFAULT_FONT_SIZE := 26
const DEFAULT_FONT_CYCLE_SECONDS := 0.6
const DEFAULT_CHARACTERS_PER_SECOND := 40.0

## Reported by [member DialogueBox.active_style_id], e.g. [code]&"god"[/code].
@export var style_id: StringName = &""
@export var text_color: Color = Color.WHITE
## Glow around the letters; alpha is its strength. Gods tint it with their orb's colour.
@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.0)
## Soft dark halo behind the text so it reads over bright skies; alpha is its strength.
@export var shade_color: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var font_size: int = DEFAULT_FONT_SIZE
@export var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
@export var reveal: DialogueText.Reveal = DialogueText.Reveal.FADE_WORDS
## Typewriter speed for these lines.
@export var characters_per_second: float = DEFAULT_CHARACTERS_PER_SECOND
## Show the speaker tag (e.g. [code]you >[/code]) before the line.
@export var show_speaker_tag: bool = false
@export var tag_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export_group("Placement")
## Left and right edges of the line, as fractions of the screen width.
@export_range(0.0, 1.0) var left: float = 0.2
@export_range(0.0, 1.0) var right: float = 0.8
## Extra space (px) between the orb row and the line.
@export var drop: float = 0.0
@export_group("Fonts")
## The first font is used normally; god speakers flash through all of them.
@export var fonts: Array[Font] = []
## Used when [member fonts] is empty.
@export var font_set: FontSet = FontSet.THEME
## Seconds each font stays on screen while a god talks.
@export var font_cycle_seconds: float = DEFAULT_FONT_CYCLE_SECONDS
@export_group("Glyph flash")
## While a god talks, briefly flash the line into [method FontLibrary.god_glyph_fonts]
## (religion icons, Christian dings) and back.
@export var glyph_flash: bool = false
## Seconds from one glyph flash to the next.
@export_range(0.1, 30.0, 0.1, "suffix:s") var flash_cycle_seconds: float = \
		GodTextFlash.DEFAULT_FLASH_CYCLE_SECONDS
## Fraction of the time spent on glyphs; the rest is readable text.
@export_range(0.0, 1.0, 0.01) var glyph_share: float = GodTextFlash.DEFAULT_GLYPH_SHARE
## How opaque the glyphs are while they flash (they ghost over the line, never shout).
@export_range(0.0, 1.0, 0.01) var glyph_alpha: float = 0.7

## Library fonts, looked up once per style (they may be read straight from a font file).
var _library_fonts: Array[Font] = []
var _library_glyph_fonts: Array[Font] = []
var _library_looked_up: bool = false


## The readable fonts to use: [member fonts], else those of [member font_set].
func resolved_fonts() -> Array[Font]:
	if not fonts.is_empty():
		return fonts
	_look_up_library()
	return _library_fonts


## The fonts a flash shows; empty unless [member glyph_flash] is on.
func resolved_glyph_fonts() -> Array[Font]:
	if not glyph_flash:
		var none: Array[Font] = []
		return none
	_look_up_library()
	return _library_glyph_fonts


func _look_up_library() -> void:
	if _library_looked_up:
		return
	_library_looked_up = true
	match font_set:
		FontSet.PLAYER:
			_library_fonts.append(FontLibrary.player_font())
		FontSet.GOD:
			_library_fonts = FontLibrary.god_fonts()
	_library_glyph_fonts = FontLibrary.god_glyph_fonts()
