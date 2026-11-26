class_name EdgeJob
extends RefCounted
## One shape's edge extraction, run on a worker thread by [GrindEdges]: pure data in
## ([member faces] in the shape's local space, its world [member xform] and the finder's
## settings), [member polylines] out. Touches no nodes, so it is safe off the main thread.

## The shape's triangles in its local space.
var faces: PackedVector3Array
## The shape's global transform when the job was made.
var xform: Transform3D
## Result: [method EdgeFinder.find_polylines] in world space.
var polylines: Array[Dictionary] = []
## WorkerThreadPool task id (-1 when run inline).
var task_id: int = -1
var _finder: EdgeFinder


func _init(local_faces: PackedVector3Array, world: Transform3D, settings: EdgeFinder) -> void:
	faces = local_faces
	xform = world
	_finder = EdgeFinder.new()
	_finder.min_angle_deg = settings.min_angle_deg
	_finder.min_length = settings.min_length
	_finder.max_turn_deg = settings.max_turn_deg
	_finder.max_slope_deg = settings.max_slope_deg
	_finder.min_up = settings.min_up
	_finder.max_extent = settings.max_extent


## Does the work (on whichever thread calls it).
func run() -> void:
	var world := faces
	if xform != Transform3D.IDENTITY:
		world = PackedVector3Array()
		world.resize(faces.size())
		for i: int in faces.size():
			world[i] = xform * faces[i]
	polylines = _finder.find_polylines(world)
