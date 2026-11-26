class_name TrickCatalog
extends RefCounted
## The trick table: which air trick an input performs, and what tricks and grabs score.
##
## Four families, all in the air (see docs/CONTROLS.md):
## [br]- Flips, [code]trick[/code] (Q) + a direction: W front flip, S back flip, A kickflip,
##   D heelflip, and the diagonals combine a body flip with a board flip (W + A is a
##   Front Kickflip). One-off [method base_points] each.
## [br]- Board tricks, [code]board_trick[/code] (E) + an optional direction: the board spins
##   flat under the rider (Pop Shove-it, 360 Shove-it) or spins and flips (Varial Kickflip,
##   360 Flip, Hardflip...). One-off points.
## [br]- Spins: turning in the air (Q + mouse, or A/D) is scored on landing by how far round
##   it went: [method spin_for_degrees] gives Frontside / Backside 180, 360, 540...
## [br]- Grabs, [code]grab_left[/code] (Ctrl, front hand) / [code]grab_right[/code] (Alt,
##   back hand) + an optional direction: Melon, Nosegrab, Indy, Stalefish... Points per
##   second held ([method grab_points_per_second]).
## Static only: call the lookups directly, never instantiate.

## Which hand grabs the board: LEFT is the front hand (Ctrl), RIGHT the back hand (Alt).
enum GrabSide { LEFT, RIGHT }

## Inputs shorter than this are not a direction (no trick).
const INPUT_DEADZONE := 0.3
## A direction counts as diagonal (a combined trick) when both axes are at least this.
const DIAGONAL_MIN := 0.5
## Returned when no trick or grab applies.
const NO_TRICK := &""
## Spins under this many degrees short of a half turn still count as that half turn.
const SPIN_TOLERANCE_DEG := 45.0
## Flip tricks (Q) by direction key: forward, back, left, right and the diagonals.
const DIRECTION_TRICKS := {
	&"forward": &"front_flip",
	&"back": &"back_flip",
	&"left": &"kickflip",
	&"right": &"heelflip",
	&"forward_left": &"front_kickflip",
	&"forward_right": &"front_heelflip",
	&"back_left": &"back_kickflip",
	&"back_right": &"back_heelflip",
}
## Board tricks (E) by direction key; &"none" is E alone.
const BOARD_TRICKS := {
	&"none": &"pop_shove_it",
	&"forward": &"shove_it_360",
	&"back": &"fs_shove_it",
	&"left": &"varial_kickflip",
	&"right": &"varial_heelflip",
	&"forward_left": &"tre_flip",
	&"forward_right": &"laser_flip",
	&"back_left": &"hardflip",
	&"back_right": &"inward_heelflip",
}
## Grab tricks by [enum GrabSide], then direction key (&"none" is the grab key alone).
const GRABS := {
	GrabSide.LEFT: {
		&"none": &"melon_grab",
		&"forward": &"nosegrab",
		&"back": &"method_grab",
		&"left": &"mute_grab",
		&"right": &"seatbelt_grab",
	},
	GrabSide.RIGHT: {
		&"none": &"indy_grab",
		&"forward": &"crail_grab",
		&"back": &"tailgrab",
		&"left": &"stalefish_grab",
		&"right": &"roast_beef_grab",
	},
}
## Grab for each side with no direction (kept for callers that only know the hand).
const SIDE_GRABS := {
	GrabSide.LEFT: &"melon_grab",
	GrabSide.RIGHT: &"indy_grab",
}
## Spin trick ids by half turns (1 = 180) for frontside (index 0) and backside (index 1).
const SPIN_HALF_TURNS_MAX := 6
## Every trick and grab: display name, one-off points, points per second held, and
## "time": the trick's length as a share of [member Skater.trick_duration].
const TRICKS := {
	&"front_flip": {"name": "Front Flip", "points": 500, "time": 1.0},
	&"back_flip": {"name": "Back Flip", "points": 500, "time": 1.0},
	&"kickflip": {"name": "Kickflip", "points": 300, "time": 0.85},
	&"heelflip": {"name": "Heelflip", "points": 300, "time": 0.85},
	&"front_kickflip": {"name": "Front Kickflip", "points": 900, "time": 1.0},
	&"front_heelflip": {"name": "Front Heelflip", "points": 900, "time": 1.0},
	&"back_kickflip": {"name": "Back Kickflip", "points": 900, "time": 1.0},
	&"back_heelflip": {"name": "Back Heelflip", "points": 900, "time": 1.0},
	&"pop_shove_it": {"name": "Pop Shove-it", "points": 250, "time": 0.7},
	&"fs_shove_it": {"name": "Frontside Shove-it", "points": 250, "time": 0.7},
	&"shove_it_360": {"name": "360 Shove-it", "points": 450, "time": 0.9},
	&"varial_kickflip": {"name": "Varial Kickflip", "points": 500, "time": 0.85},
	&"varial_heelflip": {"name": "Varial Heelflip", "points": 500, "time": 0.85},
	&"tre_flip": {"name": "360 Flip", "points": 800, "time": 0.95},
	&"laser_flip": {"name": "Laser Flip", "points": 850, "time": 0.95},
	&"hardflip": {"name": "Hardflip", "points": 650, "time": 0.85},
	&"inward_heelflip": {"name": "Inward Heelflip", "points": 650, "time": 0.85},
	&"melon_grab": {"name": "Melon Grab", "points_per_second": 150.0},
	&"indy_grab": {"name": "Indy Grab", "points_per_second": 150.0},
	&"nosegrab": {"name": "Nosegrab", "points_per_second": 170.0},
	&"tailgrab": {"name": "Tailgrab", "points_per_second": 170.0},
	&"method_grab": {"name": "Method", "points_per_second": 210.0},
	&"mute_grab": {"name": "Mute Grab", "points_per_second": 160.0},
	&"seatbelt_grab": {"name": "Seatbelt", "points_per_second": 220.0},
	&"crail_grab": {"name": "Crail Grab", "points_per_second": 220.0},
	&"stalefish_grab": {"name": "Stalefish", "points_per_second": 200.0},
	&"roast_beef_grab": {"name": "Roast Beef", "points_per_second": 190.0},
	&"fs_180": {"name": "Frontside 180", "points": 200},
	&"bs_180": {"name": "Backside 180", "points": 200},
	&"fs_360": {"name": "Frontside 360", "points": 450},
	&"bs_360": {"name": "Backside 360", "points": 450},
	&"fs_540": {"name": "Frontside 540", "points": 750},
	&"bs_540": {"name": "Backside 540", "points": 750},
	&"fs_720": {"name": "Frontside 720", "points": 1100},
	&"bs_720": {"name": "Backside 720", "points": 1100},
	&"fs_900": {"name": "Frontside 900", "points": 1500},
	&"bs_900": {"name": "Backside 900", "points": 1500},
	&"fs_1080": {"name": "Frontside 1080", "points": 2000},
	&"bs_1080": {"name": "Backside 1080", "points": 2000},
}


## Flip trick for a stick direction, or [constant NO_TRICK] inside the deadzone.
## [param input] follows [method Input.get_vector] with (left, right, forward, back):
## negative y is forward. A strong diagonal (both axes at least [constant DIAGONAL_MIN],
## e.g. two keys) is a combined trick; otherwise the dominant axis wins and an exact tie
## goes to the flip axis.
static func trick_for_input(input: Vector2) -> StringName:
	var key := direction_key(input)
	return DIRECTION_TRICKS.get(key, NO_TRICK)


## Board trick (E) for a direction; no direction is the Pop Shove-it.
static func board_trick_for_input(input: Vector2) -> StringName:
	var key := direction_key(input)
	return BOARD_TRICKS.get(&"none" if key == NO_TRICK else key, NO_TRICK)


## Grab for a hand and an optional direction (only the dominant axis counts).
static func grab_for(side: GrabSide, input: Vector2) -> StringName:
	var table: Dictionary = GRABS.get(side, {})
	var key := &"none"
	if input.length() >= INPUT_DEADZONE:
		if absf(input.y) >= absf(input.x):
			key = &"forward" if input.y < 0.0 else &"back"
		else:
			key = &"left" if input.x < 0.0 else &"right"
	return table.get(key, NO_TRICK)


## Grab for a hand with no direction, or [constant NO_TRICK] for an unknown side.
static func grab_for_side(side: GrabSide) -> StringName:
	return SIDE_GRABS.get(side, NO_TRICK)


## Spin trick for a turn of [param degrees] in the air (positive = frontside), or
## [constant NO_TRICK] under a half turn. A spin up to [constant SPIN_TOLERANCE_DEG] short
## of the next half turn counts as it.
static func spin_for_degrees(degrees: float) -> StringName:
	var halves := mini(floori((absf(degrees) + SPIN_TOLERANCE_DEG) / 180.0),
		SPIN_HALF_TURNS_MAX)
	if halves < 1:
		return NO_TRICK
	return StringName("%s_%d" % ["fs" if degrees > 0.0 else "bs", halves * 180])


## Direction name for an input: forward, back, left, right, forward_left... or
## [constant NO_TRICK] inside the deadzone.
static func direction_key(input: Vector2) -> StringName:
	if input.length() < INPUT_DEADZONE:
		return NO_TRICK
	var vertical := &"forward" if input.y < 0.0 else &"back"
	var sideways := &"left" if input.x < 0.0 else &"right"
	if absf(input.x) >= DIAGONAL_MIN and absf(input.y) >= DIAGONAL_MIN:
		return StringName("%s_%s" % [vertical, sideways])
	if absf(input.y) >= absf(input.x):
		return vertical
	return sideways


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


## Length of [param id] as a share of the skater's base trick duration (1.0 if unknown).
static func time_scale(id: StringName) -> float:
	return float(_entry(id).get("time", 1.0))


## True for the ids a [code]board_trick[/code] (E) press does.
static func is_board_trick(id: StringName) -> bool:
	return BOARD_TRICKS.values().has(id)


static func _entry(id: StringName) -> Dictionary:
	return TRICKS.get(id, {})
