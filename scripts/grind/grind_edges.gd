class_name GrindEdges
extends RefCounted
## Every sharp edge of the level art, ready to grind: builds an [EdgeSet] per collision shape
## once (with [EdgeFinder]) and finds the nearest edge to a point.
##
## Sets are cached per [CollisionShape3D] and dropped when it leaves the tree. [method watch]
## (called by [GrindAbility]) queues each shape that enters the skater's world;
## [method build_pending] works through the queue on one worker thread ([EdgeJob]), one
## shape at a time so it never crowds the physics jobs sharing the pool, and files each
## result, so a level loading (or being built ahead behind a portal) never stalls a frame.
## A shape asked for before its edges are ready is built on the spot (or its running job
## is waited for). [method nearest] asks the physics server which shapes are within
## reach (one sphere query) and searches only their grids: no mesh is scanned per frame.
## [br]Bodies in the [InvisibleBarrier] group, or with metadata [code]no_grind[/code] set,
## never grind.

## Metadata that keeps a body's edges off the grind list.
const NO_GRIND_META := &"no_grind"
## Most shapes one reach query looks at.
const MAX_SHAPES := 32
## Layers whose bodies carry grindable edges.
const MASK := PhysicsLayers.WORLD_MASK | PhysicsLayers.PHASEABLE_MASK

static var finder: EdgeFinder = EdgeFinder.new()
static var _sphere: SphereShape3D = SphereShape3D.new()
static var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
static var _sets: Dictionary[int, EdgeSet] = {}
static var _pending: Array = []
## The one job in flight and its shape's instance id (0 when idle).
static var _job: EdgeJob = null
static var _job_id: int = 0
## Tasks whose shape left the tree before they finished; reaped once done, never waited on.
static var _orphans: Array[int] = []
static var _watched: Dictionary[int, bool] = {}


## Queues shapes that enter [param tree] from now on (once per tree), and every shape
## already in [param world] under [param root].
static func watch(tree: SceneTree, root: Node, world: World3D) -> void:
	var tree_id := tree.get_instance_id()
	if not _watched.has(tree_id):
		_watched[tree_id] = true
		tree.node_added.connect(_on_node_added)
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.is_inside_tree() and shape.get_world_3d() == world:
			_queue(shape)


## Files the running job once it is done, then starts the next queued shape in
## [param world] (shapes of other worlds, such as portal previews, are left to build if
## ever asked for). Returns true when a job was started.
static func build_pending(world: World3D) -> bool:
	for task: int in _orphans.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_orphans.erase(task)
	if _job != null:
		if not WorkerThreadPool.is_task_completed(_job.task_id):
			return false
		_collect()
	while not _pending.is_empty():
		# Held as a Variant: a queued shape may have been freed since.
		var entry: Variant = _pending.pop_front()
		if not is_instance_valid(entry):
			continue
		var shape := entry as CollisionShape3D
		if not shape.is_inside_tree() \
				or shape.get_world_3d() != world or _sets.has(shape.get_instance_id()):
			continue
		_job_id = shape.get_instance_id()
		_job = _job_for(shape)
		_job.task_id = WorkerThreadPool.add_task(_job.run, false, "grind edges")
		shape.tree_exiting.connect(_forget.bind(_job_id), CONNECT_ONE_SHOT)
		return true
	return false


## True while shapes are queued or a job is running or unreaped.
static func has_pending() -> bool:
	return not _pending.is_empty() or _job != null or not _orphans.is_empty()


## The (cached) edges of [param shape]: waits for its job if one is running, or builds it
## now if it never was queued.
static func edges_for(shape: CollisionShape3D) -> EdgeSet:
	var id := shape.get_instance_id()
	var cached: EdgeSet = _sets.get(id, null)
	if cached != null:
		return cached
	if _job != null and _job_id == id:
		return _collect()
	var job := _job_for(shape)
	job.run()
	shape.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)
	return _file(id, shape, job)


## The edge point nearest [param feet] within [param radius] in [param body]'s world
## ([code]{"track", "offset", "distance"}[/code], or empty). [param body] itself is ignored.
static func nearest(body: CollisionObject3D, feet: Vector3, radius: float,
		end_margin: float) -> Dictionary:
	_sphere.radius = radius
	_query.shape = _sphere
	_query.transform = Transform3D(Basis.IDENTITY, feet)
	_query.collision_mask = MASK
	_query.collide_with_areas = false
	_query.exclude = [body.get_rid()]
	var hits := body.get_world_3d().direct_space_state.intersect_shape(_query, MAX_SHAPES)
	var best: Dictionary = {}
	var best_distance := radius
	for hit: Dictionary in hits:
		var shape := _shape_node(hit)
		if shape == null:
			continue
		var found := edges_for(shape).nearest(feet, best_distance, end_margin)
		if not found.is_empty() and float(found["distance"]) <= best_distance:
			best = found
			best_distance = float(found["distance"])
	return best


static func _shape_node(hit: Dictionary) -> CollisionShape3D:
	var collider := hit.get("collider") as CollisionObject3D
	if collider == null or not _grindable(collider):
		return null
	var owner_id := collider.shape_find_owner(int(hit.get("shape", 0)))
	return collider.shape_owner_get_owner(owner_id) as CollisionShape3D


static func _grindable(body: CollisionObject3D) -> bool:
	if body == null or body is Area3D or body.is_in_group(InvisibleBarrier.GROUP):
		return false
	return not bool(body.get_meta(NO_GRIND_META, false))


static func _queue(shape: CollisionShape3D) -> void:
	if not _sets.has(shape.get_instance_id()):
		_pending.append(shape)


static func _on_node_added(node: Node) -> void:
	var shape := node as CollisionShape3D
	if shape != null:
		_queue(shape)


static func _job_for(shape: CollisionShape3D) -> EdgeJob:
	var faces := PackedVector3Array()
	if shape.shape != null and _grindable(shape.get_parent() as CollisionObject3D):
		faces = EdgeFinder.local_faces_of(shape.shape)
	return EdgeJob.new(faces, shape.global_transform, finder)


## Waits for (if needed) and files the running job.
static func _collect() -> EdgeSet:
	var job := _job
	var id := _job_id
	_job = null
	_job_id = 0
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	var shape := instance_from_id(id) as CollisionShape3D
	if shape == null:
		return null
	return _file(id, shape, job)


static func _file(id: int, shape: CollisionShape3D, job: EdgeJob) -> EdgeSet:
	var body := shape.get_parent() as CollisionObject3D
	var made := EdgeSet.new(shape, job.polylines, body.get_rid() if body != null else RID(),
			job.xform)
	_sets[id] = made
	return made


## Drops shape [param id]'s edges; a job still running is left to finish and be reaped by
## [method build_pending], so a level leaving the tree never waits on a thread.
static func _forget(id: int) -> void:
	if _job != null and _job_id == id:
		_orphans.append(_job.task_id)
		_job = null
		_job_id = 0
	_sets.erase(id)
