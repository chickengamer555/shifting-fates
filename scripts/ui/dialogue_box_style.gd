class_name DialogueBoxStyle
extends Resource
## How a [DialogueBox] looks for one kind of speaker: panel, overlay shader, colours and fonts.
##
## Fonts are plain [Font] slots, so a licensed font file can be dropped in later without code
## changes. With no fonts the box uses its theme's default font.

const DEFAULT_FONT_SIZE := 22
const DEFAULT_FONT_CYCLE_SECONDS := 0.6

## Reported by [member DialogueBox.active_style_id], e.g. [code]&"god"[/code].
@export var style_id: StringName = &""
## The box background. Null keeps the theme's PanelContainer panel.
@export var panel: StyleBox = null
## Drawn over the panel background (shimmer, grit). Null hides the overlay.
@export var overlay_material: Material = null
@export var name_color: Color = Color.WHITE
@export var text_color: Color = Color.WHITE
@export var font_size: int = DEFAULT_FONT_SIZE
## The first font is used normally; god speakers flash through all of them.
@export var fonts: Array[Font] = []
## Seconds each font stays on screen while a god talks.
@export var font_cycle_seconds: float = DEFAULT_FONT_CYCLE_SECONDS
