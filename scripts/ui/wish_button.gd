class_name WishButton
extends Button
## A menu choice drawn as text only, in the gods' Cinzel: no box. Hovered or focused, it
## brightens, a thin line of light draws itself under the words and a small light (like a
## tiny god orb) appears before them. Disabled wishes fade back.
##
## Colours come from the theme's [code]Button[/code] font colours; the light is drawn here.

## Cinzel weight and letter spacing (px) of the wish text.
const WEIGHT := 500
const LETTER_SPACING := 1
## Durations are clamped to at least this, so a zero setting never divides by zero.
const MIN_SECONDS := 0.001

## Seconds the light takes to draw in or fade out.
@export var ease_seconds: float = 0.22
@export var light_color: Color = Color(1.0, 0.96, 0.86, 1.0)
## Thickness of the underline (px) and its gap below the text (px).
@export var line_width: float = 1.0
@export var line_gap: float = 3.0
## Radius (px) of the small light before the words, and its distance to their left.
@export var dot_radius: float = 2.5
@export var dot_offset: float = 16.0

## 0 at rest, 1 fully lit (hovered or focused); eased.
var lit: float = 0.0
var _hovered: bool = false


func _ready() -> void:
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	var font := FontLibrary.title_font(WEIGHT)
	if font is FontVariation:
		(font as FontVariation).spacing_glyph = LETTER_SPACING
	add_theme_font_override("font", font)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_animate)
	focus_exited.connect(_animate)
	set_process(false)


func _process(delta: float) -> void:
	var step := delta / maxf(ease_seconds, MIN_SECONDS)
	lit = move_toward(lit, _target(), step)
	queue_redraw()
	if is_equal_approx(lit, _target()):
		set_process(false)


func _draw() -> void:
	if lit <= 0.0:
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var style := get_theme_stylebox("normal")
	var left := style.get_margin(SIDE_LEFT)
	var eased := ease(lit, -2.0)
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var line_y := baseline + line_gap
	var line_end := left + text_width * eased
	var glow := Color(light_color, 0.07 * eased)
	draw_line(Vector2(left, line_y), Vector2(line_end, line_y), glow, line_width + 3.0, true)
	var fade := PackedColorArray([Color(light_color, 0.85 * eased), Color(light_color, 0.0)])
	draw_polyline_colors(PackedVector2Array([Vector2(left, line_y), Vector2(line_end, line_y)]),
		fade, line_width, true)
	var dot := Vector2(left - dot_offset, size.y * 0.5)
	draw_circle(dot, dot_radius * 3.0, Color(light_color, 0.08 * eased))
	draw_circle(dot, dot_radius * 1.8, Color(light_color, 0.18 * eased))
	draw_circle(dot, dot_radius, Color(light_color, 0.95 * eased))


func _target() -> float:
	if disabled:
		return 0.0
	return 1.0 if _hovered or has_focus() else 0.0


## Eases [member lit] towards the hover / focus state over the next frames.
func _animate() -> void:
	set_process(true)


func _on_mouse_entered() -> void:
	_hovered = true
	_animate()


func _on_mouse_exited() -> void:
	_hovered = false
	_animate()
