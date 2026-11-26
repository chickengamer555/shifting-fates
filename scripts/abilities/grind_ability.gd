class_name GrindAbility
extends SkaterAbility
## Grinding: hold C near a [GrindRail] to lock onto it and slide along it.
##
## While grinding this ability owns the skater's movement ([method is_controlling_movement]
## is true) and [method places_body_directly]: every tick it places the body on the rail at
## [member ride_height] above it and sets [code]velocity[/code] along the rail, so the host
## skips its own gravity, [code]move_and_slide()[/code] and air state that frame (a rail is
## neither ground nor air: no take-off, no air time). Speed is kept with slight friction, never
## dropping below [member min_grind_speed]. A/D feed a [GrindBalance] minigame (read
## [member balance] for the HUD bar). The grind ends:
## [br]- at the rail end: launched off with the rail speed plus a small pop (clean),
## [br]- on a fresh jump press: jumps off along the rail (clean),
## [br]- when C is released: rolls off along the rail (clean),
## [br]- when the balance bar hits an end: [signal bailed], knocked off sideways (not clean).
## [br]After any end the ability waits [member rearm_time] before it can snap again, and
## after a bail C must be released and pressed again. A rail only snaps while the feet are
## alongside it, not past either end, so the skater never re-grabs the rail it just left.
## Disabling the ability mid-grind ends the grind cleanly.

## Emitted when the skater locks onto [param rail].
signal grind_started(rail: GrindRail)
## Emitted when the grind finishes; [param clean] is false for a bail.
signal grind_ended(clean: bool)
## Emitted when the balance bar tipped over and the skater fell off.
signal bailed

const GRIND_ACTION := "grind"
const JUMP_ACTION := "jump"
const LEFT_ACTION := "move_left"
const RIGHT_ACTION := "move_right"
## Distance (m) from each rail end inside which a rail can't be snapped onto.
const END_MARGIN := 0.05

## Furthest (m) the skater's feet may be from a rail to snap onto it.
@export var snap_distance: float = 1.5
## Height (m) of the skater's origin above the rail while grinding.
@export var ride_height: float = 0.9
## Speed lost per second while grinding (m/s²).
@export var friction: float = 0.6
## Grinds never run slower than this (m/s); also the entry speed when nearly stopped.
@export var min_grind_speed: float = 4.0
## Upward speed (m/s) added when the rail ends under the skater.
@export var end_pop_speed: float = 2.0
## Upward speed (m/s) of a jump off the rail.
@export var jump_off_speed: float = 6.0
## Sideways speed (m/s) of the knock when bailing.
@export var bail_knock_speed: float = 3.0
## Upward speed (m/s) of the knock when bailing.
@export var bail_pop_speed: float = 1.5
## Fraction of the rail speed kept after a bail.
@export var bail_speed_keep: float = 0.4
## Seconds after a grind ends before another can start.
@export var rearm_time: float = 0.35

@export_group("Balance")
## Starting wobble rate of the balance bar (see [GrindBalance]).
@export var wobble_base_rate: float = 0.5
## Wobble rate growth per second of grinding.
@export var wobble_growth: float = 0.3
## Wobble rate cap.
@export var max_wobble_rate: float = 2.0

## Optional seeded generator for the balance gusts (tests); null = random.
var balance_rng: RandomNumberGenerator = null
## True while riding a rail.
var grinding: bool = false
## The rail being ground, or null.
var rail: GrindRail = null
## Whether the most recent grind ended cleanly (false after a bail).
var last_end_clean: bool = true
## Balance bar position -1..1 for the HUD (0 when not grinding).
var balance: float:
	get:
		return _balance.balance if grinding and _balance != null else 0.0

var _balance: GrindBalance = null
var _offset: float = 0.0
var _direction: float = 1.0
var _speed: float = 0.0
var _rearm_left: float = 0.0
var _jump_was_held: bool = false
var _bail_pending: bool = false
var _needs_regrip: bool = false
## The body last ticked, so a mid-grind disable can let it go.
var _host: CharacterBody3D = null


func physics_tick(skater: CharacterBody3D, delta: float) -> void:
	_host = skater
	_rearm_left = maxf(_rearm_left - delta, 0.0)
	if not grinding:
		if not _wants_grind():
			_needs_regrip = false
		elif _rearm_left <= 0.0 and not _needs_regrip:
			_try_start(skater)
		return
	_tick_grind(skater, delta)


func is_controlling_movement() -> bool:
	return grinding


func places_body_directly() -> bool:
	return grinding


func is_active() -> bool:
	return grinding


## Ends the current grind (e.g. the Skater got hit or a cutscene started).
func stop_grind(skater: CharacterBody3D) -> void:
	if grinding:
		_end(skater, true, Vector3.ZERO)


func _on_disabled() -> void:
	if _host != null:
		stop_grind(_host)


func _wants_grind() -> bool:
	return input_enabled and Input.is_action_pressed(GRIND_ACTION)


func _try_start(skater: CharacterBody3D) -> void:
	var feet := _feet(skater)
	var best: GrindRail = null
	var best_distance := snap_distance
	for node in skater.get_tree().get_nodes_in_group(GrindRail.GROUP):
		var candidate := node as GrindRail
		if candidate == null or candidate.length() <= 0.0:
			continue
		var offset := candidate.closest_offset(feet)
		if offset <= END_MARGIN or offset >= candidate.length() - END_MARGIN:
			continue
		var distance := candidate.distance_to(feet)
		if distance <= best_distance:
			best = candidate
			best_distance = distance
	if best != null:
		_start(skater, best)


func _start(skater: CharacterBody3D, target: GrindRail) -> void:
	rail = target
	grinding = true
	_offset = rail.closest_offset(_feet(skater))
	var along := skater.velocity.dot(rail.tangent_at(_offset))
	_direction = -1.0 if along < 0.0 else 1.0
	_speed = maxf(absf(along), min_grind_speed)
	_balance = GrindBalance.new(balance_rng)
	_balance.base_wobble_rate = wobble_base_rate
	_balance.wobble_growth = wobble_growth
	_balance.max_wobble_rate = max_wobble_rate
	_bail_pending = false
	_balance.bailed.connect(_on_balance_bailed)
	_jump_was_held = Input.is_action_pressed(JUMP_ACTION)
	_place(skater)
	grind_started.emit(rail)
	activated.emit()


func _tick_grind(skater: CharacterBody3D, delta: float) -> void:
	var jump_held := input_enabled and Input.is_action_pressed(JUMP_ACTION)
	var jump_pressed := jump_held and not _jump_was_held
	_jump_was_held = jump_held
	if jump_pressed:
		_end(skater, true, Vector3.UP * jump_off_speed)
		return
	if not _wants_grind():
		_end(skater, true, Vector3.ZERO)
		return
	var steer := Input.get_axis(LEFT_ACTION, RIGHT_ACTION) if input_enabled else 0.0
	_balance.tick(delta, steer)
	if _bail_pending:
		_bail(skater)
		return
	_speed = maxf(_speed - friction * delta, min_grind_speed)
	_offset += _direction * _speed * delta
	if _offset <= 0.0 or _offset >= rail.length():
		_offset = clampf(_offset, 0.0, rail.length())
		_place(skater)
		_end(skater, true, Vector3.UP * end_pop_speed)
		return
	_place(skater)


func _bail(skater: CharacterBody3D) -> void:
	var side := _travel_direction().cross(Vector3.UP).normalized()
	var lean := signf(_balance.balance)
	var knock := side * lean * bail_knock_speed + Vector3.UP * bail_pop_speed
	_speed *= bail_speed_keep
	_needs_regrip = true
	bailed.emit()
	_end(skater, false, knock)


func _end(skater: CharacterBody3D, clean: bool, extra_velocity: Vector3) -> void:
	skater.velocity = _travel_direction() * _speed + extra_velocity
	if _balance != null and _balance.bailed.is_connected(_on_balance_bailed):
		_balance.bailed.disconnect(_on_balance_bailed)
	grinding = false
	rail = null
	_balance = null
	last_end_clean = clean
	_rearm_left = rearm_time
	grind_ended.emit(clean)
	deactivated.emit()


func _place(skater: CharacterBody3D) -> void:
	skater.global_position = rail.position_at(_offset) + Vector3.UP * ride_height
	skater.velocity = _travel_direction() * _speed


func _travel_direction() -> Vector3:
	return rail.tangent_at(_offset) * _direction


func _feet(skater: CharacterBody3D) -> Vector3:
	return skater.global_position - Vector3.UP * ride_height


func _on_balance_bailed() -> void:
	_bail_pending = true
