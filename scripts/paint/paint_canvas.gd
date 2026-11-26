class_name PaintCanvas
extends RefCounted
## Texture painting on every paintable mesh under a root (a rig, a test scene, ...).
##
## Paintable means a [MeshInstance3D] in group [constant GROUP] whose surfaces have UV0;
## each surface is one [PaintLayer]. A stroke is [method begin_stroke], any number of
## [method stroke_to] hits, then [method end_stroke]: consecutive hits are joined by a
## continuous line, unless they are on different layers or UV islands, or their UVs are much
## further apart than the points on the surface (a seam); then the line breaks there rather
## than streak across the texture. An empty hit lifts the brush. Each stroke or fill is one
## undo step that restores the exact pixels it changed.
## [br]Layers are keyed by [method layer_id], which [Appearance] uses to save and restore
## the painted textures.

## Group of the meshes that can be painted.
const GROUP := &"paintable"
## Metadata on a paintable mesh that overrides its id (default: its path from the root).
const META_PAINT_ID := &"paint_id"
## Separator between a mesh id and a surface index in a layer id.
const SURFACE_SEPARATOR := "#"
## Two hits on one island are joined only while their UV distance (in metres on the surface)
## is at most this many times the distance between the points themselves...
const SEAM_STRETCH := 3.0
## ...plus this many brush radii (so short hops across tiny triangles still join).
const SEAM_SLACK_RADII := 2.0
## Undo steps kept by default.
const DEFAULT_MAX_UNDO := 32

## Brush diameter in metres on the surface.
var brush_size: float = 0.04
## Paint colour.
var color: Color = Color.RED
## When true strokes paint back to the unpainted look instead of [member color].
var erasing: bool = false
## How much of the colour a stroke puts on (0 to 1); a stroke never builds up over itself.
var opacity: float = 1.0
## Edge softness: 0 a crisp edge, 1 fades from the centre of the brush.
var softness: float = 0.0
## Break lines at UV seams (switch off only to see what a seam streak looks like).
var break_seams: bool = true
## Most undo steps kept.
var max_undo: int = DEFAULT_MAX_UNDO
## Undo steps currently available.
var undo_count: int:
	get:
		return _undo.size()

var _root: Node
var _layers: Array[PaintLayer] = []
var _undo: Array[Array] = []
var _stroke_open: bool = false
## Last hit of each line of the open stroke (chain id -> hit); a mirrored brush draws a
## second line (chain 1) beside the first.
var _last_hits: Dictionary[int, Dictionary] = {}
## The paint-bucket fill still pouring ([method begin_fill]) and its layer, or null.
var _fill_job: PaintLayer.FloodJob = null
var _fill_layer: PaintLayer = null


## Collects the paintable meshes under [param scope] (default: [param root]); layer ids
## are paths from [param root]. Layers saved in [param appearance] are loaded and shown.
func _init(root: Node, appearance: Appearance = null, scope: Node = null) -> void:
	_root = root
	for mesh_instance in paintable_meshes(scope if scope != null else root):
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var layer := PaintLayer.create(mesh_instance, surface,
					layer_id(root, mesh_instance, surface))
			if layer == null:
				continue
			_layers.append(layer)
			layer.watch_pose()
			if appearance != null and appearance.has_layer(layer.id):
				var saved := appearance.layer_image(layer.id)
				if saved != null:
					layer.load_image(saved)


## The paintable meshes under [param root] (the root itself included).
static func paintable_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var candidates: Array[Node] = [root]
	candidates.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in candidates:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null \
				and mesh_instance.is_in_group(GROUP):
			found.append(mesh_instance)
	return found


## Stable id of [param surface] of [param mesh_instance]: its [constant META_PAINT_ID]
## metadata or its path from [param root], then [constant SURFACE_SEPARATOR] and the surface.
static func layer_id(root: Node, mesh_instance: MeshInstance3D, surface: int) -> String:
	var mesh_id := str(mesh_instance.get_meta(META_PAINT_ID)) \
			if mesh_instance.has_meta(META_PAINT_ID) else str(root.get_path_to(mesh_instance))
	return "%s%s%d" % [mesh_id, SURFACE_SEPARATOR, surface]


## Starts preparing every layer for painting in the background ([method PaintLayer.warm_up]).
func warm_up() -> void:
	for layer in _layers:
		layer.warm_up()


## Collects finished background preparation; with [param wait] waits for all of it.
func settle_warm_up(wait: bool = false) -> void:
	for layer in _layers:
		layer.settle_warm_up(wait)


## Every layer.
func layers() -> Array[PaintLayer]:
	return _layers


## The layers of [param mesh_instance].
func layers_of(mesh_instance: MeshInstance3D) -> Array[PaintLayer]:
	var found: Array[PaintLayer] = []
	for layer in _layers:
		if layer.mesh_instance == mesh_instance:
			found.append(layer)
	return found


## The paintable mesh named [param mesh_name] (node name or layer mesh id), or null.
func find_mesh(mesh_name: String) -> MeshInstance3D:
	for layer in _layers:
		if layer.mesh_instance.name == mesh_name or layer.id.get_slice(SURFACE_SEPARATOR, 0) \
				== mesh_name:
			return layer.mesh_instance
	return null


## The nearest hit of a global ray on the paintable meshes [param among] (all when empty),
## skipping hidden ones. See [method PaintLayer.pick] for the fields; adds
## [code]world[/code] (the global hit point).
func pick_ray(origin: Vector3, direction: Vector3,
		among: Array[MeshInstance3D] = []) -> Dictionary:
	var best := {}
	var best_distance := INF
	for layer in _layers:
		var mesh_instance := layer.mesh_instance
		if not mesh_instance.is_visible_in_tree():
			continue
		if not among.is_empty() and not among.has(mesh_instance):
			continue
		var to_local := mesh_instance.global_transform.affine_inverse()
		var hit := layer.pick(to_local * origin, to_local.basis * direction)
		if hit.is_empty():
			continue
		var world: Vector3 = mesh_instance.global_transform * (hit["position"] as Vector3)
		var distance := origin.distance_to(world)
		if distance < best_distance:
			best_distance = distance
			hit["world"] = world
			best = hit
	return best


## The hit on [param mesh_instance] at [param local_pos], found by a ray coming in along
## -[param local_normal] (both local to the mesh). When that ray misses, a ray from the same
## outside point towards the mesh's centre is tried. Empty when both miss.
func hit_on(mesh_instance: MeshInstance3D, local_pos: Vector3, local_normal: Vector3) -> Dictionary:
	var normal := local_normal.normalized()
	var reach := maxf(mesh_instance.get_aabb().get_longest_axis_size(), 0.01)
	var hit := _hit_along(mesh_instance, local_pos, local_pos + normal * reach, -normal)
	if hit.is_empty():
		var outside := local_pos + normal * reach
		var to_centre := mesh_instance.get_aabb().get_center() - outside
		if not to_centre.is_zero_approx():
			hit = _hit_along(mesh_instance, local_pos, outside, to_centre.normalized())
	return hit


## Re-reads the pose of skinned meshes (call before picking when the rig may have moved).
func refresh_pose() -> void:
	for layer in _layers:
		layer.refresh_pose()


## True when every skinned layer has recorded the pose its mesh is drawn with (layers that
## are not skinned count as ready).
func has_drawn_pose() -> bool:
	for layer in _layers:
		if layer.mesh_instance.skin != null and not layer.has_drawn_pose():
			return false
	return true


## Opens a stroke (one undo step). Opening one while another is open ends the old one.
func begin_stroke() -> void:
	finish_fill()
	if _stroke_open:
		end_stroke()
	_stroke_open = true
	_last_hits.clear()


## True while a stroke is open.
func is_stroke_open() -> bool:
	return _stroke_open


## Paints up to [param hit]: a line from the previous hit of line [param chain], or a dot
## when the line breaks. An empty [param hit] lifts that line's brush (its next hit starts a
## new line).
func stroke_to(hit: Dictionary, chain: int = 0) -> void:
	if not _stroke_open:
		begin_stroke()
	if hit.is_empty():
		_last_hits.erase(chain)
		return
	var layer := hit["layer"] as PaintLayer
	if not layer.in_stroke():
		layer.begin_stroke()
	var last: Dictionary = _last_hits.get(chain, {})
	var from := last if _joins(last, hit) else hit
	layer.draw_segment(from, hit, brush_size * 0.5, color, erasing, opacity, softness)
	_last_hits[chain] = hit


## Closes the stroke. True when it changed any pixel (and so became an undo step).
func end_stroke() -> bool:
	_stroke_open = false
	_last_hits.clear()
	var records: Array[Dictionary] = []
	for layer in _layers:
		if layer.in_stroke():
			var record := layer.end_stroke()
			if not record.is_empty():
				records.append(record)
	if records.is_empty():
		return false
	_push_undo(records)
	return true


## Floods every surface of [param mesh_instance] with [param fill_color]. One undo step.
func fill_mesh(mesh_instance: MeshInstance3D, fill_color: Color) -> bool:
	finish_fill()
	var targets := layers_of(mesh_instance)
	if targets.is_empty():
		return false
	if _stroke_open:
		end_stroke()
	var records: Array[Dictionary] = []
	for layer in targets:
		layer.begin_stroke()
		layer.fill(fill_color)
		records.append(layer.end_stroke())
	_push_undo(records)
	return true


## Paint bucket: floods the connected area of the colour under [param hit] with
## [param fill_color] (see [method PaintLayer.flood]), all at once. One undo step; false
## when nothing changed.
func fill_connected(hit: Dictionary, fill_color: Color) -> bool:
	if not begin_fill(hit, fill_color):
		return false
	return finish_fill()


## Starts a paint-bucket fill under [param hit] that [method step_fill] spreads over frames
## (the colour pours in). False when the area already has [param fill_color].
func begin_fill(hit: Dictionary, fill_color: Color) -> bool:
	finish_fill()
	if hit.is_empty():
		return false
	if _stroke_open:
		end_stroke()
	var layer := hit["layer"] as PaintLayer
	layer.begin_stroke()
	var job := layer.flood_start(hit["triangle"] as int, hit["uv"] as Vector2, fill_color)
	if job == null:
		layer.end_stroke()
		return false
	_fill_layer = layer
	_fill_job = job
	return true


## True while a fill from [method begin_fill] is still pouring.
func is_filling() -> bool:
	return _fill_job != null


## Pours the open fill for about [param budget_usec] microseconds. True when it finished
## on this call (it is then one undo step).
func step_fill(budget_usec: int) -> bool:
	if _fill_job == null or not _fill_layer.flood_step(_fill_job, budget_usec):
		return false
	_close_fill()
	return true


## Finishes the open fill at once (anything else that changes the paint does this first).
## True when it changed any texel.
func finish_fill() -> bool:
	if _fill_job == null:
		return false
	_fill_layer.flood_step(_fill_job, -1)
	return _close_fill()


func _close_fill() -> bool:
	var record := _fill_layer.end_stroke()
	_fill_job = null
	_fill_layer = null
	if record.is_empty():
		return false
	_push_undo([record])
	return true


## Gives every surface of [param mesh_instance] the finish [param finish_id] ([PaintFinish]).
## One undo step; false when they all wore it already.
func set_finish(mesh_instance: MeshInstance3D, finish_id: StringName) -> bool:
	return set_finish_all([mesh_instance], finish_id)


## Gives every surface of [param meshes] the finish [param finish_id]. One undo step.
func set_finish_all(meshes: Array[MeshInstance3D], finish_id: StringName) -> bool:
	finish_fill()
	if _stroke_open:
		end_stroke()
	var records: Array[Dictionary] = []
	for mesh_instance in meshes:
		for layer in layers_of(mesh_instance):
			var record := layer.set_finish(finish_id)
			if not record.is_empty():
				records.append(record)
	if records.is_empty():
		return false
	_push_undo(records)
	return true


## The colour painted under [param hit] (the unpainted look where nothing is painted).
func color_under(hit: Dictionary) -> Color:
	if hit.is_empty():
		return Color.WHITE
	return (hit["layer"] as PaintLayer).color_at(hit["uv"] as Vector2)


## Takes back the last stroke or fill. False when there is nothing to undo.
func undo() -> bool:
	finish_fill()
	if _stroke_open:
		end_stroke()
	if _undo.is_empty():
		return false
	for record: Dictionary in _undo.pop_back():
		(record["layer"] as PaintLayer).restore(record)
	return true


## Uploads every changed layer to its texture (call once per frame while painting).
func flush() -> void:
	for layer in _layers:
		layer.flush()


## Writes every painted layer into [param appearance] (PNG per layer id).
func store_into(appearance: Appearance) -> void:
	finish_fill()
	flush()
	for layer in _layers:
		if layer.painted:
			appearance.set_layer_png(layer.id, layer.to_png())
			appearance.set_layer_finish(layer.id, layer.finish())


## Gives every painted layer a mipmapped texture for play (after painting is over).
func finalize_for_play() -> void:
	for layer in _layers:
		layer.finalize_for_play()


func _hit_along(mesh_instance: MeshInstance3D, near: Vector3, origin: Vector3,
		direction: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	for layer in layers_of(mesh_instance):
		var hit := layer.pick(origin, direction)
		if hit.is_empty():
			continue
		var distance := (hit["position"] as Vector3).distance_to(near)
		if distance < best_distance:
			best_distance = distance
			hit["world"] = mesh_instance.global_transform * (hit["position"] as Vector3) \
					if mesh_instance.is_inside_tree() else hit["position"] as Vector3
			best = hit
	return best


## True when a line from hit [param previous] to hit [param hit] is drawn as one (same layer
## and UV island, no seam between); false when the line breaks there.
func joins(previous: Dictionary, hit: Dictionary) -> bool:
	return _joins(previous, hit)


func _joins(previous: Dictionary, hit: Dictionary) -> bool:
	if previous.is_empty() or previous["layer"] != hit["layer"]:
		return false
	if not break_seams:
		return true
	var layer := hit["layer"] as PaintLayer
	var triangle: int = hit["triangle"]
	if layer.island_of(previous["triangle"] as int) != layer.island_of(triangle):
		return false
	var on_surface := (previous["world"] as Vector3).distance_to(hit["world"] as Vector3) \
			if previous.has("world") and hit.has("world") \
			else (previous["position"] as Vector3).distance_to(hit["position"] as Vector3)
	var in_uv := layer.uv_distance_m(triangle, previous["uv"] as Vector2, hit["uv"] as Vector2)
	return in_uv <= on_surface * SEAM_STRETCH + brush_size * 0.5 * SEAM_SLACK_RADII


func _push_undo(records: Array[Dictionary]) -> void:
	_undo.append(records)
	while _undo.size() > maxi(max_undo, 1):
		_undo.pop_front()
