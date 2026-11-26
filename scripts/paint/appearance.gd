class_name Appearance
extends Resource
## How the player painted their body and board: base colour per rig part plus paint dabs.
##
## Parts are keyed by the [MeshInstance3D] node names of the skater rig (body: Head,
## Torso, ArmL, ArmR, LegL, LegR; board: Deck, TruckFront, TruckBack, WheelFL, WheelFR,
## WheelBL, WheelBR). [method apply_to] recolours with duplicated materials, so the
## shared white material of the rig is never changed, and rebuilds every dab as a
## [Decal] under its part (see [PaintBrush]).

const DEFAULT_PATH := "user://appearance.tres"
const DEFAULT_MAX_STROKES := 400
## A dab merges into the previous one when closer than this fraction of its size.
const DEFAULT_MERGE_RATIO := 0.35

## Base colour per part name. Parts not listed keep the rig's own material.
@export var part_colors: Dictionary[StringName, Color] = {}
## Paint dabs, oldest first.
@export var strokes: Array[PaintStroke] = []
## Most dabs kept; adding past it drops the oldest so painting never stalls.
@export var max_strokes: int = DEFAULT_MAX_STROKES
## Merge distance as a fraction of the brush size (0 turns merging off).
@export_range(0.0, 1.0) var merge_ratio: float = DEFAULT_MERGE_RATIO


## Loads the appearance at [param path] and applies it to [param rig_root]. Returns the
## loaded appearance, or null (rig left as is) when there is no saved one.
static func apply_saved(rig_root: Node3D, path: String = DEFAULT_PATH) -> Appearance:
	var appearance := load_from(path)
	if appearance != null:
		appearance.apply_to(rig_root)
	return appearance


## Reads an appearance from [param path]; null when missing or not an Appearance.
static func load_from(path: String = DEFAULT_PATH) -> Appearance:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Appearance


## Every paintable part under [param rig_root], by node name.
static func find_parts(rig_root: Node) -> Dictionary[StringName, MeshInstance3D]:
	var parts: Dictionary[StringName, MeshInstance3D] = {}
	for node in rig_root.find_children("*", "MeshInstance3D", true, false):
		parts[StringName(node.name)] = node as MeshInstance3D
	return parts


## Writes this appearance to [param path].
func save(path: String = DEFAULT_PATH) -> Error:
	return ResourceSaver.save(self, path)


## Sets the base colour of [param part].
func set_part_color(part: StringName, color: Color) -> void:
	part_colors[part] = color


## Base colour of [param part], or [param fallback] when it was never filled.
func get_part_color(part: StringName, fallback: Color = Color.WHITE) -> Color:
	return part_colors.get(part, fallback)


## Adds a dab. Returns false when it merged into the previous dab instead. Past
## [member max_strokes] the oldest dabs are dropped.
func add_stroke(part: StringName, local_pos: Vector3, normal: Vector3, color: Color,
		size: float) -> bool:
	if _merges_with_last(part, local_pos, color, size):
		return false
	strokes.append(PaintStroke.create(part, local_pos, normal, color, size))
	while strokes.size() > maxi(max_strokes, 0):
		strokes.pop_front()
	return true


## Removes the dabs on [param part] within [param radius] of [param local_pos]. Returns
## how many were removed.
func erase_near(part: StringName, local_pos: Vector3, radius: float) -> int:
	var kept: Array[PaintStroke] = []
	for stroke in strokes:
		if stroke.part != part or stroke.position.distance_to(local_pos) > radius:
			kept.append(stroke)
	var removed := strokes.size() - kept.size()
	strokes = kept
	return removed


## A copy that shares the (immutable) strokes; cheap enough for undo snapshots.
func snapshot() -> Appearance:
	var copy := Appearance.new()
	copy.copy_from(self)
	return copy


## Makes this appearance equal to [param other] (keeps this object's identity).
func copy_from(other: Appearance) -> void:
	part_colors = other.part_colors.duplicate()
	strokes = other.strokes.duplicate()
	max_strokes = other.max_strokes
	merge_ratio = other.merge_ratio


## Recolours the parts under [param rig_root] and rebuilds the dabs. Pass the skater's
## [code]Rig[/code] node (any ancestor of the part meshes works). Returns the dabs in
## stroke order.
func apply_to(rig_root: Node3D) -> Array[Decal]:
	var parts := find_parts(rig_root)
	for part_name in parts:
		_recolour(parts[part_name], part_name)
		_clear_dabs(parts[part_name])
	var dabs: Array[Decal] = []
	for stroke in strokes:
		var part: MeshInstance3D = parts.get(stroke.part)
		if part == null:
			continue
		var dab := PaintBrush.make_dab(stroke)
		part.add_child(dab)
		dabs.append(dab)
	return dabs


func _merges_with_last(part: StringName, local_pos: Vector3, color: Color,
		size: float) -> bool:
	if strokes.is_empty() or merge_ratio <= 0.0:
		return false
	var last: PaintStroke = strokes.back()
	return (last.part == part and last.color.is_equal_approx(color)
			and is_equal_approx(last.size, size)
			and last.position.distance_to(local_pos) < size * merge_ratio)


func _recolour(part: MeshInstance3D, part_name: StringName) -> void:
	if not part_colors.has(part_name):
		part.material_override = null
		return
	var source: Material = null
	if part.mesh != null and part.mesh.get_surface_count() > 0:
		source = part.mesh.surface_get_material(0)
	var material: BaseMaterial3D
	if source is BaseMaterial3D:
		material = source.duplicate() as BaseMaterial3D
	else:
		material = StandardMaterial3D.new()
	material.albedo_color = part_colors[part_name]
	part.material_override = material


func _clear_dabs(part: MeshInstance3D) -> void:
	for child in part.get_children():
		if PaintBrush.is_dab(child):
			part.remove_child(child)
			child.queue_free()
