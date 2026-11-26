class_name LevelGoal
extends RefCounted
## A level's point threshold. Reaching it appeases the gods and opens the next portal.
##
## Feed it banked combo points with [method add_points]; [signal goal_reached] fires once,
## the first time the total reaches [member threshold].

## Points reached [member threshold] for the first time.
signal goal_reached

## Points needed to meet the goal.
var threshold: int = 0
## Points collected so far.
var points: int = 0

var _reached: bool = false


func _init(point_threshold: int = 0) -> void:
	threshold = maxi(point_threshold, 0)


## Adds banked [param amount]; non-positive amounts are ignored.
func add_points(amount: int) -> void:
	if amount <= 0:
		return
	points += amount
	if not _reached and is_met():
		_reached = true
		goal_reached.emit()


## True once [member points] has reached [member threshold].
func is_met() -> bool:
	return points >= threshold


## Points still needed, never below 0.
func remaining() -> int:
	return maxi(threshold - points, 0)


## Fraction of the goal collected, clamped to 0..1 (1 for a zero threshold).
func progress() -> float:
	if threshold <= 0:
		return 1.0
	return clampf(float(points) / float(threshold), 0.0, 1.0)
