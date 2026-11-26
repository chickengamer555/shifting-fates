class_name GrappleLineMesh
extends RefCounted
## Builds one grapple line into an [ImmediateMesh]: a thin round rope from the line's start
## (the mesh's origin) to its end, sagging in a shallow curve while slack, and a small hook
## head (a spear tip with three barbs) at the end. The rope is never thinner on screen than
## a given number of pixels, so a far line still reads as a line.

## Sides of the rope's tube and of the hook's tip.
const SIDES := 6
## Segments along a sagging rope (a taut one is a single straight segment).
const SAG_SEGMENTS := 18
## Below this sag (m) the rope is drawn straight.
const MIN_SAG := 0.01
const BARBS := 3
## How far past the anchor the tip pokes (share of the head length).
const TIP_POKE := 0.08
## Where the barbs leave the shaft and how far back they reach (shares of the head length).
const BARB_ROOT := 0.3
const BARB_BACK := 0.95
## Radius of the spear tip's base (share of the head radius).
const TIP_RADIUS := 0.42

var _mesh: ImmediateMesh
var _origin: Vector3
var _camera: Camera3D
var _radius: float
var _min_pixels: float


func _init(mesh: ImmediateMesh, origin: Vector3, camera: Camera3D, radius: float,
		min_pixels: float) -> void:
	_mesh = mesh
	_origin = origin
	_camera = camera
	_radius = radius
	_min_pixels = min_pixels


## Rebuilds the mesh: rope from the origin to [param end] (world) sagging [param sag] metres,
## with a hook head [param head_length] long and [param head_radius] wide at the end.
func draw(end: Vector3, sag: float, head_length: float, head_radius: float) -> void:
	_mesh.clear_surfaces()
	var span := end - _origin
	if span.is_zero_approx():
		return
	var points := _rope_points(span, sag)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(points)
	var tip_dir := (points[points.size() - 1] - points[points.size() - 2]).normalized()
	_head(span, tip_dir, head_length, head_radius)
	_mesh.surface_end()


## Points (local to the origin) along the rope: a straight line, or a shallow parabola that
## hangs [param sag] metres below the chord at its middle.
func _rope_points(span: Vector3, sag: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var direction := span.normalized()
	var hang := Vector3.DOWN - direction * Vector3.DOWN.dot(direction)
	var segments := SAG_SEGMENTS if sag > MIN_SAG and not hang.is_zero_approx() else 1
	hang = hang.normalized() if segments > 1 else Vector3.ZERO
	for i: int in segments + 1:
		var t := float(i) / float(segments)
		points.append(span * t + hang * (sag * 4.0 * t * (1.0 - t)))
	return points


func _tube(points: PackedVector3Array) -> void:
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i: int in points.size():
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var frame := _frame((after - before).normalized())
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		var radius := _radius_at(points[i])
		for k: int in SIDES:
			var angle := TAU * float(k) / float(SIDES)
			var out := frame[0] * cos(angle) + frame[1] * sin(angle)
			ring.append(points[i] + out * radius)
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	for i: int in points.size() - 1:
		for k: int in SIDES:
			var j := (k + 1) % SIDES
			_quad(rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k],
					normals[i][k], normals[i][j], normals[i + 1][j], normals[i + 1][k])


func _head(span: Vector3, direction: Vector3, length: float, radius: float) -> void:
	var frame := _frame(direction)
	var tip := span + direction * length * TIP_POKE
	var base := span - direction * length
	var root := span - direction * length * BARB_ROOT
	var tip_radius := maxf(radius * TIP_RADIUS, _radius_at(span))
	for k: int in SIDES:
		var a := TAU * float(k) / float(SIDES)
		var b := TAU * float(k + 1) / float(SIDES)
		var out_a := frame[0] * cos(a) + frame[1] * sin(a)
		var out_b := frame[0] * cos(b) + frame[1] * sin(b)
		_vertex(tip, direction)
		_vertex(base + out_a * tip_radius, out_a)
		_vertex(base + out_b * tip_radius, out_b)
	for k: int in BARBS:
		var angle := TAU * float(k) / float(BARBS)
		var out := frame[0] * cos(angle) + frame[1] * sin(angle)
		var across := direction.cross(out)
		_vertex(root, across)
		_vertex(root - direction * length * 0.2, across)
		_vertex(span - direction * length * BARB_BACK + out * radius, across)


## Two unit vectors at right angles to [param direction] and to each other.
func _frame(direction: Vector3) -> Array[Vector3]:
	var reference := Vector3.UP
	if absf(direction.dot(reference)) > MathLimits.NEAR_PARALLEL_DOT:
		reference = Vector3.RIGHT
	var side := direction.cross(reference).normalized()
	var frame: Array[Vector3] = [side, direction.cross(side).normalized()]
	return frame


## Tube radius at [param local] (m): the line's radius, or enough for the minimum pixels.
func _radius_at(local: Vector3) -> float:
	if _camera == null:
		return _radius
	var distance := _camera.global_position.distance_to(_origin + local)
	var height := _camera.get_viewport().get_visible_rect().size.y
	if height <= 0.0:
		return _radius
	var per_pixel := 2.0 * distance * tan(deg_to_rad(_camera.fov) * 0.5) / height
	return maxf(_radius, per_pixel * _min_pixels * 0.5)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3,
		nc: Vector3, nd: Vector3) -> void:
	_vertex(a, na)
	_vertex(b, nb)
	_vertex(c, nc)
	_vertex(a, na)
	_vertex(c, nc)
	_vertex(d, nd)


func _vertex(at: Vector3, normal: Vector3) -> void:
	_mesh.surface_set_normal(normal)
	_mesh.surface_add_vertex(at)
