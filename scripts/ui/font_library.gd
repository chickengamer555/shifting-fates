class_name FontLibrary
extends RefCounted
## Where every UI font comes from: the combo score, the player, the gods and their glyph flashes.
##
## The fonts the design asks for (The Jacatra, EldergodsBB, KR Lynda's Christian Dings) may not
## be redistributed, so they live in the git-ignored [constant DEFAULT_LOCAL_DIR] and are
## absent in a fresh clone. Each getter uses the local font when its file is there and quietly
## falls back to a bundled font otherwise (never an error). Nothing here preloads a local font.
## [br]Every getter takes the local font folder (any [code]res://[/code], [code]user://[/code] or
## absolute folder), so tests can point it at a missing or a temporary one.

const DEFAULT_LOCAL_DIR := "res://local_fonts"
## Metadata key on every font this library loads: the file path it was loaded from.
const META_SOURCE_PATH := &"font_library_source_path"

const JACATRA := "the_jacatra/THE_JACATRA.otf"
const ELDERGODS := "eldergods_bb/ElderGodsBB.ttf"
const ELDERGODS_ITALIC := "eldergods_bb/ElderGodsBB_ital.ttf"
const CHRISTIAN_DINGS := "kr_lyndas_christian_dings/kr_lyndas_christian_dings.ttf"

## Bundled with the repo (see THIRD_PARTY.md).
const PERMANENT_MARKER := "res://third_party/fonts/permanent_marker/PermanentMarker-Regular.ttf"
const FONT_AWESOME := "res://third_party/fonts/fontawesome/fa-solid-900.ttf"

## System fonts tried for the gods' readable text when EldergodsBB is missing.
const GOD_FALLBACK_FAMILIES: PackedStringArray = [
	"Cinzel", "Trajan Pro", "Times New Roman", "serif",
]


## The combo multiplier and rank font: The Jacatra, else Permanent Marker.
static func combo_font(local_dir: String = DEFAULT_LOCAL_DIR) -> Font:
	var font := _local(local_dir, JACATRA)
	return font if font != null else player_font(local_dir)


## The player's rough skater font (dialogue, menu title and buttons): Permanent Marker.
## [param local_dir] is unused today; it is accepted so every getter is called the same way.
static func player_font(_local_dir: String = DEFAULT_LOCAL_DIR) -> Font:
	var font := _load(PERMANENT_MARKER)
	return font if font != null else ThemeDB.fallback_font


## The gods' readable fonts: EldergodsBB regular and italic, else a serif system font.
static func god_fonts(local_dir: String = DEFAULT_LOCAL_DIR) -> Array[Font]:
	var fonts: Array[Font] = []
	for file: String in [ELDERGODS, ELDERGODS_ITALIC]:
		var font := _local(local_dir, file)
		if font != null:
			fonts.append(font)
	if fonts.is_empty():
		var fallback := SystemFont.new()
		fallback.font_names = GOD_FALLBACK_FAMILIES
		fonts.append(fallback)
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


## A bundled font: the imported resource (shared through the resource cache), else the file.
static func _load(path: String) -> Font:
	var font := _load_imported(path)
	return font if font != null else _load_file(path)


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


static func _tagged(font: Font, path: String) -> Font:
	if font != null:
		font.set_meta(META_SOURCE_PATH, path)
	return font
