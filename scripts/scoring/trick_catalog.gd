class_name TrickCatalog
extends RefCounted
## The trick table: which air trick a direction performs, and what tricks and grabs score.
##
## Holding [code]trick[/code] (Q) plus a direction does a flip trick worth
## [method base_points] once. Holding a grab ([code]grab_left[/code] /
## [code]grab_right[/code]) earns [method grab_points_per_second] while held.
## Static only: call the lookups directly, never instantiate.

## Which hand grabs the board.
enum GrabSide { LEFT, RIGHT }

## Inputs shorter than this are not a direction (no trick).
const INPUT_DEADZONE := 0.3
## Returned when no trick or grab applies.
const NO_TRICK := &""
## Flip tricks by direction. Keys: forward, back, left, right.
const DIRECTION_TRICKS := {
	&"forward": &"front_flip",
	&"back": &"back_flip",
	&"left": &"kickflip",
	&"right": &"heelflip",
}
## Grab tricks by [enum GrabSide].
const SIDE_GRABS := {
	GrabSide.LEFT: &"melon_grab",
	GrabSide.RIGHT: &"indy_grab",
}
## Every trick and grab: display name, one-off points and points per second held.
const TRICKS := {
	&"front_flip": {"name": "Front Flip", "points": 500, "points_per_second": 0.0},
	&"back_flip": {"name": "Back Flip", "points": 500, "points_per_second": 0.0},
	&"kickflip": {"name": "Kickflip", "points": 300, "points_per_second": 0.0},
	&"heelflip": {"name": "Heelflip", "points": 300, "points_per_second": 0.0},
	&"melon_grab": {"name": "Melon Grab", "points": 0, "points_per_second": 150.0},
	&"indy_grab": {"name": "Indy Grab", "points": 0, "points_per_second": 150.0},
}


## Trick for a stick direction, or [constant NO_TRICK] inside the deadzone.
## [param input] follows [method Input.get_vector] with (left, right, forward, back):
## negative y is forward. The dominant axis wins; an exact tie goes to the flip axis.
static func trick_for_input(input: Vector2) -> StringName:
	if input.length() < INPUT_DEADZONE:
		return NO_TRICK
	var direction: StringName
	if absf(input.y) >= absf(input.x):
		direction = &"forward" if input.y < 0.0 else &"back"
	else:
		direction = &"left" if input.x < 0.0 else &"right"
	return DIRECTION_TRICKS[direction]


## Grab for a hand, or [constant NO_TRICK] for an unknown side.
static func grab_for_side(side: GrabSide) -> StringName:
	return SIDE_GRABS.get(side, NO_TRICK)


## True if [param id] is in the catalog.
static func has_trick(id: StringName) -> bool:
	return TRICKS.has(id)


## Player-facing name, or "" for an unknown id.
static func display_name(id: StringName) -> String:
	return str(_entry(id).get("name", ""))


## One-off points for landing [param id] in a combo; 0 for grabs and unknown ids.
static func base_points(id: StringName) -> int:
	return int(_entry(id).get("points", 0))


## Points earned per second while [param id] is held; 0 for flips and unknown ids.
static func grab_points_per_second(id: StringName) -> float:
	return float(_entry(id).get("points_per_second", 0.0))


static func _entry(id: StringName) -> Dictionary:
	return TRICKS.get(id, {})
