class_name PaintChoiceButton
extends Button
## A choice on the paint panel drawn the way the menu's wishes are: no box, just its text or
## icon. The chosen one (pressed) glows in the gods' warm light with a short line of light
## under it; hovering lights it halfway.

## Seconds the light takes to come or go.
const EASE_SECONDS := 0.16
const MIN_SECONDS := 0.001
## Line of light under the choice: thickness, gap below the content, share of the width.
const LINE_WIDTH := 1.0
const LINE_GAP := 2.0
const LINE_SHARE := 0.6
## How far inside its box an outlined choice's frame is drawn.
const OUTLINE_INSET := 1.5

@export var light_color: Color = Color(1.0, 0.96, 0.86, 1.0)
## Draws a faint frame of light round the choice, so a one-off action (not one of a set of
## choices) reads as a button.
@export var outlined: bool = false

## 0 unlit, 0.5 hovered, 1 chosen; eased.
var lit: float = 0.0

var _hovered: bool = false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func _process(delta: float) -> void:
	var target := 1.0 if button_pressed else (0.5 if _hovered and not disabled else 0.0)
	if is_equal_approx(lit, target):
		return
	lit = move_toward(lit, target, delta / maxf(EASE_SECONDS, MIN_SECONDS))
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	if outlined:
		draw_rect(box.grow(-OUTLINE_INSET), Color(light_color, 0.28 + 0.4 * lit), false,
				LINE_WIDTH)
	if lit <= 0.0:
		return
	draw_rect(box, Color(light_color, 0.06 * lit))
	var half := size.x * LINE_SHARE * 0.5
	var y := size.y - LINE_GAP
	var middle := size.x * 0.5
	var fade := PackedColorArray([Color(light_color, 0.0), Color(light_color, 0.9 * lit),
		Color(light_color, 0.0)])
	draw_polyline_colors(PackedVector2Array([Vector2(middle - half, y), Vector2(middle, y),
		Vector2(middle + half, y)]), fade, LINE_WIDTH, true)
