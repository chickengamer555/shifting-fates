class_name ScoreKeeper
extends Node
## Turns a [Skater]'s moves into points for the level.
##
## Call [method bind] with the skater once it is ready. The keeper drives a [ComboTracker]
## with [TrickCatalog] points and feeds every banked combo to the level's [LevelGoal]
## (from [code]GameState.create_level_goal()[/code] on ready, unless [method set_goal] was
## called first). One combo works like this:
## [br]- It opens when the skater takes off or locks onto a grind rail.
## [br]- Air time [b]and grind time[/b] grow the multiplier (0.1x per 0.3 s, see
##   [ComboTracker]): riding a rail keeps the combo alive between jumps. The Skater itself
##   never counts grinding as air time; that rule lives here.
## [br]- Flip tricks add their one-off points; grabs and grinding add points per second.
## [br]- Combos chain easily: after a clean landing (or a clean end of a grind) the combo
##   stays open for [member chain_window] seconds, multiplier held. Taking off again or
##   locking onto a rail inside that window carries the whole combo on; otherwise it banks
##   pending points x multiplier, clean.
## [br]- An unclean landing or a grind bail banks half at once and ends the combo.
##
## Runs its physics step after the default priority, so it sees the skater's state for the
## frame. Re-emits everything the HUD needs; nothing else has to watch the skater.

## [member score] changed to [param score] (a combo was banked).
signal score_changed(score: int)
## The combo multiplier or its rank changed.
signal combo_changed(multiplier: float, rank_name: String)
## A combo scored [param points] (> 0); [param clean] is false when it was halved.
signal combo_banked(points: int, clean: bool)
## The level's point goal was reached (once per goal).
signal goal_reached

## Physics priority after the Skater's default (0), so the skater has moved this frame.
const AFTER_SKATER_PRIORITY := 1

## Pending points earned per second of grinding.
@export var grind_points_per_second: float = 100.0
## Seconds a clean landing keeps the combo open for the next jump or rail. Longer than the
## skater's take-off grace, so rolling off a rail end into a hop still chains.
@export var chain_window: float = 0.75

## The combo rules; read-only for callers.
var combo: ComboTracker = ComboTracker.new()
## The level's point goal, or null before ready.
var goal: LevelGoal = null
## Points banked so far this level.
var score: int:
	get:
		return combo.total_score
## Current combo multiplier.
var multiplier: float:
	get:
		return combo.multiplier
## Rank name of the current multiplier.
var rank_name: String:
	get:
		return combo.rank_name
## Fraction of the goal collected (0..1); 0 without a goal.
var goal_progress: float:
	get:
		return goal.progress() if goal != null else 0.0
## Points of the last banked combo that scored anything.
var last_banked: int = 0
## Whether the last banked combo landed clean.
var last_banked_clean: bool = true
## True while the bound skater grinds.
var grinding: bool = false

var _skater: Skater = null
var _grind: GrindAbility = null
var _grab_id: StringName = TrickCatalog.NO_TRICK
## Seconds left to chain the combo after a clean landing; 0 when not waiting.
var _chain_left: float = 0.0


func _ready() -> void:
	set_meta("verify_unit", "ScoreKeeper")
	process_physics_priority = AFTER_SKATER_PRIORITY
	combo.multiplier_changed.connect(_on_combo_multiplier_changed)
	combo.combo_banked.connect(_on_combo_banked)
	if goal == null:
		set_goal(GameState.create_level_goal())


func _physics_process(delta: float) -> void:
	# The multiplier only grows in the air and on rails, not while waiting to chain.
	if _chain_left <= 0.0:
		combo.tick(delta)
	if _grab_id != TrickCatalog.NO_TRICK:
		combo.add_grab(TrickCatalog.grab_points_per_second(_grab_id), delta)
	if grinding:
		combo.add_grab(grind_points_per_second, delta)
	if _chain_left > 0.0:
		_chain_left -= delta
		if _chain_left <= 0.0:
			_chain_left = 0.0
			if _skater == null or not _skater.is_airborne():
				combo.land(true)


## True while a landed combo is waiting [member chain_window] for the next jump or rail.
func is_chaining() -> bool:
	return _chain_left > 0.0


## Starts scoring [param skater]'s moves (and its [member Skater.grind_ability]).
## Binding another skater lets go of the previous one.
func bind(skater: Skater) -> void:
	_unbind()
	_skater = skater
	if _skater == null:
		return
	_skater.took_off.connect(_on_skater_took_off)
	_skater.landed.connect(_on_skater_landed)
	_skater.trick_performed.connect(_on_skater_trick_performed)
	_skater.grab_started.connect(_on_skater_grab_started)
	_skater.grab_ended.connect(_on_skater_grab_ended)
	_grind = _skater.grind_ability
	if _grind != null:
		_grind.grind_started.connect(_on_grind_started)
		_grind.grind_ended.connect(_on_grind_ended)


## Replaces the level goal (e.g. a new level started). Points already banked stay.
func set_goal(new_goal: LevelGoal) -> void:
	if goal != null and goal.goal_reached.is_connected(_on_goal_reached):
		goal.goal_reached.disconnect(_on_goal_reached)
	goal = new_goal
	if goal != null:
		goal.goal_reached.connect(_on_goal_reached)


## Drops the combo in progress and zeroes the score (the goal keeps its own points).
func reset_score() -> void:
	combo.reset()
	_grab_id = TrickCatalog.NO_TRICK
	_chain_left = 0.0
	score_changed.emit(score)


func _unbind() -> void:
	if _skater != null:
		_skater.took_off.disconnect(_on_skater_took_off)
		_skater.landed.disconnect(_on_skater_landed)
		_skater.trick_performed.disconnect(_on_skater_trick_performed)
		_skater.grab_started.disconnect(_on_skater_grab_started)
		_skater.grab_ended.disconnect(_on_skater_grab_ended)
	if _grind != null:
		_grind.grind_started.disconnect(_on_grind_started)
		_grind.grind_ended.disconnect(_on_grind_ended)
	_skater = null
	_grind = null
	grinding = false


func _open_combo() -> void:
	var was_open := combo.is_airborne()
	combo.start_air()
	if not was_open:
		combo_changed.emit(multiplier, rank_name)


func _on_skater_took_off() -> void:
	_chain_left = 0.0
	_open_combo()


func _on_skater_landed(clean: bool) -> void:
	_grab_id = TrickCatalog.NO_TRICK
	if clean and combo.is_airborne():
		_chain_left = chain_window
		return
	_chain_left = 0.0
	combo.land(clean)


func _on_skater_trick_performed(trick_id: StringName) -> void:
	combo.add_trick(TrickCatalog.base_points(trick_id))


func _on_skater_grab_started(grab_id: StringName) -> void:
	_grab_id = grab_id


func _on_skater_grab_ended(_grab_id_ended: StringName) -> void:
	_grab_id = TrickCatalog.NO_TRICK


func _on_grind_started(_rail: GrindRail) -> void:
	grinding = true
	_chain_left = 0.0
	_open_combo()


func _on_grind_ended(clean: bool) -> void:
	grinding = false
	if clean:
		_chain_left = chain_window
	else:
		_chain_left = 0.0
		combo.land(false)


func _on_combo_multiplier_changed(value: float) -> void:
	combo_changed.emit(value, ComboRanks.rank_name(value))


## Empty combos (a plain ollie, the hop after a bail) bank 0 and are not reported.
func _on_combo_banked(points: int, clean: bool) -> void:
	if points <= 0:
		return
	last_banked = points
	last_banked_clean = clean
	if goal != null:
		goal.add_points(points)
	combo_banked.emit(points, clean)
	score_changed.emit(score)


func _on_goal_reached() -> void:
	goal_reached.emit()
