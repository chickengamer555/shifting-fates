class_name Crosshair
extends Control
## A small, quiet crosshair at the screen centre: four short ticks round a gap and a centre
## dot. The grapple hooks fire exactly where it points. Drawn in [member color] with a thin
## dark outline so it reads over bright and dark scenes alike.

## Colour of the ticks and dot.
@export var color: Color = Color(1.0, 0.97, 0.9, 0.85):
	set(value):
		color = value
		queue_redraw()
## Outline colour drawn under the ticks.
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.45)
## Gap (px) between the centre and each tick, and each tick's length and width.
@export var gap: float = 5.0
@export var tick_length: float = 6.0
@export var tick_width: float = 2.0
## Radius (px) of the centre dot.
@export var dot_radius: float = 1.5

const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


func _draw() -> void:
	var centre := size * 0.5
	for pass_index: int in 2:
		var outline := pass_index == 0
		var width := tick_width + (2.0 if outline else 0.0)
		var paint := outline_color if outline else color
		var grow := 1.0 if outline else 0.0
		for direction: Vector2 in DIRECTIONS:
			var from := centre + direction * (gap - grow)
			var to := centre + direction * (gap + tick_length + grow)
			draw_line(from, to, paint, width)
		draw_circle(centre, dot_radius + grow, paint)
