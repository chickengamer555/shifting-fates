class_name GrindMeter
extends Control
## The grind balance meter: a horizontal line with a mark at its middle and a bar that
## shows where the skater's balance is, from -1 (far left) to 1 (far right).
##
## The bar slides from the middle colour towards [member danger_color] as it nears an end.
## Set [member balance]; the meter redraws itself.

## How far the line is inset from the control's left and right edges (px).
@export var edge_inset: float = 8.0
## Thickness of the line (px).
@export var line_width: float = 4.0
## Height of the middle mark (px).
@export var middle_height: float = 18.0
## Width of the middle mark (px).
@export var middle_width: float = 3.0
## Size of the bar that shows the skater (px).
@export var marker_size: Vector2 = Vector2(10.0, 30.0)
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var middle_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var safe_color: Color = Color(0.4, 1.0, 0.6, 1.0)
@export var danger_color: Color = Color(1.0, 0.25, 0.2, 1.0)

## Balance -1..1; 0 is centred.
var balance: float = 0.0:
	set = set_balance


## Moves the bar to [param value] (clamped to -1..1).
func set_balance(value: float) -> void:
	balance = clampf(value, -1.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var centre_y := size.y * 0.5
	var left := edge_inset
	var right := size.x - edge_inset
	var middle_x := (left + right) * 0.5
	draw_line(Vector2(left, centre_y), Vector2(right, centre_y), line_color, line_width)
	var half_mark := middle_height * 0.5
	draw_line(Vector2(middle_x, centre_y - half_mark), Vector2(middle_x, centre_y + half_mark),
			middle_color, middle_width)
	var marker_x := middle_x + balance * (right - left) * 0.5
	var colour := safe_color.lerp(danger_color, absf(balance))
	draw_rect(Rect2(Vector2(marker_x, centre_y) - marker_size * 0.5, marker_size), colour)
