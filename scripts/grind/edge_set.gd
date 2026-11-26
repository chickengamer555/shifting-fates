class_name EdgeSet
extends RefCounted
## The grindable edges ([EdgeTrack]s) of one collision shape, with a spatial grid over their
## segments so "the nearest edge to the feet" looks at a few cells, never at every edge.
##
## The grid is built once, in the rest pose of the shape (see [EdgeTrack]); queries map the
## world point into it through the shape's current transform.

## Side (m) of a grid cell.
const CELL := 4.0

## Every grindable run of this shape.
var tracks: Array[EdgeTrack] = []
## Cell -> packed (track index, segment index) pairs whose segment passes through the cell.
var _grid: Dictionary[Vector3i, PackedInt32Array] = {}


## Builds the set for [param node] from [param polylines] ([method
## EdgeFinder.find_polylines] results in world space, found with the node at [param rest]).
func _init(node: Node3D, polylines: Array[Dictionary], body: RID, rest: Transform3D) -> void:
	for line: Dictionary in polylines:
		var track := EdgeTrack.new(node, line["points"] as PackedVector3Array,
				bool(line["loop"]), rest, body)
		tracks.append(track)
		_index(tracks.size() - 1, track)


## Total metres of grindable edge.
func total_length() -> float:
	var total := 0.0
	for track in tracks:
		total += track.length()
	return total


## The closest point on any track to [param world_pos] within [param radius]:
## [code]{"track": EdgeTrack, "offset": float, "distance": float}[/code], or empty. Points
## closer than [param end_margin] to the end of an open track don't count (the feet must be
## alongside an edge, not past it).
func nearest(world_pos: Vector3, radius: float, end_margin: float) -> Dictionary:
	if tracks.is_empty():
		return {}
	var to_rest := tracks[0].to_world().affine_inverse()
	var local := to_rest * world_pos
	var low := _cell(local - Vector3.ONE * radius)
	var high := _cell(local + Vector3.ONE * radius)
	var best: Dictionary = {}
	var best_distance := radius
	var seen: Dictionary[int, bool] = {}
	for x: int in range(low.x, high.x + 1):
		for y: int in range(low.y, high.y + 1):
			for z: int in range(low.z, high.z + 1):
				var entries: PackedInt32Array = _grid.get(Vector3i(x, y, z), PackedInt32Array())
				for k: int in range(0, entries.size(), 2):
					var track_index := entries[k]
					var segment := entries[k + 1]
					var tag := track_index * 1000003 + segment
					if seen.has(tag):
						continue
					seen[tag] = true
					var track := tracks[track_index]
					var hit := track.closest_on_segment(segment, local)
					if hit.y > best_distance:
						continue
					if not track.is_loop() and (hit.x <= end_margin
							or hit.x >= track.length() - end_margin):
						continue
					best_distance = hit.y
					best = {"track": track, "offset": hit.x, "distance": hit.y}
	return best


func _index(track_index: int, track: EdgeTrack) -> void:
	for segment: int in track.points.size() - 1:
		var a := track.points[segment]
		var b := track.points[segment + 1]
		var low := _cell(a.min(b))
		var high := _cell(a.max(b))
		for x: int in range(low.x, high.x + 1):
			for y: int in range(low.y, high.y + 1):
				for z: int in range(low.z, high.z + 1):
					if not _touches(a, b, Vector3i(x, y, z)):
						continue
					var key := Vector3i(x, y, z)
					var list: PackedInt32Array = _grid.get(key, PackedInt32Array())
					list.append(track_index)
					list.append(segment)
					_grid[key] = list


## True when segment a-b passes within a cell's half-diagonal of the cell's centre (keeps
## long diagonal edges from filling their whole bounding box).
static func _touches(a: Vector3, b: Vector3, cell: Vector3i) -> bool:
	var centre := (Vector3(cell) + Vector3.ONE * 0.5) * CELL
	var ab := b - a
	var span := ab.length_squared()
	var t := 0.0 if span <= 0.0 else clampf((centre - a).dot(ab) / span, 0.0, 1.0)
	return centre.distance_to(a + ab * t) <= CELL * 0.87


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
