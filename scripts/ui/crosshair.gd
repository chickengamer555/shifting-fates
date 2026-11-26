class_name Crosshair
extends Control
## The crosshair at the screen centre, where the grapple hooks fire, and the hooks' state
## drawn quietly round it. Everything is thin lines with a soft dark under-stroke so it reads
## over bright and dark scenes alike.
##
## [br]- Centre: four short ticks. While [member hookable] (what it points at would catch a
##   hook) they close in, warm up and gain a centre dot; otherwise they sit wider and dim.
## [br]- Ring: the left half belongs to the left hook, the right half to the right one. While
##   a hook is stuck its half fills, from the bottom, with the line it has left
##   ([member left_meter]); while it recharges the half fills as the recharge comes back.
## [br]- Hook icons: a small diamond either side of the ring, hollow when the hook is ready,
##   filled warm while it is stuck, dim with a growing core while it recharges.
## The [Hud] sets the fields every frame from the [GrappleAbility].

enum HookState { READY, ATTACHED, RECHARGING }

const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
## Gap (radians) left at the top and bottom of the ring between the two halves.
const RING_GAP := 0.42
const ARC_POINTS := 24
## Under-stroke drawn below every mark: extra width (px) and colour.
const UNDER_GROW := 2.0
## Line width (px) of the hook icons.
const ICON_LINE := 1.5

## True while the crosshair points at something a hook would stick to.
var hookable: bool = false:
	set(value):
		if hookable != value:
			hookable = value
			queue_redraw()
## [enum HookState] of the left and right hooks.
var left_state: int = HookState.READY:
	set(value):
		if left_state != value:
			left_state = value
			queue_redraw()
var right_state: int = HookState.READY:
	set(value):
		if right_state != value:
			right_state = value
			queue_redraw()
## Left and right meters (0..1): line left while stuck, recharge while recharging, 1 ready.
var left_meter: float = 1.0:
	set(value):
		if not is_equal_approx(left_meter, value):
			left_meter = value
			queue_redraw()
var right_meter: float = 1.0:
	set(value):
		if not is_equal_approx(right_meter, value):
			right_meter = value
			queue_redraw()

## Colour of marks that are live: a hookable centre, a stuck hook.
@export var live_color: Color = Color(1.0, 0.93, 0.78, 1.0)
## Colour of the plain centre and of ready hooks.
@export var idle_color: Color = Color(1.0, 1.0, 1.0, 0.8)
## Colour of a recharging hook's fill.
@export var recharge_color: Color = Color(0.62, 0.8, 1.0, 0.95)
## Colour of the ring's empty track.
@export var track_color: Color = Color(1.0, 1.0, 1.0, 0.26)
## Soft dark under-stroke.
@export var under_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export_group("Centre")
## Gap (px) between the centre and each tick, plain and hookable.
@export var gap: float = 6.0
@export var hookable_gap: float = 3.5
## Each tick's length and width (px).
@export var tick_length: float = 5.0
@export var tick_width: float = 2.0
## Radius (px) of the hookable centre dot.
@export var dot_radius: float = 1.6
@export_group("Ring")
## Radius and width (px) of the ring.
@export var ring_radius: float = 17.0
@export var ring_width: float = 2.0
## Distance (px) from the centre to each hook icon, and the icon's half size.
@export var icon_offset: float = 28.0
@export var icon_size: float = 4.0


func _draw() -> void:
	var centre := size * 0.5
	_draw_centre(centre)
	_draw_half(centre, -1.0, left_state, left_meter)
	_draw_half(centre, 1.0, right_state, right_meter)
	_draw_icon(centre + Vector2.LEFT * icon_offset, left_state, left_meter)
	_draw_icon(centre + Vector2.RIGHT * icon_offset, right_state, right_meter)


func _draw_centre(centre: Vector2) -> void:
	var paint := live_color if hookable else idle_color
	var inner := hookable_gap if hookable else gap
	for under: bool in [true, false]:
		var grow := UNDER_GROW * 0.5 if under else 0.0
		var colour := under_color if under else paint
		var width := tick_width + (UNDER_GROW if under else 0.0)
		for direction: Vector2 in DIRECTIONS:
			draw_line(centre + direction * (inner - grow),
					centre + direction * (inner + tick_length + grow), colour, width, true)
		if hookable:
			draw_circle(centre, dot_radius + grow, colour, true, -1.0, true)


## One half of the ring: [param side] -1 is the left half, 1 the right.
func _draw_half(centre: Vector2, side: float, state: int, meter: float) -> void:
	# Angles run clockwise on screen from +x (y points down): PI / 2 is straight down. Each
	# half runs from beside the bottom gap, round its side, to beside the top gap.
	var bottom := PI * 0.5 - RING_GAP * 0.5 * side
	var top := PI * 0.5 - (PI - RING_GAP * 0.5) * side
	_arc(centre, bottom, top, under_color, ring_width + UNDER_GROW)
	_arc(centre, bottom, top, track_color, ring_width)
	if state == HookState.READY:
		return
	var fill := clampf(meter, 0.0, 1.0)
	if fill <= 0.0:
		return
	var colour := live_color if state == HookState.ATTACHED else recharge_color
	_arc(centre, bottom, lerpf(bottom, top, fill), colour, ring_width)


func _draw_icon(at: Vector2, state: int, meter: float) -> void:
	var points := PackedVector2Array([
		at + Vector2.UP * icon_size, at + Vector2.RIGHT * icon_size,
		at + Vector2.DOWN * icon_size, at + Vector2.LEFT * icon_size,
		at + Vector2.UP * icon_size,
	])
	draw_polyline(points, under_color, ICON_LINE + UNDER_GROW, true)
	match state:
		HookState.ATTACHED:
			draw_colored_polygon(points.slice(0, 4), live_color)
			draw_polyline(points, live_color, ICON_LINE, true)
		HookState.RECHARGING:
			draw_polyline(points, track_color, ICON_LINE, true)
			var core := icon_size * clampf(meter, 0.0, 1.0)
			if core > 0.3:
				draw_colored_polygon(PackedVector2Array([
					at + Vector2.UP * core, at + Vector2.RIGHT * core,
					at + Vector2.DOWN * core, at + Vector2.LEFT * core]), recharge_color)
		_:
			draw_polyline(points, idle_color, ICON_LINE, true)


func _arc(centre: Vector2, from: float, to: float, colour: Color, width: float) -> void:
	var count := maxi(int(ceil(absf(to - from) / PI * ARC_POINTS)), 2)
	draw_arc(centre, ring_radius, from, to, count, colour, width, true)
