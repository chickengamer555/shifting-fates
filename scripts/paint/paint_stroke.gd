class_name PaintStroke
extends Resource
## One dab of paint on a rig part, stored in the part's local space.
##
## Strokes are treated as immutable once added to an [Appearance], so undo snapshots can
## share them instead of copying.

## Name of the rig part ([MeshInstance3D]) the dab sits on, e.g. [code]Torso[/code].
@export var part: StringName = &""
## Hit point in the part's local space.
@export var position: Vector3 = Vector3.ZERO
## Outward surface normal at the hit, in the part's local space.
@export var normal: Vector3 = Vector3.UP
## Paint colour.
@export var color: Color = Color.WHITE
## Brush diameter in metres.
@export var size: float = 0.05


## Builds a stroke from its fields.
static func create(part_name: StringName, local_pos: Vector3, local_normal: Vector3,
		paint: Color, diameter: float) -> PaintStroke:
	var stroke := PaintStroke.new()
	stroke.part = part_name
	stroke.position = local_pos
	stroke.normal = local_normal.normalized()
	stroke.color = paint
	stroke.size = diameter
	return stroke
