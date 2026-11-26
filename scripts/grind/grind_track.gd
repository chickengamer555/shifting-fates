class_name GrindTrack
extends RefCounted
## Something the skater can grind along: a hand-placed [GrindRail] ([RailTrack]) or a sharp
## edge of the level art ([EdgeTrack]). [GrindAbility] rides any of them through this
## interface. Offsets are metres along the track from its start; everything else is world
## space. Override every method.


## Total length (m).
func length() -> float:
	return 0.0


## True when the end joins back to the start (a round rim): offsets wrap instead of ending.
func is_loop() -> bool:
	return false


## Offset (m) of the point on the track closest to [param world_pos].
func closest_offset(_world_pos: Vector3) -> float:
	return 0.0


## World position at [param offset] (clamped, or wrapped on a loop).
func position_at(_offset: float) -> Vector3:
	return Vector3.ZERO


## Unit world direction of travel towards larger offsets at [param offset].
func tangent_at(_offset: float) -> Vector3:
	return Vector3.RIGHT


## Straight-line distance (m) from [param world_pos] to the nearest point on the track.
func distance_to(world_pos: Vector3) -> float:
	return world_pos.distance_to(position_at(closest_offset(world_pos)))


## The physics body the track belongs to, if any (never counted as burying the track).
func body_rid() -> RID:
	return RID()


## Short name for logs.
func label() -> String:
	return "track"
