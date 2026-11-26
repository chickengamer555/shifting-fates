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
## [br]A Portal marker inside the hole of a ring-shaped art object (a torus: one thin axis
## and a hole through it, see [method find_ring]) puts the exit in that ring instead: its
## opening centred on the ring, facing through it (the axis sign pointing away from Spawn),
## sized to fill the hole ([constant KEY_EXIT_RADIUS]).
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
## Opening radius (m) of the exit, present only when it fills a ring.
const KEY_EXIT_RADIUS := &"exit_radius"
## Share of a ring's hole the opening fills, so its rim of light sits just inside the ring.
const RING_FILL := 0.92
## A mesh is a ring when its thinnest side is at most this share of its other two...
const RING_FLATNESS := 0.5
## ...which are within this share of each other.
const RING_ROUNDNESS := 0.2
## A marker counts as in a ring's hole within this many times the ring's thickness of its
## middle plane.
const RING_DEPTH_REACH := 1.5
## Keys of a [method find_ring] result.
const RING_CENTRE := &"centre"
const RING_AXIS := &"axis"
const RING_RADIUS := &"radius"
## The art's markers, children of the art scene's root.
const SPAWN_MARKER := ^"Spawn"
const PORTAL_MARKER := ^"Portal"


## [method plan] for the markers of the art scene [param art] (in the tree), or empty when
## it has no [constant SPAWN_MARKER].
static func plan_for_art(art: Node, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var spawn := art.get_node_or_null(SPAWN_MARKER) as Node3D
	if spawn == null:
		return {}
	var exit_marker := art.get_node_or_null(PORTAL_MARKER) as Node3D
	if exit_marker == null:
		return plan(space, spawn.global_position, null)
	return plan(space, spawn.global_position, exit_marker.global_position,
		find_ring(art, exit_marker.global_position))


## The plan for markers at [param spawn] and [param exit_marker] (null: no exit marker),
## using floors in [param space]: [constant KEY_HEADING] (Vector3), [constant KEY_START]
## (skater, Transform3D), [constant KEY_WAY_IN] and, with an exit marker,
## [constant KEY_EXIT] (portal frames, Transform3D). With a [param ring] (a
## [method find_ring] result) the exit fills it and [constant KEY_EXIT_RADIUS] is set.
static func plan(space: PhysicsDirectSpaceState3D, spawn: Vector3,
		exit_marker: Variant, ring: Dictionary = {}) -> Dictionary:
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
	if not ring.is_empty():
		result[KEY_EXIT] = ring_frame(ring, spawn)
		result[KEY_EXIT_RADIUS] = float(ring[RING_RADIUS]) * RING_FILL
	elif exit_marker != null:
		result[KEY_EXIT] = Transform3D(facing, portal_base(space, exit_marker as Vector3))
	return result


## The portal frame filling [param ring]: its opening at the ring's centre, the way through
## along the ring's axis, pointing away from [param spawn].
static func ring_frame(ring: Dictionary, spawn: Vector3) -> Transform3D:
	var centre := ring[RING_CENTRE] as Vector3
	var through := ring[RING_AXIS] as Vector3
	if through.dot(centre - spawn) < 0.0:
		through = -through
	var up := Vector3.UP
	if absf(through.dot(up)) > MathLimits.NEAR_PARALLEL_DOT:
		up = Vector3.FORWARD
	var facing := Basis.looking_at(through, up)
	return Transform3D(facing, centre - facing.y * Portal.CENTRE_HEIGHT)


## The ring-shaped art object under [param art] whose hole [param marker] is in: its global
## centre ([constant RING_CENTRE]), unit axis ([constant RING_AXIS]) and hole radius
## ([constant RING_RADIUS], measured from the mesh's vertices). Empty when there is none.
static func find_ring(art: Node, marker: Vector3) -> Dictionary:
	for node: Node in art.find_children("*", "CollisionObject3D", true, false):
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			var ring := _ring_around(child as MeshInstance3D, marker)
			if not ring.is_empty():
				return ring
	return {}


static func _ring_around(mesh_node: MeshInstance3D, marker: Vector3) -> Dictionary:
	if mesh_node.mesh == null:
		return {}
	var box := mesh_node.mesh.get_aabb()
	var thin := 0
	for axis: int in 3:
		if box.size[axis] < box.size[thin]:
			thin = axis
	var side_a := box.size[(thin + 1) % 3]
	var side_b := box.size[(thin + 2) % 3]
	if box.size[thin] > RING_FLATNESS * minf(side_a, side_b) \
			or absf(side_a - side_b) > RING_ROUNDNESS * maxf(side_a, side_b):
		return {}
	var xform := mesh_node.global_transform
	var centre := box.get_center()
	var local_marker := xform.affine_inverse() * marker - centre
	if absf(local_marker[thin]) > box.size[thin] * RING_DEPTH_REACH:
		return {}
	local_marker[thin] = 0.0
	var hole := INF
	for vertex: Vector3 in mesh_node.mesh.get_faces():
		var offset := vertex - centre
		offset[thin] = 0.0
		hole = minf(hole, offset.length())
	if hole <= 0.0 or local_marker.length() >= hole:
		return {}
	return {
		RING_CENTRE: xform * centre,
		RING_AXIS: xform.basis[thin].normalized(),
		RING_RADIUS: hole * xform.basis[(thin + 1) % 3].length(),
	}


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
