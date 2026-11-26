class_name GrindBalance
extends RefCounted
## The grind balance minigame: a bar that wobbles off centre while the player counters it.
##
## [member balance] runs from -1 (fallen off left) through 0 (centred) to 1 (fallen off
## right); the HUD draws it as a marker on a line. Each [method tick] the bar is pushed by a
## random gust that changes direction every so often, and the further it leans the faster
## it falls (like balancing on a beam). The push gets stronger the longer the grind lasts,
## up to [member max_wobble_rate]. However hard the gust and the lean push together, the
## total is capped at [constant MAX_DRIFT_FRACTION] of [member counter_strength], so full
## input against the lean always wins and a player who reacts well can always hold the
## grind, even at full wobble. Player input (A = -1, D = +1) moves the bar
## in that direction. Reaching [constant BAIL_LIMIT] either way emits [signal bailed] once,
## and the bar then stops moving until [method reset].
##
## Pass a seeded [RandomNumberGenerator] to [method _init] for deterministic gusts.

## Emitted once when the bar reaches either end.
signal bailed

## |balance| at which the skater falls off the rail.
const BAIL_LIMIT := 1.0
## Smallest gust strength (as a fraction of the wobble rate), so a gust is never dead calm.
const MIN_GUST := 0.4
## Largest gust strength (as a fraction of the wobble rate).
const MAX_GUST := 1.0
## Largest drift (gust plus lean) as a fraction of [member counter_strength]. Below 1, so
## full counter input always moves the bar back towards the centre.
const MAX_DRIFT_FRACTION := 0.9

## Wobble rate (balance units per second) when the grind starts.
var base_wobble_rate: float = 0.5
## How much the wobble rate grows for each second spent grinding.
var wobble_growth: float = 0.3
## The wobble rate never grows past this, keeping long grinds hard but possible.
var max_wobble_rate: float = 2.0
## How strongly leaning makes the bar fall further (0 = gusts only).
var instability: float = 1.5
## How fast full input moves the bar (balance units per second).
var counter_strength: float = 3.0
## Shortest and longest time (seconds) before a gust changes direction.
var gust_interval_min: float = 0.4
var gust_interval_max: float = 1.0

## Current bar position, -1..1, 0 = centred.
var balance: float = 0.0
## Seconds since the grind started (drives the growing wobble).
var grind_time: float = 0.0
## True once the bar has hit an end; it no longer moves.
var has_bailed: bool = false

var _rng: RandomNumberGenerator
var _gust: float = 0.0
var _gust_time_left: float = 0.0


## [param rng] drives the gusts; leave it null for a randomly seeded one.
func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_rng = rng
	reset()


## Centres the bar and restarts the wobble timer for a new grind.
func reset() -> void:
	balance = 0.0
	grind_time = 0.0
	has_bailed = false
	_gust_time_left = 0.0
	_gust = 0.0


## Current wobble strength (balance units per second) for this point in the grind.
func wobble_rate() -> float:
	return minf(base_wobble_rate + wobble_growth * grind_time, max_wobble_rate)


## Current push on the bar from the gust and the lean (balance units per second), capped
## at [constant MAX_DRIFT_FRACTION] of [member counter_strength] either way.
func drift() -> float:
	var limit := counter_strength * MAX_DRIFT_FRACTION
	return clampf(wobble_rate() * (_gust + instability * balance), -limit, limit)


## Advances the minigame by [param delta] seconds with player [param input] in -1..1.
func tick(delta: float, input: float) -> void:
	if has_bailed:
		return
	grind_time += delta
	_gust_time_left -= delta
	if _gust_time_left <= 0.0:
		_pick_gust()
	var push := clampf(input, -1.0, 1.0) * counter_strength
	balance = clampf(balance + (drift() + push) * delta, -BAIL_LIMIT, BAIL_LIMIT)
	if absf(balance) >= BAIL_LIMIT:
		has_bailed = true
		bailed.emit()


func _pick_gust() -> void:
	var strength := _rng.randf_range(MIN_GUST, MAX_GUST)
	var direction := -1.0 if _rng.randf() < 0.5 else 1.0
	_gust = strength * direction
	_gust_time_left = _rng.randf_range(gust_interval_min, gust_interval_max)
