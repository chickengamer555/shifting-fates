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
var _mask: PackedInt32Array
var _mask_size: int = 0
## Stroke state: the image before the stroke, the best coverage per texel so far and the
## rectangle the stroke touched.
var _stroke_base: Image
var _coverage: PackedByteArray
var _stroke_rect: Rect2i = Rect2i()
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
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	texture = ImageTexture.create_from_image(image)
	material.albedo_texture = texture
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
func finalize_for_play() -> void:
	if image == null:
		return
	var shown := image.duplicate() as Image
	shown.generate_mipmaps()
	texture = ImageTexture.create_from_image(shown)
	material.albedo_texture = texture
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


## Puts back the pixels of an undo record from [method end_stroke].
func restore(record: Dictionary) -> void:
	var rect: Rect2i = record["rect"]
	image.blit_rect(record["pixels"] as Image, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	_dirty = true


## Draws a line [param radius_m] metres wide each side from hit [param from] to hit
## [param to] (both on this layer, same island) in [param color], or back to the unpainted
## look when [param erase]. Must be inside [method begin_stroke] / [method end_stroke].
func draw_segment(from: Dictionary, to: Dictionary, radius_m: float, color: Color,
		erase: bool) -> void:
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
			var level := int(cover * 255.0)
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


## The painted image as PNG bytes.
func to_png() -> PackedByteArray:
	return image.save_png_to_buffer() if image != null else PackedByteArray()


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


## Texture size from the source texture, else from the mesh's surface area.
func _pick_size() -> Vector2i:
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
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
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
	_uvs.resize(order.size())
	for i in range(order.size()):
		_positions[i] = vertices[order[i]]
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
	if _mask_size > 0:
		return
	_ensure_triangles()
	_mask_size = mini(MASK_MAX, maxi(size().x, size().y))
	_mask = PackedInt32Array()
	_mask.resize(_mask_size * _mask_size)
	_mask.fill(NO_ISLAND)
	var to_mask := Vector2(_mask_size, _mask_size) / Vector2(size())
	for t in range(_islands.size()):
		_rasterise(_uvs[t * 3] * to_mask, _uvs[t * 3 + 1] * to_mask, _uvs[t * 3 + 2] * to_mask,
				_islands[t])
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
