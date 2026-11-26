class_name EdgeTrack
extends GrindTrack
## One grindable run of sharp edges found by [EdgeFinder]: a polyline, open or a loop.
##
## The points are stored where the shape was when its edges were built ("rest" pose). The
## track follows its [member owner_node] from then on, so the edges of art that moves (a ring
## that spins) stay on the art: every query maps through the owner's current transform.

## The collision shape node whose edges these are.
var owner_node: Node3D
## Polyline corners at rest (world space when built).
var points: PackedVector3Array
## Distance (m) along the polyline to each corner; the last entry is the full length.
var offsets: PackedFloat32Array
## The body that owns the shape (excluded from burial checks).
var rid: RID = RID()
var _loop: bool = false
var _rest: Transform3D = Transform3D.IDENTITY


## [param corners] at rest pose [param rest] (the owner's global transform when built).
func _init(node: Node3D, corners: PackedVector3Array, loop: bool, rest: Transform3D,
		body: RID) -> void:
	owner_node = node
	points = corners
	_loop = loop and corners.size() > 2
	_rest = rest
	rid = body
	if _loop:
		points.append(points[0])
	offsets = PackedFloat32Array([0.0])
	for i: int in range(1, points.size()):
		offsets.append(offsets[i - 1] + points[i - 1].distance_to(points[i]))


func length() -> float:
	return offsets[offsets.size() - 1]


func is_loop() -> bool:
	return _loop


func body_rid() -> RID:
	return rid


func label() -> String:
	if owner_node == null or not is_instance_valid(owner_node):
		return "edge"
	var body := owner_node.get_parent()
	return "edge of %s" % (body.name if body != null else owner_node.name)


## Maps rest-pose points to where the owner is now.
func to_world() -> Transform3D:
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return Transform3D.IDENTITY
	return owner_node.global_transform * _rest.affine_inverse()


func closest_offset(world_pos: Vector3) -> float:
	var local := to_world().affine_inverse() * world_pos
	var best := 0.0
	var best_distance := INF
	for i: int in points.size() - 1:
		var hit := closest_on_segment(i, local)
		if hit.y < best_distance:
			best_distance = hit.y
			best = hit.x
	return best


## Offset and distance ([code]Vector2(offset, distance)[/code]) of the point on segment
## [param index] closest to rest-pose point [param local].
func closest_on_segment(index: int, local: Vector3) -> Vector2:
	var a := points[index]
	var b := points[index + 1]
	var ab := b - a
	var span := ab.length_squared()
	var t := 0.0 if span <= 0.0 else clampf((local - a).dot(ab) / span, 0.0, 1.0)
	var on := a + ab * t
	return Vector2(offsets[index] + (offsets[index + 1] - offsets[index]) * t,
			local.distance_to(on))


func position_at(offset: float) -> Vector3:
	var index := _segment(offset)
	var o := _wrap(offset)
	var span := offsets[index + 1] - offsets[index]
	var t := 0.0 if span <= 0.0 else (o - offsets[index]) / span
	return to_world() * points[index].lerp(points[index + 1], clampf(t, 0.0, 1.0))


func tangent_at(offset: float) -> Vector3:
	var index := _segment(offset)
	var along := to_world().basis * (points[index + 1] - points[index])
	return along.normalized() if not along.is_zero_approx() else Vector3.RIGHT


func _wrap(offset: float) -> float:
	var total := length()
	if _loop and total > 0.0:
		return fposmod(offset, total)
	return clampf(offset, 0.0, total)


## Index of the segment holding [param offset].
func _segment(offset: float) -> int:
	var o := _wrap(offset)
	var low := 0
	var high := offsets.size() - 2
	while low < high:
		var mid := (low + high + 1) / 2
		if offsets[mid] <= o:
			low = mid
		else:
			high = mid - 1
	return clampi(low, 0, maxi(offsets.size() - 2, 0))
