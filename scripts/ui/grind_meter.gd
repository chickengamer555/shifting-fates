class_name GrindMeter
extends Control
## The grind balance meter: a thin line of light with a tick at its middle and a glowing
## marker that shows where the skater's balance is, from -1 (far left) to 1 (far right).
##
## Styled like the HUD's top strip: hairline track fading out at both ends, a slim marker.
## The marker slides from [member safe_color] towards [member danger_color] as it nears an
## end. Set [member balance]; the meter redraws itself.

## Segments the track is drawn in, so its ends can fade out.
const TRACK_SEGMENTS := 24

## How far the line is inset from the control's left and right edges (px).
@export var edge_inset: float = 8.0
## Thickness of the line (px).
@export var line_width: float = 2.0
## Height of the middle mark (px).
@export var middle_height: float = 10.0
## Width of the middle mark (px).
@export var middle_width: float = 1.5
## Size of the bar that shows the skater (px).
@export var marker_size: Vector2 = Vector2(4.0, 20.0)
## Extra size (px, each side) of the soft glow around the marker.
@export var glow_size: float = 4.0
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export var middle_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var safe_color: Color = Color(1.0, 0.95, 0.85, 1.0)
@export var danger_color: Color = Color(1.0, 0.36, 0.3, 1.0)

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
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	for index: int in TRACK_SEGMENTS + 1:
		var t := float(index) / float(TRACK_SEGMENTS)
		points.append(Vector2(lerpf(left, right, t), centre_y))
		var edge_fade := 1.0 - pow(absf(t * 2.0 - 1.0), 3.0)
		colours.append(Color(line_color, line_color.a * edge_fade))
	draw_polyline_colors(points, colours, line_width, true)
	var half_mark := middle_height * 0.5
	draw_line(Vector2(middle_x, centre_y - half_mark), Vector2(middle_x, centre_y + half_mark),
			middle_color, middle_width, true)
	var marker_x := middle_x + balance * (right - left) * 0.5
	var colour := safe_color.lerp(danger_color, absf(balance))
	var glow := Rect2(Vector2(marker_x, centre_y) - marker_size * 0.5, marker_size) \
			.grow(glow_size)
	draw_rect(glow, Color(colour, 0.18))
	draw_rect(Rect2(Vector2(marker_x, centre_y) - marker_size * 0.5, marker_size), colour)
