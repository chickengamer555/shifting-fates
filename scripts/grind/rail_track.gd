class_name RailTrack
extends GrindTrack
## A hand-placed [GrindRail] seen as a [GrindTrack].

## The rail this track reads.
var rail: GrindRail


func _init(source: GrindRail) -> void:
	rail = source


func length() -> float:
	return rail.length()


func closest_offset(world_pos: Vector3) -> float:
	return rail.closest_offset(world_pos)


func position_at(offset: float) -> Vector3:
	return rail.position_at(offset)


func tangent_at(offset: float) -> Vector3:
	return rail.tangent_at(offset)


func distance_to(world_pos: Vector3) -> float:
	return rail.distance_to(world_pos)


func label() -> String:
	return String(rail.name)
