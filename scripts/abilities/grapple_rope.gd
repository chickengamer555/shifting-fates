class_name GrappleRope
extends RefCounted
## Rules for one grapple hook's line, with no nodes so it can be tested on its own.
##
## Reading of the design note "grapple hook extends over time while in air so it'll get to
## the point where line too long to work": once a hook is attached its line keeps paying
## out while the skater is airborne ([member payout_speed] m/s), so every swing hangs a
## little lower and looser. On the ground the line holds its length. When the line grows
## past [member max_length] it is too long to be useful and the hook lets go
## ([signal detached]). While the owner reels the body in, [method wind_in] takes up the
## slack so the line ends up shorter, never below [member min_length].
##
## The line is a rope, not a rod: [method constrain_velocity] only stops the body moving
## further than [member length] from the anchor; moving towards the anchor is free. It
## works on velocity alone (no teleporting), so a CharacterBody3D still collides normally.

## Emitted once when the line grows too long and the hook lets go.
signal detached

## How fast (m/s) the line pays out while airborne.
var payout_speed: float = 2.5
## Longest usable line (m); past this the hook detaches.
var max_length: float = 25.0
## The line is never shorter than this (m).
var min_length: float = 1.5

## World point the hook is stuck to.
var anchor: Vector3 = Vector3.ZERO
## Current line length (m).
var length: float = 0.0
## True while the hook is stuck to something.
var attached: bool = false


## Sticks the hook at [param anchor_point] with the line just reaching [param from_position].
func attach(anchor_point: Vector3, from_position: Vector3) -> void:
	anchor = anchor_point
	length = maxf(anchor_point.distance_to(from_position), min_length)
	attached = true


## Lets go of the anchor (no signal; the caller chose to release).
func release() -> void:
	attached = false


## Pays the line out while [param airborne]; detaches once it is longer than max_length.
func tick(delta: float, airborne: bool) -> void:
	if not attached or not airborne:
		return
	length += payout_speed * delta
	if length > max_length:
		attached = false
		detached.emit()


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
