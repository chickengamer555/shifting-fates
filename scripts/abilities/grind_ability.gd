class_name GrindAbility
extends SkaterAbility
## Grinding: hold C near a [GrindRail] or any sharp edge of the level art to lock onto it
## and slide along it.
##
## What can be ground: every hand-placed rail (group [constant GrindRail.GROUP]) and every
## sharp convex edge of the solid level geometry (the top edges of a box, the lip of a ramp,
## the rim of a disc), found by [GrindEdges] / [EdgeFinder] once when the level loads.
## Either is ridden as a [GrindTrack] ([member track]).
## [br]While grinding this ability owns the skater's movement ([method is_controlling_movement]
## is true) and [method places_body_directly]: every tick it places the body on the track at
## [member ride_height] above it and sets [code]velocity[/code] along it, so the host
## skips its own gravity, [code]move_and_slide()[/code] and air state that frame (a rail is
## neither ground nor air: no take-off, no air time). Speed is kept with slight friction, never
## dropping below [member min_grind_speed]; the full rolling speed carries onto the track
## whatever the entry angle. A/D feed a [GrindBalance] minigame (read
## [member balance] for the HUD bar). The grind ends:
## [br]- at the track end, or where an edge runs into other geometry (a ramp's side edge
##   meeting the ground): launched off with the speed plus a small pop (clean); a round rim
##   (a loop) has no end,
## [br]- on a fresh jump press: jumps off along the track (clean),
## [br]- when C is released: rolls off along the track (clean),
## [br]- when the balance bar hits an end: [signal thrown_off]. Losing the balance is not a
##   bail: the rider is thrown off the side it leant to with a small hop, keeps most of the
##   speed ([member throw_speed_keep]) and rides on; the grind still ends clean, so the combo
##   carries on.
## [br]After any end the ability waits [member rearm_time] before it can snap again, and
## after being thrown off C must be released and pressed again. A track only snaps while the
## feet are alongside it, not past either end, so the skater never re-grabs the track it just
## left.
## Disabling the ability mid-grind ends the grind cleanly.

## Emitted when the skater locks onto a track: [param rail] is the [GrindRail], or null on
## an edge of the level art (read [member track]).
signal grind_started(rail: GrindRail)
## Emitted when the grind finishes; [param clean] is false only when it was cut short by
## something other than the rider (never for a lost balance).
signal grind_ended(clean: bool)
## Emitted when the balance bar tipped over and the rider was thrown off the rail.
signal thrown_off

const GRIND_ACTION := "grind"
const JUMP_ACTION := "jump"
const LEFT_ACTION := "move_left"
const RIGHT_ACTION := "move_right"
## Distance (m) from each rail end inside which a rail can't be snapped onto.
const END_MARGIN := 0.05
## An edge counts as buried (ends the grind) when other geometry sits between
## [constant BURY_CLEARANCE] and [constant BURY_PROBE] metres above it (the ground it runs
## into, or no room for the rider).
const BURY_CLEARANCE := 0.05
const BURY_PROBE := 0.9

## Furthest (m) the skater's feet may be from a rail or edge to snap onto it. Generous:
## rolling beside a rail, or dropping onto it from above, locks on from up to this far.
@export var snap_distance: float = 2.5
## Seconds the body takes to slide from where it was onto the rail when it snaps, so a
## snap from a metre or two away reads as a hop onto the rail, not a teleport.
@export var entry_blend_time: float = 0.12
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
## Sideways speed (m/s) of the throw when the balance is lost, towards the side leant to.
@export var throw_side_speed: float = 2.5
## Upward speed (m/s) of the hop off the rail when the balance is lost.
@export var throw_pop_speed: float = 2.5
## Fraction of the rail speed kept when thrown off.
@export_range(0.0, 1.0) var throw_speed_keep: float = 0.9
## Seconds after a grind ends before another can start.
@export var rearm_time: float = 0.35

@export_group("Balance")
## Starting wobble rate of the balance bar (see [GrindBalance]).
@export var wobble_base_rate: float = 0.5
## Wobble rate growth per second of grinding.
@export var wobble_growth: float = 0.3
## Wobble rate cap.
@export var max_wobble_rate: float = 2.0

@export_group("Edges")
## Sharp edges of the level art can be ground, not only GrindRails.
@export var grind_edges: bool = true

## Optional seeded generator for the balance gusts (tests); null = random.
var balance_rng: RandomNumberGenerator = null
## True while riding a rail or an edge.
var grinding: bool = false
## What is being ground (a rail or an edge), or null.
var track: GrindTrack = null
## The rail being ground, or null (also null on an edge of the art).
var rail: GrindRail = null
## True while grinding an edge of the level art rather than a GrindRail.
var on_edge: bool:
	get:
		return grinding and rail == null
## Whether the most recent grind ended cleanly (a lost balance still ends clean).
var last_end_clean: bool = true
## Whether the most recent grind ended with the rider thrown off (the balance lost).
var last_end_thrown: bool = false
## Balance bar position -1..1 for the HUD (0 when not grinding).
var balance: float:
	get:
		return _balance.balance if grinding and _balance != null else 0.0

var _balance: GrindBalance = null
var _offset: float = 0.0
var _direction: float = 1.0
var _speed: float = 0.0
var _rearm_left: float = 0.0
## Where the body was relative to its rail spot when it snapped; fades out over
## [member entry_blend_time].
var _entry_offset: Vector3 = Vector3.ZERO
var _entry_left: float = 0.0
var _jump_was_held: bool = false
var _throw_pending: bool = false
var _needs_regrip: bool = false
## The body last ticked, so a mid-grind disable can let it go.
var _host: CharacterBody3D = null
var _watching: bool = false


func physics_tick(skater: CharacterBody3D, delta: float) -> void:
	_host = skater
	_build_edges(skater)
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
	var best: GrindTrack = null
	var best_rail: GrindRail = null
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
			best_rail = candidate
			best_distance = distance
	if best_rail != null:
		best = RailTrack.new(best_rail)
	if grind_edges:
		var edge := GrindEdges.nearest(skater, feet, best_distance, END_MARGIN)
		if not edge.is_empty() and float(edge["distance"]) < best_distance:
			var edge_track := edge["track"] as EdgeTrack
			if not _buried(skater, edge_track, float(edge["offset"])):
				best = edge_track
				best_rail = null
	if best != null:
		_start(skater, best, best_rail)


func _start(skater: CharacterBody3D, target: GrindTrack, target_rail: GrindRail) -> void:
	track = target
	rail = target_rail
	grinding = true
	_offset = track.closest_offset(_feet(skater))
	var along := skater.velocity.dot(track.tangent_at(_offset))
	_direction = -1.0 if along < 0.0 else 1.0
	# Arcade: the whole rolling speed carries onto the track, whatever the entry angle.
	var rolling := Vector2(skater.velocity.x, skater.velocity.z).length()
	_speed = maxf(rolling, min_grind_speed)
	_balance = GrindBalance.new(balance_rng)
	_balance.base_wobble_rate = wobble_base_rate
	_balance.wobble_growth = wobble_growth
	_balance.max_wobble_rate = max_wobble_rate
	_throw_pending = false
	_balance.bailed.connect(_on_balance_bailed)
	_jump_was_held = Input.is_action_pressed(JUMP_ACTION)
	_entry_offset = skater.global_position - _rail_spot()
	_entry_left = entry_blend_time
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
	if _throw_pending:
		_throw_off(skater)
		return
	_speed = maxf(_speed - friction * delta, min_grind_speed)
	_offset += _direction * _speed * delta
	_entry_left = maxf(_entry_left - delta, 0.0)
	if track.is_loop():
		_offset = fposmod(_offset, track.length())
	elif _offset <= 0.0 or _offset >= track.length():
		_offset = clampf(_offset, 0.0, track.length())
		_place(skater)
		_end(skater, true, Vector3.UP * end_pop_speed)
		return
	if rail == null and _buried(skater, track, _offset):
		_place(skater)
		_end(skater, true, Vector3.UP * end_pop_speed)
		return
	_place(skater)


## The balance is lost: off the side the rider leant to, with a hop, most speed kept.
func _throw_off(skater: CharacterBody3D) -> void:
	var side := _travel_direction().cross(Vector3.UP).normalized()
	var lean := signf(_balance.balance)
	var throw := side * lean * throw_side_speed + Vector3.UP * throw_pop_speed
	_speed *= throw_speed_keep
	_needs_regrip = true
	thrown_off.emit()
	_end(skater, true, throw, true)


func _end(skater: CharacterBody3D, clean: bool, extra_velocity: Vector3,
		thrown: bool = false) -> void:
	skater.velocity = _travel_direction() * _speed + extra_velocity
	if _balance != null and _balance.bailed.is_connected(_on_balance_bailed):
		_balance.bailed.disconnect(_on_balance_bailed)
	grinding = false
	rail = null
	track = null
	_balance = null
	last_end_clean = clean
	last_end_thrown = thrown
	_rearm_left = rearm_time
	grind_ended.emit(clean)
	deactivated.emit()


func _place(skater: CharacterBody3D) -> void:
	var blend := _entry_left / entry_blend_time if entry_blend_time > 0.0 else 0.0
	skater.global_position = _rail_spot() + _entry_offset * blend
	skater.velocity = _travel_direction() * _speed


## Where the body rides at the current offset: [member ride_height] above the track.
func _rail_spot() -> Vector3:
	return track.position_at(_offset) + Vector3.UP * ride_height


func _travel_direction() -> Vector3:
	return track.tangent_at(_offset) * _direction


## Builds the level's edges once, the frame after its shapes enter the skater's world.
func _build_edges(skater: CharacterBody3D) -> void:
	if not grind_edges:
		return
	if not _watching:
		_watching = true
		GrindEdges.watch(skater.get_tree(), skater.get_tree().root, skater.get_world_3d())
	if GrindEdges.has_pending():
		GrindEdges.build_pending(skater.get_world_3d())


## True when other geometry covers the edge at [param offset] (it runs into the ground or
## a wall): a short ray from above down to just above the edge hits something else, or
## starts inside something (the edge is deep underground).
func _buried(skater: CharacterBody3D, edge: GrindTrack, offset: float) -> bool:
	var point := edge.position_at(offset)
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * BURY_PROBE,
			point + Vector3.UP * BURY_CLEARANCE, GrindEdges.MASK)
	var exclude: Array[RID] = [skater.get_rid()]
	if edge.body_rid().is_valid():
		exclude.append(edge.body_rid())
	query.exclude = exclude
	query.hit_from_inside = true
	return not skater.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _feet(skater: CharacterBody3D) -> Vector3:
	return skater.global_position - Vector3.UP * ride_height


func _on_balance_bailed() -> void:
	_throw_pending = true
