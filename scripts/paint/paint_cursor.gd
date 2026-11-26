class_name PaintCursor
extends Control
## The brush under the mouse while painting: a thin ring exactly as wide as the paint it
## leaves, with a dot of the paint colour in its middle. The fill tool shows a small cross.
## Purely visual, it never takes the mouse.

const RING_WIDTH := 1.5
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.9)
## A darker ring just outside the white one keeps the outline readable on light paint.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const SHADOW_WIDTH := 3.0
const SEGMENTS := 48
const DOT_RADIUS := 2.5
const CROSS_ARM := 7.0
const MIN_RADIUS := 2.0

## Ring radius in pixels.
var radius: float = 10.0
## Ring centre in this control's coordinates.
var at: Vector2 = Vector2.ZERO
## Colour of the centre dot.
var tint: Color = Color.WHITE
## Show a cross (fill tool) instead of the ring.
var cross: bool = false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## Shows the cursor at [param position_px] with a ring of [param radius_px].
func show_at(position_px: Vector2, radius_px: float, color: Color, as_cross: bool) -> void:
	at = position_px
	radius = maxf(radius_px, MIN_RADIUS)
	tint = color
	cross = as_cross
	visible = true
	queue_redraw()


func _draw() -> void:
	if cross:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(at - axis * CROSS_ARM, at + axis * CROSS_ARM, SHADOW_COLOR, SHADOW_WIDTH, true)
			draw_line(at - axis * CROSS_ARM, at + axis * CROSS_ARM, RING_COLOR, RING_WIDTH, true)
		draw_circle(at, DOT_RADIUS, tint, true, -1.0, true)
		return
	draw_arc(at, radius + RING_WIDTH, 0.0, TAU, SEGMENTS, SHADOW_COLOR, SHADOW_WIDTH, true)
	draw_arc(at, radius, 0.0, TAU, SEGMENTS, RING_COLOR, RING_WIDTH, true)
	draw_circle(at, DOT_RADIUS, tint, true, -1.0, true)
