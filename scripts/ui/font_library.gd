class_name FontLibrary
extends RefCounted
## Where every UI font comes from: the combo score, the player, the gods and their glyph flashes.
##
## Two bundled families carry the whole interface: Cinzel (the gods' voice, titles and the
## menu) and Inter (the player's plain voice and every number on the HUD). The
## licensed fonts (The Jacatra, KR Lynda's Christian Dings) may not be redistributed, so they
## live in the git-ignored [constant DEFAULT_LOCAL_DIR] and are absent in a fresh clone. Each
## getter uses the local font when its file is there and quietly falls back to a bundled font
## otherwise (never an error). Nothing here preloads a local font.
## [br]Every getter takes the local font folder (any [code]res://[/code], [code]user://[/code] or
## absolute folder), so tests can point it at a missing or a temporary one.

const DEFAULT_LOCAL_DIR := "res://local_fonts"
## Metadata key on every font this library loads: the file path it was loaded from.
const META_SOURCE_PATH := &"font_library_source_path"

const JACATRA := "the_jacatra/THE_JACATRA.otf"
const CHRISTIAN_DINGS := "kr_lyndas_christian_dings/kr_lyndas_christian_dings.ttf"

## Bundled with the repo (see THIRD_PARTY.md).
const INTER := "res://third_party/fonts/inter/Inter-Variable.ttf"
const FONT_AWESOME := "res://third_party/fonts/fontawesome/fa-solid-900.ttf"
const CINZEL := "res://third_party/fonts/cinzel/Cinzel-Variable.ttf"
## Cinzel is a variable font; the gods use its semi-bold weight, which holds up over bright skies.
const GOD_WEIGHT := 600
## Weight of the combo rank's fallback (Cinzel) when The Jacatra is not installed.
const COMBO_FALLBACK_WEIGHT := 800
## Inter is variable too: the player's lines sit at a calm regular weight.
const PLAYER_WEIGHT := 420
const WEIGHT_AXIS := "wght"
## OpenType feature: tabular (equal-width) figures, so counting numbers never jitter.
const TABULAR_FIGURES := "tnum"

## System fonts tried for the gods' readable text if the bundled Cinzel file is missing.
const GOD_FALLBACK_FAMILIES: PackedStringArray = [
	"Cinzel", "Trajan Pro", "Times New Roman", "serif",
]

## Bundled fonts read straight from their files (not imported yet), so each is read once.
static var _bundled_files: Dictionary[String, Font] = {}


## The combo rank font: The Jacatra, else a heavy Cinzel. Words only: The Jacatra draws its
## "0" as the font author's logo, so never give it digits (see [method has_digits]).
static func combo_font(local_dir: String = DEFAULT_LOCAL_DIR) -> Font:
	var font := _local(local_dir, JACATRA)
	return font if font != null else title_font(COMBO_FALLBACK_WEIGHT)


## The player's voice: plain, readable Inter at a regular weight (theme font if missing).
## [param local_dir] is unused today; it is accepted so every getter is called the same way.
static func player_font(_local_dir: String = DEFAULT_LOCAL_DIR) -> Font:
	return ui_font(PLAYER_WEIGHT)


## Clean Inter at [param weight] (100..900) with tabular figures, for HUD numbers and small
## interface text. The theme's fallback font if the bundled file is missing.
static func ui_font(weight: int = PLAYER_WEIGHT) -> Font:
	var inter := _load(INTER)
	if inter == null:
		return ThemeDB.fallback_font
	var variation := _weighted(inter, weight)
	var server := TextServerManager.get_primary_interface()
	variation.opentype_features = {server.name_to_tag(TABULAR_FIGURES): 1}
	return _tagged(variation, INTER)


## Cinzel at [param weight] (400..900) for titles, menu wishes and HUD captions.
static func title_font(weight: int = GOD_WEIGHT) -> Font:
	var cinzel := _load(CINZEL)
	if cinzel == null:
		var fallback := SystemFont.new()
		fallback.font_names = GOD_FALLBACK_FAMILIES
		return fallback
	return _tagged(_weighted(cinzel, weight), CINZEL)


## True when [param text] holds a digit (it then must not be drawn in the combo font).
static func has_digits(text: String) -> bool:
	for character: String in text:
		if character >= "0" and character <= "9":
			return true
	return false


## The gods' readable font: the bundled Cinzel, else a serif system font. One font, so a
## god's line never jumps between typefaces (the glyph flashes are its only flicker).
## [param local_dir] is unused today; it is accepted so every getter is called the same way.
static func god_fonts(_local_dir: String = DEFAULT_LOCAL_DIR) -> Array[Font]:
	var fonts: Array[Font] = [title_font(GOD_WEIGHT)]
	return fonts


## Fonts a god line briefly flashes into: KR Lynda's Christian Dings (letters drawn as
## pictures) when present, and always the bundled Font Awesome religion icons.
static func god_glyph_fonts(local_dir: String = DEFAULT_LOCAL_DIR) -> Array[Font]:
	var fonts: Array[Font] = []
	var dings := _local(local_dir, CHRISTIAN_DINGS)
	if dings != null:
		fonts.append(dings)
	var icons := icon_font()
	if icons != null:
		fonts.append(icons)
	return fonts


## The bundled Font Awesome Solid icon font (null only if the bundled file is missing).
static func icon_font() -> Font:
	return _load(FONT_AWESOME)


## The file path [param font] was loaded from by this library; empty for other fonts.
static func source_path(font: Font) -> String:
	if font == null or not font.has_meta(META_SOURCE_PATH):
		return ""
	return String(font.get_meta(META_SOURCE_PATH))


## A local font: read straight from its file, so any folder works; an exported build (where
## only the imported copy exists) falls back to the imported resource.
static func _local(local_dir: String, file: String) -> Font:
	var path := local_dir.path_join(file)
	var font := _load_file(path)
	return font if font != null else _load_imported(path)


## A bundled font: the imported resource (shared through the resource cache), else the file
## (read once, then kept).
static func _load(path: String) -> Font:
	var font := _load_imported(path)
	if font != null:
		return font
	if not _bundled_files.has(path):
		font = _load_file(path)
		if font == null:
			return null
		_bundled_files[path] = font
	return _bundled_files[path]


## Null, silently, when [param path] is not an imported font.
static func _load_imported(path: String) -> Font:
	if not path.begins_with("res://") or not ResourceLoader.exists(path, "Font"):
		return null
	return _tagged(load(path) as Font, path)


## Null, silently, when there is no readable font file at [param path].
static func _load_file(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return null
	var font := FontFile.new()
	if font.load_dynamic_font(path) != OK:
		return null
	return _tagged(font, path)


## [param base] at [param weight] on its variable weight axis.
static func _weighted(base: Font, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	var axis := TextServerManager.get_primary_interface().name_to_tag(WEIGHT_AXIS)
	variation.variation_opentype = {axis: weight}
	return variation


static func _tagged(font: Font, path: String) -> Font:
	if font != null:
		font.set_meta(META_SOURCE_PATH, path)
	return font
