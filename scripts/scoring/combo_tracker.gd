class_name ComboTracker
extends RefCounted
## Tracks one air combo: the air-time multiplier, the pending trick points, and the score.
##
## Call [method start_air] on take-off, [method tick] every physics frame, [method add_trick]
## / [method add_grab] as tricks happen, and [method land] on touch-down. While airborne the
## multiplier starts at 1.0x and grows 0.1x for every full 0.3 s. Landing banks
## [code]pending points * multiplier[/code] into [member total_score]; an unclean landing
## halves that. Air time is counted in whole microseconds so steps never drift.

## The multiplier moved to [param multiplier] (a step in the air, or the reset on landing).
signal multiplier_changed(multiplier: float)
## The multiplier crossed into a new rank, named [param rank_name] (see [ComboRanks]).
signal rank_changed(rank_name: String)
## A combo was banked for [param points]; [param clean] is false if it was halved.
signal combo_banked(points: int, clean: bool)
## The combo ended in an unclean landing (fired before [signal combo_banked]).
signal combo_failed

## Air time per multiplier step, in microseconds (0.3 s).
const STEP_USEC := 300_000
## Microseconds per second, for converting [method tick] deltas.
const USEC_PER_SECOND := 1_000_000
## Multiplier at the start of every combo, in tenths (1.0x).
const BASE_TENTHS := 10
## Multiplier gained per step, in tenths (0.1x).
const TENTHS_PER_STEP := 1
## Tenths per 1.0x.
const TENTHS_PER_UNIT := 10.0
## Share of the combo kept after an unclean landing.
const UNCLEAN_LANDING_FACTOR := 0.5

## Banked points across all combos so far.
var total_score: int = 0
## Current multiplier, 1.0 while grounded or before the first step.
var multiplier: float:
	get:
		return float(BASE_TENTHS + _steps * TENTHS_PER_STEP) / TENTHS_PER_UNIT
## Rank name for the current multiplier.
var rank_name: String:
	get:
		return ComboRanks.rank_name(multiplier)
## Trick points waiting to be multiplied and banked, rounded down to whole points.
var pending_points: int:
	get:
		return floori(_pending)

var _airborne: bool = false
var _air_usec: int = 0
var _steps: int = 0
var _pending: float = 0.0


## True between [method start_air] and [method land].
func is_airborne() -> bool:
	return _airborne


## Begins air time for a combo. Does nothing if already airborne.
func start_air() -> void:
	_airborne = true


## Advances air time by [param delta] seconds; the multiplier only grows while airborne.
func tick(delta: float) -> void:
	if not _airborne or delta <= 0.0:
		return
	_air_usec += roundi(delta * USEC_PER_SECOND)
	@warning_ignore("integer_division")
	var reached := _air_usec / STEP_USEC
	while _steps < reached:
		var old_rank := rank_name
		_steps += 1
		multiplier_changed.emit(multiplier)
		if rank_name != old_rank:
			rank_changed.emit(rank_name)


## Adds a one-off trick's [param points] to the pending combo (see [TrickCatalog]).
func add_trick(points: int) -> void:
	if points > 0:
		_pending += points


## Adds points for a grab held [param delta] seconds at [param points_per_second].
func add_grab(points_per_second: float, delta: float) -> void:
	if points_per_second > 0.0 and delta > 0.0:
		_pending += points_per_second * delta


## Ends the combo: banks the pending points times the multiplier (halved when
## [param clean] is false), adds them to [member total_score] and resets.
## Returns the banked points, or 0 if there was no combo to land.
func land(clean: bool) -> int:
	if not _airborne and _pending <= 0.0:
		return 0
	var factor := 1.0 if clean else UNCLEAN_LANDING_FACTOR
	var banked := roundi(_pending * multiplier * factor)
	total_score += banked
	if not clean:
		combo_failed.emit()
	combo_banked.emit(banked, clean)
	_reset_combo()
	return banked


## Drops any combo in progress without banking it and zeroes [member total_score].
func reset() -> void:
	total_score = 0
	_reset_combo()


func _reset_combo() -> void:
	var had_steps := _steps > 0
	var old_rank := rank_name
	_airborne = false
	_air_usec = 0
	_steps = 0
	_pending = 0.0
	if had_steps:
		multiplier_changed.emit(multiplier)
	if rank_name != old_rank:
		rank_changed.emit(rank_name)
