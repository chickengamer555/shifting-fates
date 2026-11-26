class_name PortalPlacement
extends RefCounted
## Where a level's two portals and the skater's start go, worked out from the level art's
## [code]Spawn[/code] and [code]Portal[/code] markers. One rule for both sides of a portal:
## the level uses it to place its real portals, and a [Portal] uses it inside its preview
## world to find where it looks out from, so the view through a portal is exactly the world
## the player arrives in.
## [br]Markers are placed by eye in Chickbry and float a little: a portal stands on the floor
## found below its marker (art water counts as floor), or, with no floor within
## [constant MARKER_FLOOR_REACH], hangs with its opening's centre at the marker. The heading
## is level, from Spawn towards Portal. The skater starts up to [constant ARRIVAL_STEP] m in
## front of the way in, on the floor there, and the way in stands on that same floor.
## [br]A portal's frame: origin at its base, -Z the way through. The exit's way through is the
## heading; the way in's is back the way the player came.

## Metres in front of the way in that the skater starts, so the camera behind the skater is
## still on this side of the opening...
const ARRIVAL_STEP := 6.0
## ...but at most this share of the way from the way in to the exit.
const ARRIVAL_STEP_SHARE := 0.25
## How far below a marker the floor is looked for (metres).
const MARKER_FLOOR_REACH := 40.0
## The skater starts this far above the floor.
const START_LIFT := 0.1
## Keys of the [method plan] result.
const KEY_HEADING := &"heading"
const KEY_START := &"start"
const KEY_WAY_IN := &"way_in"
const KEY_EXIT := &"exit"


## The plan for markers at [param spawn] and [param exit_marker] (null: no exit marker),
## using floors in [param space]: [constant KEY_HEADING] (Vector3), [constant KEY_START]
## (skater, Transform3D), [constant KEY_WAY_IN] and, with an exit marker,
## [constant KEY_EXIT] (portal frames, Transform3D).
static func plan(space: PhysicsDirectSpaceState3D, spawn: Vector3,
		exit_marker: Variant) -> Dictionary:
	var heading := Vector3.FORWARD
	var step := ARRIVAL_STEP
	if exit_marker != null:
		var flat := (exit_marker as Vector3) - spawn
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			heading = flat.normalized()
			step = minf(ARRIVAL_STEP, flat.length() * ARRIVAL_STEP_SHARE)
	var facing := Basis.looking_at(heading, Vector3.UP)
	var way_in_at := portal_base(space, spawn)
	var start := spawn + heading * step
	var start_floor: Variant = floor_below(space, start)
	if start_floor != null:
		start = (start_floor as Vector3) + Vector3.UP * START_LIFT
		# The way in stands on the floor the skater starts on, not on something under a
		# marker that floats high up.
		way_in_at.y = (start_floor as Vector3).y
	var result := {
		KEY_HEADING: heading,
		KEY_START: Transform3D(facing, start),
		KEY_WAY_IN: Transform3D(Basis.looking_at(-heading, Vector3.UP), way_in_at),
	}
	if exit_marker != null:
		result[KEY_EXIT] = Transform3D(facing, portal_base(space, exit_marker as Vector3))
	return result


## Where a portal marked at [param marker] stands: on the floor below, or hanging with its
## opening's centre at the marker.
static func portal_base(space: PhysicsDirectSpaceState3D, marker: Vector3) -> Vector3:
	var floor_point: Variant = floor_below(space, marker)
	if floor_point != null:
		return floor_point as Vector3
	return marker - Vector3.UP * Portal.CENTRE_HEIGHT


## The first world surface (bodies or areas, e.g. art water) within
## [constant MARKER_FLOOR_REACH] below [param point], or null.
static func floor_below(space: PhysicsDirectSpaceState3D, point: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5,
		point - Vector3.UP * MARKER_FLOOR_REACH, PhysicsLayers.WORLD_MASK)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"] as Vector3


## The frame of the opening of a portal whose base frame is [param portal_frame]: at its
## centre, -Z the way through.
static func opening(portal_frame: Transform3D) -> Transform3D:
	return portal_frame * Transform3D(Basis.IDENTITY, Vector3.UP * Portal.CENTRE_HEIGHT)


## The frame a viewer stepping out of the portal at [param portal_frame] arrives in: its
## opening's centre, facing out of it (the opposite of its way through).
static func stepping_out_of(portal_frame: Transform3D) -> Transform3D:
	return opening(portal_frame) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
