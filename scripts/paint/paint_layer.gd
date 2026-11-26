class_name PaintLayer
extends RefCounted
## One paintable surface of a [MeshInstance3D]: its own material, image and texture.
##
## Paint goes into the surface's albedo texture in UV space. Hits come from [method pick]
## (a ray in the mesh's local space) and carry the hit triangle and its UV in texels.
## [method draw_segment] draws an anti-aliased capsule (a line with round caps) between two
## hits, measured in metres on the surface: each triangle's UV-to-surface mapping turns
## texel offsets into metres, so a brush is equally wide on every mesh whatever its texel
## density or UV stretch. Paint stays inside the UV island it was drawn on (no bleed into
## the neighbouring island of the atlas).
## [br]Nothing is created until it is needed: the material, image and texture on the first
## write ([method ensure_image]), the triangle data on the first [method pick]. The shared
## mesh material is never changed; the layer paints on a duplicate set as the surface's
## override material.

## Metadata key on every material a layer made (value: the layer id).
const META_PAINT_MATERIAL := &"paint_layer"
## Metadata key on a paint material: the surface override it replaced (may be null).
const META_SOURCE_MATERIAL := &"paint_source"
## Metadata key on a paint material: the painted [Image] it shows (unmipmapped), so a later
## layer on the same surface carries on from it instead of starting blank.
const META_PAINT_IMAGE := &"paint_image"
## Paint bucket: texels join the flood while every channel is within this of the clicked
## colour.
const FLOOD_TOLERANCE := 0.12
## A fringe texel counts as a mix of the seed colour and the colour beyond it while it is
## within this of the line between them.
const FLOOD_MIX_RESIDUAL := 0.08
## Paint bucket seam crossing: how far inside each triangle (texels) the two sides of a UV
## seam are sampled, the most samples per seam edge and the most crossing rounds.
const SEAM_INSET := 1.5
const SEAM_MAX_SAMPLES := 32
const SEAM_MAX_ROUNDS := 12
## Texels the paint bucket compares at once where they are exactly the clicked colour.
const FLOOD_CHUNK := 16
## A progressive flood looks at the clock every this many texel runs (a run can take a
## fraction of a millisecond, so it looks often to keep to its frame budget).
const FLOOD_CHECK_EVERY := 4
## Texels per metre of surface for a fresh texture, and its size limits (powers of two).
const TEXELS_PER_METRE := 640.0
const MIN_SIZE := 256
const MAX_SIZE := 2048
## The island mask (which UV island owns each texel) is at most this many pixels across.
const MASK_MAX := 256
## Island id of a mask pixel no triangle covers.
const NO_ISLAND := -1
## Rounds of growing each island into the empty texels round it (texture padding).
const MASK_GROW := 2
## Longest brush reach, as a fraction of the texture size (guards degenerate UVs).
const MAX_REACH := 0.25
## Smallest UV area (texels squared) a triangle needs to carry paint.
const MIN_UV_AREA := 1e-6

## Stable id of this layer (see [method PaintCanvas.layer_id]).
var id: String = ""
var mesh_instance: MeshInstance3D
var surface: int = 0
## The painted image (RGBA8, no mipmaps); null until the first write.
var image: Image
## The texture shown on the mesh; null until the first write.
var texture: ImageTexture
## The layer's own material; null until the first write.
var material: BaseMaterial3D
## True once anything was written (or loaded) into the image.
var painted: bool = false

## Unpainted look: a flat colour, or the source texture when it had one.
var _base_color: Color = Color.WHITE
var _base_image: Image
var _size: Vector2i = Vector2i.ZERO
var _dirty: bool = false
## Triangle data, 3 entries per triangle: local positions and UVs in texels.
var _positions: PackedVector3Array
var _uvs: PackedVector2Array
var _islands: PackedInt32Array
var _hit_mesh: TriangleMesh
## Rest-pose (unskinned) positions, 3 per triangle, and their hit mesh (for the mirror).
var _rest_positions: PackedVector3Array
var _rest_hit_mesh: TriangleMesh
var _mask: PackedInt32Array
var _mask_size: int = 0
## The [WorkerThreadPool] task building the island mask in the background ([method warm_up]),
## or -1.
var _mask_task: int = -1
## Stroke state: the image before the stroke, the best coverage per texel so far and the
## rectangle the stroke touched.
var _stroke_base: Image
var _coverage: PackedByteArray
var _stroke_rect: Rect2i = Rect2i()
## UV seams of the surface, for the paint bucket: per edge shared by two triangles whose UVs
## differ, [triangle a, uv a0, uv a1, triangle b, uv b0, uv b1] (uvs in texels, a0/b0 at the
## same corner). Built on the first flood.
var _seams: Array[Array] = []
var _seams_ready: bool = false
## The seams' sample texels for the bucket (see [method _ensure_seam_samples]).
var _seam_samples: PackedInt32Array
var _seam_samples_ready: bool = false
## Skinned meshes: the skeleton-space bone poses as the skeleton last handed them to the skin
## (after its modifiers, e.g. the SkaterPose), and the skeleton they were read from.
var _drawn_poses: Array[Transform3D] = []
var _pose_source: Skeleton3D = null


## A layer for [param surface] of [param mesh_instance], or null when that surface has no
## UV0 or is not made of triangles.
static func create(mesh_instance: MeshInstance3D, surface: int, layer_id: String) -> PaintLayer:
	var mesh := mesh_instance.mesh
	if mesh == null or surface >= mesh.get_surface_count():
		return null
	var arrays := mesh.surface_get_arrays(surface)
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if not uvs is PackedVector2Array or (uvs as PackedVector2Array).is_empty():
		return null
	var layer := PaintLayer.new()
	layer.id = layer_id
	layer.mesh_instance = mesh_instance
	layer.surface = surface
	return layer


## The override a paint material replaced (null when there was none).
static func replaced_material(material: Material) -> Material:
	if is_paint_material(material):
		return material.get_meta(META_SOURCE_MATERIAL, null) as Material
	return material


## True when [param material] was made by a paint layer.
static func is_paint_material(material: Material) -> bool:
	return material != null and material.has_meta(META_PAINT_MATERIAL)


## Size of the paint texture in texels (decided on first use).
func size() -> Vector2i:
	if _size == Vector2i.ZERO:
		_size = _pick_size()
	return _size


## Creates the material, image and texture if they do not exist yet.
func ensure_image() -> void:
	if image != null:
		return
	var shown := _shown_paint_image()
	var current := mesh_instance.get_surface_override_material(surface)
	var shown_finish := PaintFinish.of(current) if is_paint_material(current) \
			else PaintFinish.ORIGINAL
	if shown != null and _size == Vector2i.ZERO:
		_size = shown.get_size()
	var source := _source_material()
	material = (source.duplicate() if source is BaseMaterial3D
			else StandardMaterial3D.new()) as BaseMaterial3D
	material.set_meta(META_PAINT_MATERIAL, id)
	material.set_meta(META_SOURCE_MATERIAL,
			replaced_material(mesh_instance.get_surface_override_material(surface)))
	_base_color = material.albedo_color
	var source_texture := material.albedo_texture
	if source_texture != null:
		_base_color = Color.WHITE
	var dims := size()
	image = Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	image.fill(_base_color)
	if source_texture != null:
		_base_image = _texture_image(source_texture, dims)
		if _base_image != null:
			image.copy_from(_base_image)
	if shown != null:
		image.copy_from(_as_paintable(shown, dims))
		painted = true
	material.set_meta(META_PAINT_IMAGE, image)
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	texture = ImageTexture.create_from_image(image)
	material.albedo_texture = texture
	PaintFinish.apply(material, shown_finish, source)
	mesh_instance.set_surface_override_material(surface, material)


## Replaces the image with [param loaded] (e.g. a saved PNG) and shows it.
func load_image(loaded: Image) -> void:
	_size = loaded.get_size()
	ensure_image()
	var copy := loaded.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGBA8)
	copy.clear_mipmaps()
	image.copy_from(copy)
	painted = true
	_dirty = true
	flush()


## Puts back the material the paint replaced (drops the paint).
func detach() -> void:
	if is_instance_valid(mesh_instance) \
			and mesh_instance.get_surface_override_material(surface) == material:
		mesh_instance.set_surface_override_material(surface, replaced_material(material))


## Uploads the image to the texture if it changed since the last flush.
func flush() -> void:
	if _dirty and texture != null:
		texture.update(image)
	_dirty = false


## Builds a mipmapped texture for play (smoother at a distance than the painting texture).
## Shows [param shown] (RGBA8, no mipmaps) through [param shown_texture] (its mipmapped
## texture) with finish [param finish_id], for play: no image of its own is made, so several
## rigs can share one decoded look. Neither may be written to afterwards; a paint screen
## starts its own image from [param shown] ([constant META_PAINT_IMAGE]).
func show_for_play(shown: Image, shown_texture: ImageTexture, finish_id: StringName) -> void:
	var source := _source_material()
	material = (source.duplicate() if source is BaseMaterial3D
			else StandardMaterial3D.new()) as BaseMaterial3D
	material.set_meta(META_PAINT_MATERIAL, id)
	material.set_meta(META_SOURCE_MATERIAL,
			replaced_material(mesh_instance.get_surface_override_material(surface)))
	material.set_meta(META_PAINT_IMAGE, shown)
	_size = shown.get_size()
	image = shown
	texture = shown_texture
	painted = true
	material.albedo_color = Color.WHITE
	material.albedo_texture = shown_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	PaintFinish.apply(material, finish_id, source)
	mesh_instance.set_surface_override_material(surface, material)


func finalize_for_play() -> void:
	if image == null:
		return
	var shown := image.duplicate() as Image
	shown.generate_mipmaps()
	texture = ImageTexture.create_from_image(shown)
	material.albedo_texture = texture
	PaintFinish.follow_texture(material, texture)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Colour of the texel at [param uv] (texels); the unpainted colour before any write.
func color_at(uv: Vector2) -> Color:
	var dims := size()
	var texel := Vector2i(clampi(int(uv.x), 0, dims.x - 1), clampi(int(uv.y), 0, dims.y - 1))
	if image == null:
		return _source_color()
	return image.get_pixelv(texel)


## Where the ray from [param origin] along [param direction] (both local to the mesh)
## first meets this surface: [code]{layer, triangle, uv, position, normal}[/code] (uv in
## texels, position and normal local), or empty on a miss.
func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	_ensure_triangles()
	if _hit_mesh == null:
		return {}
	var hit := _hit_mesh.intersect_ray(origin, direction)
	if hit.is_empty():
		return {}
	var triangle: int = hit["face_index"]
	var position: Vector3 = hit["position"]
	var base := triangle * 3
	var weights := Geometry3D.get_triangle_barycentric_coords(position, _positions[base],
			_positions[base + 1], _positions[base + 2])
	var uv := _uvs[base] * weights.x + _uvs[base + 1] * weights.y + _uvs[base + 2] * weights.z
	var normal: Vector3 = hit["normal"]
	if normal.dot(direction) > 0.0:
		normal = -normal
	return {"layer": self, "triangle": triangle, "uv": uv, "position": position,
		"normal": normal.normalized()}


## The point of [param hit] (a hit on this layer) in the mesh's rest pose (unskinned, so
## left and right mirror each other there), and the rest triangle's outward normal, both
## local to the mesh.
func rest_point(hit: Dictionary) -> Array[Vector3]:
	_ensure_triangles()
	var base := int(hit["triangle"]) * 3
	var weights := Geometry3D.get_triangle_barycentric_coords(hit["position"] as Vector3,
			_positions[base], _positions[base + 1], _positions[base + 2])
	var point := _rest_positions[base] * weights.x + _rest_positions[base + 1] * weights.y \
			+ _rest_positions[base + 2] * weights.z
	var normal := (_rest_positions[base + 1] - _rest_positions[base]).cross(
			_rest_positions[base + 2] - _rest_positions[base]).normalized()
	var posed := (_positions[base + 1] - _positions[base]).cross(
			_positions[base + 2] - _positions[base])
	# Keep the side the hit faced (the hit normal points back at the viewer).
	if posed.dot(hit["normal"] as Vector3) < 0.0:
		normal = -normal
	return [point, normal]


## Like [method pick], but the ray (local to the mesh) is cast at the rest pose; the hit's
## [code]position[/code] is the matching point as the mesh is posed now.
func pick_rest(origin: Vector3, direction: Vector3) -> Dictionary:
	_ensure_triangles()
	if _rest_hit_mesh == null:
		_rest_hit_mesh = TriangleMesh.new()
		if not _rest_hit_mesh.create_from_faces(_rest_positions):
			_rest_hit_mesh = null
			return {}
	var hit := _rest_hit_mesh.intersect_ray(origin, direction)
	if hit.is_empty():
		return {}
	var triangle: int = hit["face_index"]
	var base := triangle * 3
	var weights := Geometry3D.get_triangle_barycentric_coords(hit["position"] as Vector3,
			_rest_positions[base], _rest_positions[base + 1], _rest_positions[base + 2])
	var uv := _uvs[base] * weights.x + _uvs[base + 1] * weights.y + _uvs[base + 2] * weights.z
	var position := _positions[base] * weights.x + _positions[base + 1] * weights.y \
			+ _positions[base + 2] * weights.z
	var normal := (_positions[base + 1] - _positions[base]).cross(
			_positions[base + 2] - _positions[base]).normalized()
	return {"layer": self, "triangle": triangle, "uv": uv, "position": position,
		"normal": normal, "rest_position": hit["position"]}


## Re-reads the posed triangles of a skinned mesh before the next [method pick] (its
## skeleton may have moved). Islands and the mask only depend on the UVs, so they stay.
## The pose is the one the mesh is drawn with: the skeleton restores its unmodified pose
## right after the modifiers run, so it is recorded on [signal Skeleton3D.skeleton_updated]
## (see [method watch_pose]).
func refresh_pose() -> void:
	if mesh_instance.skin != null:
		watch_pose()
		_hit_mesh = null


## True once a drawn pose of a skinned mesh's skeleton has been recorded.
func has_drawn_pose() -> bool:
	return not _drawn_poses.is_empty()


## Starts recording the drawn pose of a skinned mesh's skeleton each time it updates. Safe
## to call again; does nothing for meshes that are not skinned or not in the tree.
func watch_pose() -> void:
	var skeleton := _skeleton()
	if skeleton == null or skeleton == _pose_source:
		return
	if _pose_source != null and is_instance_valid(_pose_source) \
			and _pose_source.skeleton_updated.is_connected(_on_skeleton_updated):
		_pose_source.skeleton_updated.disconnect(_on_skeleton_updated)
	_pose_source = skeleton
	_drawn_poses.clear()
	skeleton.skeleton_updated.connect(_on_skeleton_updated)


## UV island of [param triangle].
func island_of(triangle: int) -> int:
	_ensure_triangles()
	return _islands[triangle]


## Metres on the surface between the UVs of two hits on [param triangle]'s island, measured
## with that triangle's mapping.
func uv_distance_m(triangle: int, from_uv: Vector2, to_uv: Vector2) -> float:
	var metric := _texel_metric(triangle)
	return metric.basis_xform(to_uv - from_uv).length()


## Starts a stroke: later writes blend over the image as it is now.
func begin_stroke() -> void:
	ensure_image()
	_stroke_base = image.duplicate() as Image
	_coverage = PackedByteArray()
	_coverage.resize(image.get_width() * image.get_height())
	_stroke_rect = Rect2i()


## True while a stroke is open on this layer.
func in_stroke() -> bool:
	return _stroke_base != null


## Ends the stroke. Returns the undo record (the touched rectangle as it was before the
## stroke), or an empty Dictionary when nothing changed.
func end_stroke() -> Dictionary:
	var record := {}
	if _stroke_base != null and _stroke_rect.has_area():
		record = {"layer": self, "rect": _stroke_rect,
			"pixels": _stroke_base.get_region(_stroke_rect)}
	_stroke_base = null
	_coverage = PackedByteArray()
	_stroke_rect = Rect2i()
	return record


## The finish this surface wears ([constant PaintFinish.ORIGINAL] before any paint).
func finish() -> StringName:
	return PaintFinish.of(material)


## Gives the surface the finish [param finish_id] (see [PaintFinish]). Returns an undo
## record that puts the old finish back, or an empty Dictionary when it already wore it.
func set_finish(finish_id: StringName) -> Dictionary:
	ensure_image()
	var before := finish()
	if before == finish_id:
		return {}
	PaintFinish.apply(material, finish_id, _source_material())
	painted = true
	return {"layer": self, "finish": before}


## Puts back the pixels (or the finish) of an undo record from [method end_stroke] or
## [method set_finish].
func restore(record: Dictionary) -> void:
	if record.has("finish"):
		PaintFinish.apply(material, record["finish"] as StringName, _source_material())
		return
	var rect: Rect2i = record["rect"]
	image.blit_rect(record["pixels"] as Image, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	_dirty = true


## Draws a line [param radius_m] metres wide each side from hit [param from] to hit
## [param to] (both on this layer, same island) in [param color], or back to the unpainted
## look when [param erase]. Must be inside [method begin_stroke] / [method end_stroke].
## [param opacity] scales how much of the colour goes on (a stroke never builds up over
## itself); [param softness] fades the edge from that fraction of the radius inwards.
func draw_segment(from: Dictionary, to: Dictionary, radius_m: float, color: Color,
		erase: bool, opacity: float = 1.0, softness: float = 0.0) -> void:
	_ensure_mask()
	var triangle: int = to["triangle"]
	var metric := _texel_metric(triangle)
	var area := absf(metric.determinant())
	if area < MIN_UV_AREA * MIN_UV_AREA or radius_m <= 0.0:
		return
	var texel_m := sqrt(area)
	var inverse := metric.affine_inverse()
	var reach := radius_m + texel_m
	var max_reach := float(maxi(image.get_width(), image.get_height())) * MAX_REACH
	var extent := Vector2(
		minf(reach * Vector2(inverse.x.x, inverse.y.x).length(), max_reach),
		minf(reach * Vector2(inverse.x.y, inverse.y.y).length(), max_reach))
	var start: Vector2 = from["uv"]
	var end: Vector2 = to["uv"]
	var low := Vector2i((start.min(end) - extent).floor())
	var high := Vector2i((start.max(end) + extent).ceil())
	var rect := _clip(Rect2i(low, high - low))
	if not rect.has_area():
		return
	var island := _islands[triangle]
	var span := metric.basis_xform(end - start)
	var span_length_sq := span.length_squared()
	var width := image.get_width()
	var mask_scale := Vector2(_mask_size, _mask_size) / Vector2(image.get_size())
	var strength := clampf(opacity, 0.0, 1.0)
	var soft_from := radius_m * (1.0 - clampf(softness, 0.0, 1.0))
	var touched := false
	for y in range(rect.position.y, rect.end.y):
		var mask_row := mini(int(y * mask_scale.y), _mask_size - 1) * _mask_size
		for x in range(rect.position.x, rect.end.x):
			if _mask[mask_row + mini(int(x * mask_scale.x), _mask_size - 1)] != island:
				continue
			var offset := metric.basis_xform(Vector2(x + 0.5, y + 0.5) - start)
			var along := 0.0
			if span_length_sq > 0.0:
				along = clampf(offset.dot(span) / span_length_sq, 0.0, 1.0)
			var distance := (offset - span * along).length()
			var cover := clampf((radius_m - distance) / texel_m + 0.5, 0.0, 1.0)
			if soft_from < radius_m:
				cover = minf(cover, 1.0 - smoothstep(soft_from, radius_m, distance))
			var level := int(cover * strength * 255.0)
			var index := y * width + x
			if level <= _coverage[index]:
				continue
			_coverage[index] = level
			var target := color
			if erase:
				target = _base_image.get_pixel(x, y) if _base_image != null else _base_color
			image.set_pixel(x, y, _stroke_base.get_pixel(x, y).lerp(target, level / 255.0))
			touched = true
	if touched:
		_stroke_rect = rect if not _stroke_rect.has_area() else _stroke_rect.merge(rect)
		painted = true
		_dirty = true


## Floods the whole surface with [param color] (inside an open stroke, so it can be undone).
func fill(color: Color) -> void:
	image.fill(color)
	_stroke_rect = Rect2i(Vector2i.ZERO, image.get_size())
	painted = true
	_dirty = true


## Paint bucket: floods the area of one colour round [param uv] (texels) on
## [param triangle]'s island with [param color], crossing the surface's UV seams into the
## islands it joins on the model, and recolours the anti-aliased texels along its edge the
## same way. Must be inside [method begin_stroke] / [method end_stroke]. False when nothing
## changed (also when the area already has that colour). Runs to the end at once; see
## [method flood_start] for a flood spread over frames.
func flood(triangle: int, uv: Vector2, color: Color) -> bool:
	var job := flood_start(triangle, uv, color)
	if job == null:
		return false
	flood_step(job, -1)
	return job.changed


## Starts a paint-bucket flood (see [method flood]) to be run by [method flood_step], or
## returns null when the clicked area already has [param color].
func flood_start(triangle: int, uv: Vector2, color: Color) -> FloodJob:
	_ensure_mask()
	_ensure_seams()
	_ensure_seam_samples()
	var width := image.get_width()
	var height := image.get_height()
	var data := image.get_data()
	var start := _texel(uv)
	var at := (start.y * width + start.x) * 4
	var seed := PackedInt32Array([data[at], data[at + 1], data[at + 2]])
	var fill := PackedInt32Array([color.r8, color.g8, color.b8])
	var tolerance := int(FLOOD_TOLERANCE * 255.0)
	if absi(fill[0] - seed[0]) <= tolerance and absi(fill[1] - seed[1]) <= tolerance \
			and absi(fill[2] - seed[2]) <= tolerance:
		return null
	var job := FloodJob.new()
	job.width = width
	job.height = height
	job.data = data
	job.seed = seed
	job.fill = fill
	job.color = Color(color, 1.0)
	job.tolerance = tolerance
	job.filled.resize(width * height)
	job.empty_chunk.resize(FLOOD_CHUNK)
	for _i in range(FLOOD_CHUNK):
		job.seed_chunk.append_array(data.slice(at, at + 4))
	job.mask_columns.resize(width)
	for x in range(width):
		job.mask_columns[x] = mini(int(x * float(_mask_size) / width), _mask_size - 1)
	job.mask_rows.resize(height)
	for y in range(height):
		job.mask_rows[y] = mini(int(y * float(_mask_size) / height), _mask_size - 1) \
				* _mask_size
	var island := _islands[triangle]
	var under := _mask[job.mask_rows[start.y] + job.mask_columns[start.x]]
	if under != island and under != NO_ISLAND:
		# The coarse island mask can give an edge texel to the neighbouring island.
		island = under
	job.pending = [Vector3i(start.x, start.y, island)]
	return job


## Runs [param job] for about [param budget_usec] microseconds (negative: to the end),
## painting what it has filled so far. True once it is done: the area is filled and its
## edge blended.
func flood_step(job: FloodJob, budget_usec: int) -> bool:
	if job.done:
		return true
	var deadline := -1 if budget_usec < 0 else Time.get_ticks_usec() + budget_usec
	while true:
		var drained := _flood_seeds(job, deadline)
		_apply_spans(job)
		if not drained:
			return false
		job.round += 1
		var more: Array[Vector3i] = []
		if job.round < SEAM_MAX_ROUNDS:
			more = _seam_seeds(job)
		if more.is_empty():
			break
		job.pending = more
	_blend_fringe(job, job.fill)
	job.done = true
	return true


## Paints the spans [param job] found since the last call.
func _apply_spans(job: FloodJob) -> void:
	var spans := job.spans
	if job.applied >= spans.size():
		return
	var low := Vector2i(job.width, job.height)
	var high := Vector2i(-1, -1)
	for i in range(job.applied, spans.size(), 3):
		var y := spans[i]
		image.fill_rect(Rect2i(spans[i + 1], y, spans[i + 2] - spans[i + 1] + 1, 1), job.color)
		low = Vector2i(mini(low.x, spans[i + 1]), mini(low.y, y))
		high = Vector2i(maxi(high.x, spans[i + 2]), maxi(high.y, y))
	job.applied = spans.size()
	job.changed = true
	var rect := _clip(Rect2i(low - Vector2i.ONE, high - low + Vector2i(3, 3)))
	_stroke_rect = rect if not _stroke_rect.has_area() else _stroke_rect.merge(rect)
	painted = true
	_dirty = true


## The painted image as PNG bytes.
func to_png() -> PackedByteArray:
	return image.save_png_to_buffer() if image != null else PackedByteArray()


func _texel(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(int(uv.x), 0, image.get_width() - 1),
			clampi(int(uv.y), 0, image.get_height() - 1))


## Scanline flood of every seed (x, y, island) over the texels of its island near the seed
## colour. Records the filled spans and the texels just outside them (fringe candidates,
## with the direction away from the flood). Written as one loop on purpose: it visits
## every texel of the area, so calls inside it would cost seconds on a large part.
@warning_ignore("integer_division")
func _flood_seeds(job: FloodJob, deadline: int) -> bool:
	var width := job.width
	var height := job.height
	var data := job.data
	var filled := job.filled
	var columns := job.mask_columns
	var rows := job.mask_rows
	var mask := _mask
	var s0 := job.seed[0]
	var s1 := job.seed[1]
	var s2 := job.seed[2]
	var tol := job.tolerance
	var spans := job.spans
	var fringe := job.fringe
	var stack := job.stack
	var island := job.island
	var pops := 0
	var drained := true
	while true:
		if stack.is_empty():
			if job.pending.is_empty():
				break
			var seed_point: Vector3i = job.pending.pop_back()
			island = seed_point.z
			stack.append(seed_point.y * width + seed_point.x)
			continue
		pops += 1
		if deadline >= 0 and pops % FLOOD_CHECK_EVERY == 0 and Time.get_ticks_usec() > deadline:
			drained = false
			break
		var index := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if filled[index] == 1:
			continue
		var y := index / width
		var x := index - y * width
		var row := y * width
		var mask_row := rows[y]
		var p := index * 4
		if mask[mask_row + columns[x]] != island or absi(data[p] - s0) > tol \
				or absi(data[p + 1] - s1) > tol or absi(data[p + 2] - s2) > tol:
			continue
		var left := x
		while left > 0:
			if left >= FLOOD_CHUNK and _chunk_joins(job, filled, row, left - FLOOD_CHUNK, mask_row,
					island):
				left -= FLOOD_CHUNK
				continue
			var i := row + left - 1
			p = i * 4
			if filled[i] == 1 or mask[mask_row + columns[left - 1]] != island \
					or absi(data[p] - s0) > tol or absi(data[p + 1] - s1) > tol \
					or absi(data[p + 2] - s2) > tol:
				if filled[i] == 0:
					fringe.append(i)
					fringe.append(-1)
				break
			left -= 1
		var right := x
		while right < width - 1:
			if right + FLOOD_CHUNK < width and _chunk_joins(job, filled, row, right + 1, mask_row,
					island):
				right += FLOOD_CHUNK
				continue
			var i := row + right + 1
			p = i * 4
			if filled[i] == 1 or mask[mask_row + columns[right + 1]] != island \
					or absi(data[p] - s0) > tol or absi(data[p + 1] - s1) > tol \
					or absi(data[p + 2] - s2) > tol:
				if filled[i] == 0:
					fringe.append(i)
					fringe.append(1)
				break
			right += 1
		for fx in range(left, right + 1):
			filled[row + fx] = 1
		spans.append(y)
		spans.append(left)
		spans.append(right)
		for step: int in [-1, 1]:
			var ny := y + step
			if ny < 0 or ny >= height:
				continue
			var next_row := ny * width
			var next_mask := rows[ny]
			var open := false
			var fx := left
			while fx <= right:
				if fx + FLOOD_CHUNK - 1 <= right and _chunk_joins(job, filled, next_row, fx,
						next_mask, island):
					if not open:
						stack.append(next_row + fx)
					open = true
					fx += FLOOD_CHUNK
					continue
				var i := next_row + fx
				var joins := false
				if filled[i] == 0 and mask[next_mask + columns[fx]] == island:
					p = i * 4
					joins = absi(data[p] - s0) <= tol and absi(data[p + 1] - s1) <= tol \
							and absi(data[p + 2] - s2) <= tol
					if not joins:
						fringe.append(i)
						fringe.append(step * width)
				if joins and not open:
					stack.append(i)
				open = joins
				fx += 1
	job.filled = filled
	job.spans = spans
	job.fringe = fringe
	job.stack = stack
	job.island = island
	return drained


## True when the [constant FLOOD_CHUNK] texels from column [param x] of the row starting at
## [param row] are all unfilled, exactly the seed colour and on [param island].
func _chunk_joins(job: FloodJob, filled: PackedByteArray, row: int, x: int, mask_row: int,
		island: int) -> bool:
	var i := row + x
	if filled.slice(i, i + FLOOD_CHUNK) != job.empty_chunk:
		return false
	for cell in range(job.mask_columns[x], job.mask_columns[x + FLOOD_CHUNK - 1] + 1):
		if _mask[mask_row + cell] != island:
			return false
	return job.data.slice(i * 4, (i + FLOOD_CHUNK) * 4) == job.seed_chunk


## Texels just across a UV seam from the flood (where the model carries on) that are near
## the seed colour and not filled yet, as (x, y, island).
@warning_ignore("integer_division")
func _seam_seeds(job: FloodJob) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	var samples := _seam_samples
	var filled := job.filled
	var width := job.width
	for k in range(0, samples.size(), 4):
		var index_a := samples[k]
		var index_b := samples[k + 1]
		var on_a := filled[index_a]
		var on_b := filled[index_b]
		if on_a == 1 and on_b != 1 and job.near(index_b):
			found.append(Vector3i(index_b % width, index_b / width, samples[k + 3]))
		elif on_b == 1 and on_a != 1 and job.near(index_a):
			found.append(Vector3i(index_a % width, index_a / width, samples[k + 2]))
	return found


## Samples the two sides of every UV seam once: texel index on side a, on side b, island
## of a, island of b (repeated pairs dropped).
func _ensure_seam_samples() -> void:
	if _seam_samples_ready:
		return
	_seam_samples_ready = true
	var width := image.get_width()
	var seen := {}
	for seam: Array in _seams:
		var tri_a: int = seam[0]
		var tri_b: int = seam[3]
		var a0: Vector2 = seam[1]
		var a1: Vector2 = seam[2]
		var b0: Vector2 = seam[4]
		var b1: Vector2 = seam[5]
		var centre_a := _uv_centre(tri_a)
		var centre_b := _uv_centre(tri_b)
		var count := clampi(int(maxf(a0.distance_to(a1), b0.distance_to(b1)) * 0.5), 1,
				SEAM_MAX_SAMPLES)
		for i in range(count + 1):
			var t := (float(i) + 0.5) / float(count + 1)
			var on_a := _texel(_inset(a0.lerp(a1, t), centre_a))
			var on_b := _texel(_inset(b0.lerp(b1, t), centre_b))
			var index_a := on_a.y * width + on_a.x
			var index_b := on_b.y * width + on_b.x
			var key := Vector2i(index_a, index_b)
			if seen.has(key):
				continue
			seen[key] = true
			_seam_samples.append_array(PackedInt32Array([index_a, index_b, _islands[tri_a],
					_islands[tri_b]]))


func _uv_centre(triangle: int) -> Vector2:
	var base := triangle * 3
	return (_uvs[base] + _uvs[base + 1] + _uvs[base + 2]) / 3.0


static func _inset(point: Vector2, centre: Vector2) -> Vector2:
	var inward := centre - point
	var length := inward.length()
	if length <= SEAM_INSET:
		return centre
	return point + inward / length * SEAM_INSET


## Recolours the texels just outside the flood that are anti-aliased mixes of the seed
## colour and the colour beyond them (read one texel further out): each gets the share of
## the change its seed part calls for. Texels of a different colour are left alone.
@warning_ignore("integer_division")
func _blend_fringe(job: FloodJob, fill: PackedInt32Array) -> void:
	var width := job.width
	var count := job.width * job.height
	var data := job.data
	var seed := job.seed
	var residual_limit := FLOOD_MIX_RESIDUAL * 255.0
	for k in range(0, job.fringe.size(), 2):
		var index := job.fringe[k]
		if job.filled[index] != 0:
			continue
		job.filled[index] = 2
		var step := job.fringe[k + 1]
		var beyond := index + step
		if beyond < 0 or beyond >= count or job.filled[beyond] == 1:
			continue
		if absi(step) == 1 and int(beyond / width) != int(index / width):
			continue
		var p := index * 4
		var q := beyond * 4
		var to_other := Vector3(data[q] - seed[0], data[q + 1] - seed[1], data[q + 2] - seed[2])
		var span := to_other.length_squared()
		if span < 1.0:
			continue
		var mine := Vector3(data[p] - seed[0], data[p + 1] - seed[1], data[p + 2] - seed[2])
		var share := mine.dot(to_other) / span
		if share <= 0.0 or share >= 1.0:
			continue
		if (mine - to_other * share).length() > residual_limit:
			continue
		var weight := 1.0 - share
		var x := index % width
		var y := index / width
		image.set_pixel(x, y, Color8(
				clampi(roundi(data[p] + (fill[0] - seed[0]) * weight), 0, 255),
				clampi(roundi(data[p + 1] + (fill[1] - seed[1]) * weight), 0, 255),
				clampi(roundi(data[p + 2] + (fill[2] - seed[2]) * weight), 0, 255),
				data[p + 3]))


## State of one paint-bucket flood: the image bytes as they were (read only), the texels
## filled so far (1 filled, 2 fringe handled), the filled spans (y, left, right), the
## fringe candidates (texel, step away from the flood) and where the scan stands.
class FloodJob:
	extends RefCounted
	var done: bool = false
	## True once any texel was filled.
	var changed: bool = false
	var color: Color = Color.WHITE
	var fill: PackedInt32Array
	var stack: PackedInt32Array
	var island: int = 0
	var pending: Array[Vector3i] = []
	var round: int = 0
	## Span entries already painted into the image.
	var applied: int = 0
	var width: int = 0
	var height: int = 0
	var data: PackedByteArray
	var seed: PackedInt32Array
	var tolerance: int = 0
	var filled: PackedByteArray
	var mask_columns: PackedInt32Array
	var mask_rows: PackedInt32Array
	var spans: PackedInt32Array
	var fringe: PackedInt32Array
	## [constant FLOOD_CHUNK] copies of the seed texel's bytes, and as many zero bytes: a
	## run of texels exactly the seed colour is matched with one native compare.
	var seed_chunk: PackedByteArray
	var empty_chunk: PackedByteArray

	func near(index: int) -> bool:
		var p := index * 4
		return absi(data[p] - seed[0]) <= tolerance and absi(data[p + 1] - seed[1]) \
				<= tolerance and absi(data[p + 2] - seed[2]) <= tolerance


## Finds the surface's UV seams (edges two triangles share on the model whose UVs differ).
func _ensure_seams() -> void:
	if _seams_ready:
		return
	_seams_ready = true
	_ensure_triangles()
	var arrays := mesh_instance.mesh.surface_get_arrays(surface)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := indices as PackedInt32Array if indices is PackedInt32Array \
			else PackedInt32Array()
	if order.is_empty():
		order.resize(rest.size())
		for i in range(rest.size()):
			order[i] = i
	var edges: Dictionary = {}
	for t in range(int(order.size() / 3.0)):
		for corner in range(3):
			var first := t * 3 + corner
			var second := t * 3 + (corner + 1) % 3
			var pa := rest[order[first]]
			var pb := rest[order[second]]
			var flipped := pb < pa
			var key: Array[Vector3] = [pa, pb]
			if flipped:
				key = [pb, pa]
			var low_uv := _uvs[second] if flipped else _uvs[first]
			var high_uv := _uvs[first] if flipped else _uvs[second]
			if not edges.has(key):
				edges[key] = [t, low_uv, high_uv]
				continue
			var other: Array = edges[key]
			if other.size() != 3:
				continue
			if (other[1] as Vector2).is_equal_approx(low_uv) \
					and (other[2] as Vector2).is_equal_approx(high_uv):
				continue
			_seams.append([other[0], other[1], other[2], t, low_uv, high_uv])
			edges[key] = [other[0], other[1], other[2], t]


func _source_material() -> Material:
	var override := replaced_material(mesh_instance.get_surface_override_material(surface))
	if override != null:
		return override
	if mesh_instance.material_override != null:
		return mesh_instance.material_override
	return mesh_instance.mesh.surface_get_material(surface)


func _source_color() -> Color:
	var source := _source_material() as BaseMaterial3D
	return source.albedo_color if source != null else Color.WHITE


## The painted image the surface shows now (a paint material made by an earlier layer), or
## null when it shows no paint.
func _shown_paint_image() -> Image:
	var current := mesh_instance.get_surface_override_material(surface)
	if not is_paint_material(current):
		return null
	var shown: Variant = current.get_meta(META_PAINT_IMAGE, null)
	return shown as Image if shown is Image else null


## [param picture] as an RGBA8 image of [param dims] without mipmaps (a copy).
static func _as_paintable(picture: Image, dims: Vector2i) -> Image:
	var copy := picture.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_size() != dims:
		copy.resize(dims.x, dims.y, Image.INTERPOLATE_BILINEAR)
	return copy


## Texture size: the paint the surface already shows, else the source texture's, else from
## the mesh's surface area.
func _pick_size() -> Vector2i:
	var shown := _shown_paint_image()
	if shown != null:
		return shown.get_size()
	var source := _source_material() as BaseMaterial3D
	if source != null and source.albedo_texture != null:
		var texture_size := Vector2i(source.albedo_texture.get_size())
		return texture_size.clamp(Vector2i(MIN_SIZE, MIN_SIZE), Vector2i(MAX_SIZE, MAX_SIZE))
	var box := mesh_instance.mesh.get_aabb()
	var scale := mesh_instance.global_basis.get_scale() if mesh_instance.is_inside_tree() \
			else mesh_instance.basis.get_scale()
	var dims := box.size * scale.abs()
	var area := 2.0 * (dims.x * dims.y + dims.y * dims.z + dims.x * dims.z)
	var side := clampi(nearest_po2(int(sqrt(area) * TEXELS_PER_METRE)), MIN_SIZE, MAX_SIZE)
	return Vector2i(side, side)


## The source texture as a paintable image of [param dims]. Its material tint is dropped,
## so painted colours show as picked.
static func _texture_image(source: Texture2D, dims: Vector2i) -> Image:
	var picture := source.get_image()
	if picture == null:
		return null
	picture = picture.duplicate() as Image
	if picture.is_compressed():
		picture.decompress()
	picture.clear_mipmaps()
	picture.convert(Image.FORMAT_RGBA8)
	if picture.get_size() != dims:
		picture.resize(dims.x, dims.y, Image.INTERPOLATE_BILINEAR)
	return picture


func _clip(rect: Rect2i) -> Rect2i:
	return rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))


## Maps a texel offset on [param triangle] to metres in the triangle's plane (world scale).
func _texel_metric(triangle: int) -> Transform2D:
	_ensure_triangles()
	var base := triangle * 3
	var scale_basis := mesh_instance.global_basis if mesh_instance.is_inside_tree() \
			else mesh_instance.basis
	var edge_a := scale_basis * (_positions[base + 1] - _positions[base])
	var edge_b := scale_basis * (_positions[base + 2] - _positions[base])
	var length_a := edge_a.length()
	if is_zero_approx(length_a):
		return Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	var axis := edge_a / length_a
	var flat_a := Vector2(length_a, 0.0)
	var flat_b := Vector2(edge_b.dot(axis), (edge_b - axis * edge_b.dot(axis)).length())
	var uv_a := _uvs[base + 1] - _uvs[base]
	var uv_b := _uvs[base + 2] - _uvs[base]
	var uv_frame := Transform2D(uv_a, uv_b, Vector2.ZERO)
	if absf(uv_frame.determinant()) < MIN_UV_AREA:
		return Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	return Transform2D(flat_a, flat_b, Vector2.ZERO) * uv_frame.affine_inverse()


## Reads the surface's triangles (posed, for skinned meshes) and groups them into islands.
func _ensure_triangles() -> void:
	if _hit_mesh != null or not is_instance_valid(mesh_instance):
		return
	var arrays := mesh_instance.mesh.surface_get_arrays(surface)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vertices := rest
	var skeleton := _skeleton()
	if skeleton != null:
		watch_pose()
		vertices = _posed(vertices, arrays, skeleton)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := indices as PackedInt32Array if indices is PackedInt32Array \
			else PackedInt32Array()
	if order.is_empty():
		order.resize(vertices.size())
		for i in range(vertices.size()):
			order[i] = i
	var texels := Vector2(size())
	var fresh := _islands.is_empty()
	_positions = PackedVector3Array()
	_uvs = PackedVector2Array()
	_positions.resize(order.size())
	_rest_positions = PackedVector3Array()
	_rest_positions.resize(order.size())
	_uvs.resize(order.size())
	for i in range(order.size()):
		_positions[i] = vertices[order[i]]
		_rest_positions[i] = rest[order[i]]
		_uvs[i] = uvs[order[i]] * texels
	if fresh:
		_islands = _find_islands(order, vertices, uvs)
	_hit_mesh = TriangleMesh.new()
	if not _hit_mesh.create_from_faces(_positions):
		_hit_mesh = null


## The skeleton deforming this mesh, or null when it is not skinned.
func _skeleton() -> Skeleton3D:
	if mesh_instance.skin == null or not mesh_instance.is_inside_tree():
		return null
	return mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D


## [param vertices] in the skeleton's current pose (linear blend skinning on the CPU, so it
## works before the renderer has registered the skin). Skeleton space is the mesh's space
## here, as for any skinned mesh that sits on its skeleton.
func _posed(vertices: PackedVector3Array, arrays: Array, skeleton: Skeleton3D) \
		-> PackedVector3Array:
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	if not bones is PackedInt32Array or not weights is PackedFloat32Array:
		return vertices
	var bone_ids := bones as PackedInt32Array
	var bone_weights := weights as PackedFloat32Array
	var skin := mesh_instance.skin
	var binds: Array[Transform3D] = []
	for bind in range(skin.get_bind_count()):
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		var pose := _bone_pose(skeleton, bone) if bone >= 0 else Transform3D.IDENTITY
		binds.append(pose * skin.get_bind_pose(bind))
	var per_vertex := int(bone_ids.size() / float(maxi(vertices.size(), 1)))
	if per_vertex == 0 or binds.is_empty():
		return vertices
	var posed := PackedVector3Array()
	posed.resize(vertices.size())
	for v in range(vertices.size()):
		var sum := Vector3.ZERO
		var total := 0.0
		for k in range(per_vertex):
			var weight := bone_weights[v * per_vertex + k]
			var bind := bone_ids[v * per_vertex + k]
			if weight <= 0.0 or bind >= binds.size():
				continue
			sum += binds[bind] * vertices[v] * weight
			total += weight
		posed[v] = sum / total if total > 0.0 else vertices[v]
	return posed


## Skeleton-space pose of [param bone] as last drawn; the skeleton's own pose (no
## modifiers) until the first update was recorded.
func _bone_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	if skeleton == _pose_source and bone < _drawn_poses.size():
		return _drawn_poses[bone]
	return skeleton.get_bone_global_pose(bone)


func _on_skeleton_updated() -> void:
	if not is_instance_valid(_pose_source):
		return
	var count := _pose_source.get_bone_count()
	_drawn_poses.resize(count)
	for bone in range(count):
		_drawn_poses[bone] = _pose_source.get_bone_global_pose(bone)


## Island id per triangle: triangles sharing a vertex (same position and UV) are one island.
static func _find_islands(order: PackedInt32Array, vertices: PackedVector3Array,
		uvs: PackedVector2Array) -> PackedInt32Array:
	var parents := PackedInt32Array()
	parents.resize(vertices.size())
	var seen := {}
	for i in range(vertices.size()):
		var key := [vertices[i], uvs[i]]
		parents[i] = seen.get(key, i)
		seen[key] = parents[i]
	for i in range(0, order.size(), 3):
		var root_a := _find(parents, order[i])
		_union(parents, root_a, _find(parents, order[i + 1]))
		_union(parents, _find(parents, root_a), _find(parents, order[i + 2]))
	var ids := {}
	var islands := PackedInt32Array()
	islands.resize(int(order.size() / 3.0))
	for t in range(islands.size()):
		var root := _find(parents, order[t * 3])
		if not ids.has(root):
			ids[root] = ids.size()
		islands[t] = ids[root]
	return islands


static func _find(parents: PackedInt32Array, index: int) -> int:
	var root := index
	while parents[root] != root:
		root = parents[root]
	while parents[index] != root:
		var next := parents[index]
		parents[index] = root
		index = next
	return root


static func _union(parents: PackedInt32Array, a: int, b: int) -> void:
	if a != b:
		parents[maxi(a, b)] = mini(a, b)


## Rasterises every triangle's island into a small mask, then grows the islands a little
## into the empty texels round them so paint covers the texture's filtering border.
func _ensure_mask() -> void:
	settle_warm_up(true)
	if _mask_size > 0:
		return
	_ensure_triangles()
	_build_mask(_uvs, _islands, size())


## Starts building the island mask on a worker thread, so the first stroke or fill on this
## surface does not have to wait for it. The mesh data and texture size are read here (on
## the calling thread) and handed over; the mask is only read after [method settle_warm_up].
func warm_up() -> void:
	if _mask_size > 0 or _mask_task >= 0 or not is_instance_valid(mesh_instance):
		return
	_ensure_triangles()
	if _uvs.is_empty():
		return
	_mask_task = WorkerThreadPool.add_task(_build_mask.bind(_uvs, _islands, size()), false,
			"Paint island mask")


## Collects the background mask build of [method warm_up] once it is done; with [param wait]
## it waits for it. True when no build is left running.
func settle_warm_up(wait: bool = false) -> bool:
	if _mask_task < 0:
		return true
	if not wait and not WorkerThreadPool.is_task_completed(_mask_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_mask_task)
	_mask_task = -1
	return true


## Builds the island mask from [param uvs] (texels) and [param islands] for a texture of
## [param dims]. Given its own copies of them, so it can run on a worker thread while the
## main thread re-reads the posed triangles.
func _build_mask(uvs: PackedVector2Array, islands: PackedInt32Array, dims: Vector2i) -> void:
	_mask_size = mini(MASK_MAX, maxi(dims.x, dims.y))
	_mask = PackedInt32Array()
	_mask.resize(_mask_size * _mask_size)
	_mask.fill(NO_ISLAND)
	var to_mask := Vector2(_mask_size, _mask_size) / Vector2(dims)
	for t in range(islands.size()):
		_rasterise(uvs[t * 3] * to_mask, uvs[t * 3 + 1] * to_mask, uvs[t * 3 + 2] * to_mask,
				islands[t])
	for _round in range(MASK_GROW):
		_grow_mask()


## Marks the mask pixels the triangle (a, b, c) touches (conservatively, by half a pixel).
func _rasterise(a: Vector2, b: Vector2, c: Vector2, island: int) -> void:
	var low := a.min(b).min(c).floor()
	var high := a.max(b).max(c).ceil()
	var twice_area := (b - a).cross(c - a)
	if is_zero_approx(twice_area):
		return
	var sign_flip := 1.0 if twice_area > 0.0 else -1.0
	var edges: Array[Vector2] = [a, b, b, c, c, a]
	var slack: Array[float] = []
	for e in range(3):
		slack.append((edges[e * 2 + 1] - edges[e * 2]).length() * 0.71)
	for y in range(maxi(int(low.y), 0), mini(int(high.y), _mask_size)):
		for x in range(maxi(int(low.x), 0), mini(int(high.x), _mask_size)):
			var point := Vector2(x + 0.5, y + 0.5)
			var inside := true
			for e in range(3):
				var from := edges[e * 2]
				if (edges[e * 2 + 1] - from).cross(point - from) * sign_flip < -slack[e]:
					inside = false
					break
			if inside:
				_mask[y * _mask_size + x] = island


func _grow_mask() -> void:
	var grown := _mask.duplicate()
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(_mask_size):
		for x in range(_mask_size):
			if _mask[y * _mask_size + x] != NO_ISLAND:
				continue
			for step in steps:
				var nx := x + step.x
				var ny := y + step.y
				if nx < 0 or ny < 0 or nx >= _mask_size or ny >= _mask_size:
					continue
				var neighbour := _mask[ny * _mask_size + nx]
				if neighbour != NO_ISLAND:
					grown[y * _mask_size + x] = neighbour
					break
	_mask = grown
