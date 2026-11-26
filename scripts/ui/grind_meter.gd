class_name GrindMeter
extends Control
## The grind balance meter: a thin arch of light right under the rider with a needle that
## runs along it as the balance shifts, from -1 (far left end) to 1 (far right end).
##
## Like the balance arcs of other skate games: small, close to the skater, readable at a
## glance. The [Hud] calls [method follow] each frame with the skater's position; the meter
## projects it through the active camera and sits [member below_feet] px under the feet.
## [br]- The arch is a hairline that fades out at both ends, with a slightly brighter safe
##   zone in the middle ([member safe_fraction]) and its outer ends tinted towards
##   [member danger_color] past [member danger_fraction].
## [br]- The needle is a small dot with a short radial tick and a soft glow. It eases after
##   [member balance] (no jitter), and its colour runs calm -> warm -> danger as it nears an
##   end; in the danger zone its glow pulses.
## [br]Set [member balance]; read [member needle_offset] for where the needle is drawn.

## Points the arch is drawn with.
const ARC_SEGMENTS := 48
## Where the meter goes when there is no camera to project through (fraction of screen).
const FALLBACK_ANCHOR := Vector2(0.5, 0.78)
## The meter is kept this far (px) inside the screen edges.
const SCREEN_MARGIN := 12.0

## Radius (px) of the circle the arch is part of: larger is flatter.
@export var arc_radius: float = 190.0
## Angle (degrees) the whole arch spans.
@export var arc_span_deg: float = 50.0
## Thickness (px) of the arch.
@export var line_width: float = 2.5
## Thickness (px) of the brighter safe zone.
@export var safe_width: float = 3.5
## |balance| inside which the rider is safe (the brighter middle of the arch).
@export var safe_fraction: float = 0.4
## |balance| past which the rider is about to fall (the ends tint, the needle turns red).
@export var danger_fraction: float = 0.75
## Radius (px) of the needle's dot and of its glow.
@export var needle_radius: float = 5.0
@export var glow_radius: float = 13.0
## How far (px) the needle's tick reaches inside and outside the arch.
@export var tick_inside: float = 11.0
@export var tick_outside: float = 4.0
## How far (px) under the rider's projected feet the meter's centre sits.
@export var below_feet: float = 34.0
## How quickly the meter follows the rider on screen and the needle follows the balance (1/s).
@export var follow_rate: float = 22.0
@export var needle_rate: float = 30.0
## Seconds to fade in when a grind starts.
@export var fade_seconds: float = 0.14
## How fast (rad/s) the glow pulses in the danger zone.
@export var pulse_speed: float = 13.0
@export var track_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export var shadow_color: Color = Color(0.04, 0.03, 0.06, 0.42)
@export var safe_color: Color = Color(1.0, 0.95, 0.86, 1.0)
@export var calm_color: Color = Color(1.0, 0.95, 0.86, 1.0)
@export var warm_color: Color = Color(1.0, 0.74, 0.38, 1.0)
@export var danger_color: Color = Color(1.0, 0.36, 0.3, 1.0)

## Balance -1..1; 0 is centred.
var balance: float = 0.0:
	set = set_balance
## The screen point (px) the meter was last placed under, e.g. the rider's feet.
var anchor: Vector2 = Vector2.ZERO
## Where the needle is drawn: px right (+) or left (-) of the arch's middle.
var needle_offset: float:
	get:
		return arc_radius * sin(_shown * _half_span())

## The balance the needle shows (eases after [member balance]).
var _shown: float = 0.0
var _fade: float = 0.0
var _clock: float = 0.0
var _placed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_placed = false
		_fade = 0.0
		_shown = balance


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	_shown = lerpf(_shown, balance, 1.0 - exp(-needle_rate * delta))
	_fade = minf(_fade + delta / maxf(fade_seconds, 0.001), 1.0)
	queue_redraw()


## Moves the needle to [param value] (clamped to -1..1).
func set_balance(value: float) -> void:
	balance = clampf(value, -1.0, 1.0)
	if not is_visible_in_tree():
		_shown = balance
	queue_redraw()


## Places the meter right under [param world_point] (the rider's feet) as the active camera
## sees it, kept on screen. Call it every frame while the meter shows.
func follow(world_point: Vector3) -> void:
	var screen := get_viewport_rect().size
	var point := screen * FALLBACK_ANCHOR
	var camera := get_viewport().get_camera_3d()
	if camera != null and not camera.is_position_behind(world_point):
		point = camera.unproject_position(world_point)
	anchor = point
	var target := point + Vector2(0.0, below_feet) - size * 0.5
	target.x = clampf(target.x, SCREEN_MARGIN, screen.x - SCREEN_MARGIN - size.x)
	target.y = clampf(target.y, SCREEN_MARGIN, screen.y - SCREEN_MARGIN - size.y)
	if not _placed:
		position = target
		_placed = true
	else:
		var delta := get_process_delta_time()
		position = position.lerp(target, 1.0 - exp(-follow_rate * delta))


## Colour of the needle at |balance| [param lean]: calm, warming past the safe zone, red in
## the danger zone.
func needle_color(lean: float) -> Color:
	var amount := absf(lean)
	if amount <= danger_fraction:
		return calm_color.lerp(warm_color, smoothstep(safe_fraction, danger_fraction, amount))
	return warm_color.lerp(danger_color, smoothstep(danger_fraction, 1.0, amount))


func _draw() -> void:
	var half := _half_span()
	var centre := Vector2(size.x * 0.5, size.y * 0.5 - _sag() * 0.5 + arc_radius)
	var track := PackedVector2Array()
	var track_colours := PackedColorArray()
	var shadow_colours := PackedColorArray()
	for index: int in ARC_SEGMENTS + 1:
		var t := float(index) / float(ARC_SEGMENTS) * 2.0 - 1.0
		track.append(_on_arc(centre, t * half, 0.0))
		var end_fade := 1.0 - pow(absf(t), 10.0)
		var tint := smoothstep(danger_fraction, 1.0, absf(t))
		var colour := track_color.lerp(Color(danger_color, 0.6), tint)
		track_colours.append(Color(colour, colour.a * end_fade * _fade))
		shadow_colours.append(Color(shadow_color, shadow_color.a * end_fade * _fade))
	draw_polyline_colors(track, shadow_colours, line_width + 3.5, true)
	draw_polyline_colors(track, track_colours, line_width, true)
	_draw_safe_zone(centre, half)
	_draw_ticks(centre, half)
	_draw_needle(centre, half)


func _draw_safe_zone(centre: Vector2, half: float) -> void:
	var zone := PackedVector2Array()
	var colours := PackedColorArray()
	var steps := maxi(roundi(ARC_SEGMENTS * safe_fraction), 2)
	for index: int in steps + 1:
		var t := float(index) / float(steps) * 2.0 - 1.0
		zone.append(_on_arc(centre, t * half * safe_fraction, 0.0))
		var soft := 1.0 - pow(absf(t), 6.0)
		colours.append(Color(safe_color, safe_color.a * soft * _fade))
	draw_polyline_colors(zone, colours, safe_width, true)


func _draw_ticks(centre: Vector2, half: float) -> void:
	var middle := Color(safe_color, 0.85 * _fade)
	draw_line(_on_arc(centre, 0.0, -5.0), _on_arc(centre, 0.0, 5.0), middle, 1.5, true)
	var end_colour := Color(danger_color, 0.8 * _fade)
	for side: float in [-1.0, 1.0]:
		var angle := side * half * danger_fraction
		draw_line(_on_arc(centre, angle, -4.0), _on_arc(centre, angle, 4.0), end_colour, 1.5,
				true)


func _draw_needle(centre: Vector2, half: float) -> void:
	var angle := _shown * half
	var colour := needle_color(_shown)
	var danger := smoothstep(danger_fraction, 1.0, absf(_shown))
	var pulse := 1.0 + 0.7 * danger * (0.5 + 0.5 * sin(_clock * pulse_speed))
	var tip := _on_arc(centre, angle, 0.0)
	draw_circle(tip, glow_radius, Color(colour, 0.1 * pulse * _fade), true, -1.0, true)
	draw_circle(tip, glow_radius * 0.55, Color(colour, 0.2 * pulse * _fade), true, -1.0, true)
	var outline := Color(shadow_color, shadow_color.a * _fade)
	var inner := _on_arc(centre, angle, -tick_inside)
	var outer := _on_arc(centre, angle, tick_outside)
	draw_line(inner, outer, outline, 4.0, true)
	draw_line(inner, outer, Color(colour, _fade), 2.0, true)
	draw_circle(tip, needle_radius + 1.5, outline, true, -1.0, true)
	draw_circle(tip, needle_radius, Color(colour, _fade), true, -1.0, true)


## Point on the arch at [param angle] (0 = top middle), [param lift] px outside it.
func _on_arc(centre: Vector2, angle: float, lift: float) -> Vector2:
	return centre + Vector2(sin(angle), -cos(angle)) * (arc_radius + lift)


func _half_span() -> float:
	return deg_to_rad(arc_span_deg) * 0.5


## How far (px) the arch's ends sit below its middle.
func _sag() -> float:
	return arc_radius * (1.0 - cos(_half_span()))
