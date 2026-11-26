class_name GrappleRope
extends RefCounted
## Rules for one grapple hook's line, with no nodes so it can be tested on its own.
##
## Once a hook is attached its line can pay out: each [method tick] told to pay out grows it
## by [member payout_speed] m/s (the owner decides when; the [GrappleAbility] pays out while
## the skater holds the button on the ground and keeps the length in the air). The line is
## never longer than [method too_long_at]: past [member max_length], or, for a hook that
## stuck further than that away (shooting has no reach limit), past [member max_slack]
## beyond the length it stuck at. Reaching it, the hook lets go ([signal detached]) when
## [member lets_go_when_too_long] is on; otherwise the line simply stops growing. While the
## owner reels the body in, [method wind_in] takes up the slack so the line ends up shorter,
## never below [member min_length].
##
## The line is a rope, not a rod: [method constrain_velocity] only stops the body moving
## further than [member length] from the anchor; moving towards the anchor is free. It
## works on velocity alone (no teleporting), so a CharacterBody3D still collides normally.
## [method swing_velocity] is the same constraint for a swing that keeps its momentum: while
## the line stays taut (within [member taut_tolerance]) from one step to the next, the speed
## the constraint would take away is turned along the swing instead, as a frictionless
## pendulum does. Without it a line paying out under load would brake a swing like a winch.
## [method sling_velocity] is the swing the [GrappleAbility] uses: the same hard constraint
## (the body never ends a step past the line's length) with the speed set by energy
## conservation over the step, so a swing neither bleeds nor invents speed, and a line
## snapping taut turns the fall along the swing instead of stopping it dead.

## Emitted once when the line grows too long and the hook lets go (see
## [member lets_go_when_too_long]).
signal detached

## Below this sideways speed (m/s) a swing has no direction to keep its speed along.
const SIDEWAYS_EPSILON := 0.001

## How fast (m/s) the line pays out while paying out.
var payout_speed: float = 2.5
## Longest line (m) for a hook that stuck closer than this.
var max_length: float = 25.0
## Line (m) a hook that stuck further away than [member max_length] may pay out beyond its
## attach length.
var max_slack: float = 4.0
## The line is never shorter than this (m).
var min_length: float = 1.5
## A line within this (m) of its length counts as taut for [method swing_velocity].
var taut_tolerance: float = 0.3
## True: a line paid out past [method too_long_at] lets go. False: it stops growing there.
var lets_go_when_too_long: bool = true

## World point the hook is stuck to.
var anchor: Vector3 = Vector3.ZERO
## Current line length (m).
var length: float = 0.0
## True while the hook is stuck to something.
var attached: bool = false
## Line length (m) when the hook stuck.
var attach_length: float:
	get:
		return _attach_length

var _attach_length: float = 0.0
var _was_taut: bool = false


## Sticks the hook at [param anchor_point] with the line just reaching [param from_position].
func attach(anchor_point: Vector3, from_position: Vector3) -> void:
	anchor = anchor_point
	length = maxf(anchor_point.distance_to(from_position), min_length)
	_attach_length = length
	attached = true
	_was_taut = true


## Lets go of the anchor (no signal; the caller chose to release).
func release() -> void:
	attached = false


## Longest the line may grow (m) before the hook lets go: [member max_length], or the
## attach length plus [member max_slack] when that is longer.
func too_long_at() -> float:
	return maxf(max_length, _attach_length + max_slack)


## Line (m) still to pay out before the hook lets go.
func line_left() -> float:
	return maxf(too_long_at() - length, 0.0)


## [method line_left] over the line the hook had to spare when it stuck (0..1).
func line_left_fraction() -> float:
	var spare := too_long_at() - _attach_length
	if spare <= 0.0:
		return 0.0
	return clampf(line_left() / spare, 0.0, 1.0)


## Pays the line out by [member payout_speed] m/s while [param paying_out]; at
## [method too_long_at] the hook lets go or the line stops growing (see
## [member lets_go_when_too_long]).
func tick(delta: float, paying_out: bool) -> void:
	if not attached or not paying_out:
		return
	length += payout_speed * delta
	if length <= too_long_at():
		return
	if lets_go_when_too_long:
		attached = false
		detached.emit()
	else:
		length = too_long_at()


## Takes up slack: the line shortens to the distance to [param from_position] (never
## below min_length, never longer than it already is).
func wind_in(from_position: Vector3) -> void:
	if not attached:
		return
	length = clampf(distance_from(from_position), min_length, length)


## Distance (m) from [param point] to the anchor.
func distance_from(point: Vector3) -> float:
	return anchor.distance_to(point)


## [param velocity] limited so that, after moving for [param delta] seconds, the body at
## [param point] ends no further than [member length] from the anchor: outward speed is
## capped at the slack left (a negative cap, i.e. a pull back in, if it is already past the
## end). Motion towards the anchor and around it is untouched.
func constrain_velocity(point: Vector3, velocity: Vector3, delta: float) -> Vector3:
	if not attached or delta <= 0.0:
		return velocity
	var offset := point - anchor
	if offset.is_zero_approx():
		return velocity
	var outward := offset.normalized()
	var radial := velocity.dot(outward)
	var allowed := (length - offset.length()) / delta
	if radial <= allowed:
		return velocity
	return velocity - outward * (radial - allowed)


## [method constrain_velocity] for a swing that keeps its speed: when the line was taut on
## the last step and still is, the speed is kept and only turned along the swing (the
## sideways part grows; it never shrinks). A line going taut after hanging slack takes the
## outward speed away as usual (a catch).
func swing_velocity(point: Vector3, velocity: Vector3, delta: float) -> Vector3:
	if not attached or delta <= 0.0:
		return velocity
	var offset := point - anchor
	var taut := offset.length() > length - taut_tolerance
	var was_taut := _was_taut
	_was_taut = taut
	var held := constrain_velocity(point, velocity, delta)
	if not (taut and was_taut) or held.is_equal_approx(velocity) or offset.is_zero_approx():
		return held
	var outward := offset.normalized()
	var radial := held.dot(outward)
	var sideways := held - outward * radial
	var side_speed := sideways.length()
	if side_speed < SIDEWAYS_EPSILON:
		return held
	var kept := sqrt(maxf(velocity.length_squared() - radial * radial, 0.0))
	return outward * radial + sideways * (maxf(kept, side_speed) / side_speed)


## The velocity for one swing step of a body at [param point] moving at [param velocity],
## [b]before[/b] the host adds [param gravity] for [param delta] seconds (the host adds it
## and moves after the ability ticks). The result, once the host has added gravity, never
## takes the body past [member length] (a hard constraint, not a spring), and its speed is
## what energy conservation gives at the end of the step: the speed now plus the work
## gravity does over the step's displacement (the line being reeled in adds its inward pull
## on top, never taking it out of the swing). While the line is slack (the body moving in
## towards the anchor or hanging inside the length) the velocity is untouched. A body
## falling straight out along the line (no sideways motion to turn it into) is caught.
func sling_velocity(point: Vector3, velocity: Vector3, gravity: Vector3, delta: float
		) -> Vector3:
	if not attached or delta <= 0.0:
		return velocity
	var next := velocity + gravity * delta
	var offset := point - anchor
	if offset.is_zero_approx():
		return velocity
	var outward := offset.normalized()
	var radial := next.dot(outward)
	var allowed := (length - offset.length()) / delta
	if radial <= allowed:
		return velocity
	var held := next - outward * (radial - allowed)
	var sideways := held - outward * allowed
	var side_speed := sideways.length()
	if side_speed > SIDEWAYS_EPSILON:
		# Speed at the end of the step: what it is now plus gravity's work on the way.
		# The radial speed the body already had is not swing speed: a line being reeled in
		# adds its pull on top instead of taking it out of the swing.
		var step := held * delta
		var speed_sq := velocity.length_squared() + 2.0 * gravity.dot(step)
		var radial_now := minf(velocity.dot(outward), 0.0)
		var side_target := sqrt(maxf(speed_sq - radial_now * radial_now, 0.0))
		held = outward * allowed + sideways * (side_target / side_speed)
	return held - gravity * delta
