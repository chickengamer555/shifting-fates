class_name EdgeFinder
extends RefCounted
## Finds the grindable edges of a triangle mesh: convex creases where two faces meet at a
## sharp angle, such as the top edges of a box, the lip of a ramp or the rim of a disc.
##
## [method find_polylines] welds the triangles' corners, pairs every triangle edge with the
## one triangle that shares it, and keeps an edge when
## [br]- the faces bend by at least [member min_angle_deg] and the crease points outwards
##   (convex: a ridge, never a valley or an inside corner),
## [br]- something can ride on it: the crease faces sideways or up (the bottom edges of a
##   box are not kept) and the edge is no steeper than [member max_slope_deg],
## [br]- it is not tiny: chained runs shorter than [member min_length] are dropped.
## [br]Kept edges are joined end to end into polylines wherever exactly two of them meet and
## turn by less than [member max_turn_deg], so a straight ledge is one run and a round rim
## is one closed loop. Open mesh borders (an edge with one face) and edges shared by more
## than two faces are never kept, so a flat sheet of floor has no edges at all.
## [br]Shapes wider than [member max_extent] (the endless ground and water planes) are
## skipped whole. Pure data in and out: [method faces_of] turns a collision shape into world
## space triangles; [GrindEdges] builds and caches the results per shape.

## Corners closer than this (m) are welded into one.
const WELD := 0.001
## Triangles with an area below this (m²) are ignored.
const MIN_AREA := 1e-8
## Points along a polyline that turn less than this (radians) are dropped.
const STRAIGHT_TURN := 0.01
## Sides of the faceted cylinder used for [CylinderShape3D] (sides bend 7.5°, never sharp).
const CYLINDER_SIDES := 48
## Meshes above this many triangles are skipped (edge keys would overflow 64 bits).
const MAX_TRIANGLES := 600000

## Smallest bend between two faces (degrees) that counts as a grindable edge.
var min_angle_deg: float = 35.0
## Polylines shorter than this (m) are dropped.
var min_length: float = 1.0
## Two edges chain into one polyline when they turn by less than this (degrees).
var max_turn_deg: float = 30.0
## Steepest edge (degrees from level) that can be ridden.
var max_slope_deg: float = 50.0
## The crease's outward direction must point at least this far up (-1..1); 0 = sideways.
var min_up: float = 0.05
## Shapes wider than this (m) on X or Z are skipped (endless ground and water planes).
var max_extent: float = 5000.0


## World-space triangles (3 corners each) of [param shape] under [param xform], or an empty
## array for shapes that have no sharp edges or aren't supported (spheres, capsules, rays).
static func faces_of(shape: Shape3D, xform: Transform3D) -> PackedVector3Array:
	var local := local_faces_of(shape)
	if xform == Transform3D.IDENTITY:
		return local
	var world := PackedVector3Array()
	world.resize(local.size())
	for i: int in local.size():
		world[i] = xform * local[i]
	return world


## Triangles (3 corners each) of [param shape] in its own space; see [method faces_of].
static func local_faces_of(shape: Shape3D) -> PackedVector3Array:
	var local := PackedVector3Array()
	if shape is ConcavePolygonShape3D:
		local = (shape as ConcavePolygonShape3D).get_faces()
	elif shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = (shape as BoxShape3D).size
		local = box.get_faces()
	elif shape is CylinderShape3D:
		var cylinder_shape := shape as CylinderShape3D
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = cylinder_shape.radius
		cylinder.bottom_radius = cylinder_shape.radius
		cylinder.height = cylinder_shape.height
		cylinder.radial_segments = CYLINDER_SIDES
		cylinder.rings = 0
		local = cylinder.get_faces()
	return local


## The grindable polylines of [param faces] (world-space triangles, 3 corners each). Each
## entry is [code]{"points": PackedVector3Array, "loop": bool}[/code]; a loop's last point
## joins back to its first.
func find_polylines(faces: PackedVector3Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var tri_count := faces.size() / 3
	if tri_count == 0 or tri_count > MAX_TRIANGLES or _too_wide(faces):
		return found
	var verts := PackedVector3Array()
	var corners := _weld(faces, verts)
	var normals := _normals(corners, verts, tri_count)
	var edges := _sharp_edges(corners, verts, normals, tri_count)
	for chain: PackedInt32Array in _chains(edges, verts):
		var loop := chain.size() > 3 and chain[0] == chain[chain.size() - 1]
		var points := PackedVector3Array()
		for id: int in chain:
			points.append(verts[id])
		if loop:
			points.remove_at(points.size() - 1)
		points = _simplify(points, loop)
		if _length(points, loop) >= min_length:
			found.append({"points": points, "loop": loop})
	return found


func _too_wide(faces: PackedVector3Array) -> bool:
	var low := faces[0]
	var high := faces[0]
	for p: Vector3 in faces:
		low = low.min(p)
		high = high.max(p)
	return high.x - low.x > max_extent or high.z - low.z > max_extent


## Welds corners closer than [constant WELD]; fills [param verts] and returns, per corner,
## the index of its welded vertex.
func _weld(faces: PackedVector3Array, verts: PackedVector3Array) -> PackedInt32Array:
	var index_of: Dictionary[Vector3i, int] = {}
	var corners := PackedInt32Array()
	corners.resize(faces.size())
	var inv := 1.0 / WELD
	for i: int in faces.size():
		var p := faces[i]
		var key := Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv))
		var id: int = index_of.get(key, -1)
		if id < 0:
			id = verts.size()
			index_of[key] = id
			verts.append(p)
		corners[i] = id
	return corners


## Unit outward normal per triangle (zero for slivers). Outward is decided for the whole
## mesh by its signed volume, so inside-out exports work too.
func _normals(corners: PackedInt32Array, verts: PackedVector3Array, tri_count: int) \
		-> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(tri_count)
	var volume := 0.0
	for t: int in tri_count:
		var a := verts[corners[t * 3]]
		var b := verts[corners[t * 3 + 1]]
		var c := verts[corners[t * 3 + 2]]
		var cross := (b - a).cross(c - a)
		volume += a.dot(b.cross(c))
		if cross.length_squared() * 0.25 > MIN_AREA * MIN_AREA:
			normals[t] = cross.normalized()
	if volume < 0.0:
		for t: int in tri_count:
			normals[t] = -normals[t]
	return normals


## Pairs of welded vertex ids (flat: a0, b0, a1, b1, ...) of every sharp, rideable edge.
func _sharp_edges(corners: PackedInt32Array, verts: PackedVector3Array,
		normals: PackedVector3Array, tri_count: int) -> PackedInt32Array:
	var vert_count := verts.size()
	var slots := tri_count * 3
	var keys := PackedInt64Array()
	keys.resize(slots)
	var used := 0
	for slot: int in slots:
		var t := slot / 3
		if normals[t] == Vector3.ZERO:
			continue
		var a := corners[slot]
		var b := corners[t * 3 + (slot + 1) % 3]
		if a == b:
			continue
		var low := mini(a, b)
		var high := maxi(a, b)
		keys[used] = (int(low) * vert_count + high) * slots + slot
		used += 1
	keys.resize(used)
	keys.sort()
	var min_cos := cos(deg_to_rad(min_angle_deg))
	var max_rise := sin(deg_to_rad(max_slope_deg))
	var edges := PackedInt32Array()
	var i := 0
	while i < used:
		var edge_key := keys[i] / slots
		var j := i + 1
		while j < used and keys[j] / slots == edge_key:
			j += 1
		if j - i == 2:
			var s1 := keys[i] % slots
			var s2 := keys[i + 1] % slots
			if _is_sharp(corners, verts, normals, s1, s2, min_cos, max_rise):
				edges.append(corners[s1])
				edges.append(corners[s1 / 3 * 3 + (s1 + 1) % 3])
		i = j
	return edges


func _is_sharp(corners: PackedInt32Array, verts: PackedVector3Array,
		normals: PackedVector3Array, s1: int, s2: int, min_cos: float, max_rise: float) -> bool:
	var n1 := normals[s1 / 3]
	var n2 := normals[s2 / 3]
	if n1.dot(n2) > min_cos:
		return false
	var a := verts[corners[s1]]
	var b := verts[corners[s1 / 3 * 3 + (s1 + 1) % 3]]
	var along := b - a
	if along.is_zero_approx() or absf(along.normalized().y) > max_rise:
		return false
	# Convex: the far corner of the second face lies behind the first face's plane.
	var far := verts[corners[s2 / 3 * 3 + (s2 + 2) % 3]]
	if n1.dot(far - a) >= -WELD * 0.1:
		return false
	var outward := n1 + n2
	return not outward.is_zero_approx() and outward.normalized().y >= min_up


## Joins edges into chains of vertex ids through every vertex where exactly two edges meet
## and turn gently. A loop's chain ends on the id it starts with.
func _chains(edges: PackedInt32Array, verts: PackedVector3Array) -> Array[PackedInt32Array]:
	var edge_count := edges.size() / 2
	var at: Dictionary[int, PackedInt32Array] = {}
	for e: int in edge_count:
		for id: int in [edges[e * 2], edges[e * 2 + 1]]:
			var list: PackedInt32Array = at.get(id, PackedInt32Array())
			list.append(e)
			at[id] = list
	var used := PackedByteArray()
	used.resize(edge_count)
	var max_turn := deg_to_rad(max_turn_deg)
	var chains: Array[PackedInt32Array] = []
	for e: int in edge_count:
		if used[e] != 0:
			continue
		used[e] = 1
		var chain := PackedInt32Array([edges[e * 2], edges[e * 2 + 1]])
		_extend(chain, edges, at, used, verts, max_turn)
		if chain[0] != chain[chain.size() - 1]:
			chain.reverse()
			_extend(chain, edges, at, used, verts, max_turn)
		chains.append(chain)
	return chains


## Grows [param chain] from its last vertex while the way on is a gentle, unused edge.
func _extend(chain: PackedInt32Array, edges: PackedInt32Array,
		at: Dictionary[int, PackedInt32Array], used: PackedByteArray, verts: PackedVector3Array,
		max_turn: float) -> void:
	while true:
		var tip := chain[chain.size() - 1]
		var prev := chain[chain.size() - 2]
		var list: PackedInt32Array = at[tip]
		if list.size() != 2:
			return
		var next_edge := list[0] if used[list[1]] != 0 else list[1]
		if used[next_edge] != 0:
			return
		var other := edges[next_edge * 2] if edges[next_edge * 2] != tip \
				else edges[next_edge * 2 + 1]
		var d_in := (verts[tip] - verts[prev]).normalized()
		var d_out := (verts[other] - verts[tip]).normalized()
		if d_in.angle_to(d_out) > max_turn:
			return
		used[next_edge] = 1
		chain.append(other)
		if other == chain[0]:
			return


## Drops interior points where the polyline runs straight on.
static func _simplify(points: PackedVector3Array, loop: bool) -> PackedVector3Array:
	if points.size() < 3:
		return points
	var kept := PackedVector3Array()
	var count := points.size()
	for i: int in count:
		var is_end := not loop and (i == 0 or i == count - 1)
		if is_end:
			kept.append(points[i])
			continue
		var prev := points[(i - 1 + count) % count]
		var next := points[(i + 1) % count]
		var d_in := (points[i] - prev).normalized()
		var d_out := (next - points[i]).normalized()
		if d_in.angle_to(d_out) > STRAIGHT_TURN:
			kept.append(points[i])
	return kept


static func _length(points: PackedVector3Array, loop: bool) -> float:
	var total := 0.0
	for i: int in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	if loop and points.size() > 2:
		total += points[points.size() - 1].distance_to(points[0])
	return total
