class_name GrindRail
extends Path3D
## A rail the skater can grind along. The shape is this node's [member Path3D.curve].
##
## On ready (and whenever the curve changes) it builds a thin box-section mesh along the
## curve for the visuals and a chain of capsules in [code]SnapArea[/code] (physics layer 4,
## [code]grind_rail[/code]) so other systems can detect it. The rail joins the
## [code]grind_rails[/code] group; [GrindAbility] searches that group and rides the rail
## through the query functions below, which all work in world space.

## Group every rail joins so abilities can find them.
const GROUP := "grind_rails"
## Distance (m) used to estimate the direction of the curve at an offset.
const TANGENT_STEP := 0.05

## Width and height (m) of the visible rail bar.
@export var rail_thickness: float = 0.08
## Radius (m) of the detection capsules around the rail.
@export var snap_radius: float = 0.3
## Length (m) of each detection capsule segment.
@export var snap_segment_length: float = 2.0

@onready var _mesh_instance: MeshInstance3D = $RailMesh
@onready var _snap_area: Area3D = $SnapArea


func _ready() -> void:
	add_to_group(GROUP)
	_snap_area.collision_layer = PhysicsLayers.GRIND_RAIL_MASK
	_snap_area.collision_mask = 0
	curve_changed.connect(_on_curve_changed)
	_rebuild()


## Total length (m) of the rail along its curve.
func length() -> float:
	if curve == null:
		return 0.0
	return curve.get_baked_length()


## Distance along the rail (m) of the point closest to [param world_pos].
func closest_offset(world_pos: Vector3) -> float:
	if curve == null:
		return 0.0
	return curve.get_closest_offset(to_local(world_pos))


## World position on the rail at [param offset] (clamped to the rail).
func position_at(offset: float) -> Vector3:
	if curve == null:
		return global_position
	return to_global(curve.sample_baked(clampf(offset, 0.0, length()), true))


## Unit world-space direction of travel (towards larger offsets) at [param offset].
func tangent_at(offset: float) -> Vector3:
	var total := length()
	if total <= 0.0:
		return global_basis.x.normalized()
	var a := clampf(offset - TANGENT_STEP, 0.0, total)
	var b := clampf(offset + TANGENT_STEP, 0.0, total)
	var along := position_at(b) - position_at(a)
	if along.is_zero_approx():
		return global_basis.x.normalized()
	return along.normalized()


## Straight-line distance (m) from [param world_pos] to the nearest point on the rail.
func distance_to(world_pos: Vector3) -> float:
	return world_pos.distance_to(position_at(closest_offset(world_pos)))


func _on_curve_changed() -> void:
	if is_node_ready():
		_rebuild()


func _rebuild() -> void:
	_mesh_instance.mesh = _build_mesh()
	_rebuild_snap_shapes()


func _build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if curve == null or curve.point_count < 2:
		return mesh
	var points := curve.get_baked_points()
	if points.size() < 2:
		return mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := rail_thickness * 0.5
	for i in range(points.size() - 1):
		_add_box_segment(tool, points[i], points[i + 1], half)
	tool.generate_normals()
	return tool.commit()


func _add_box_segment(tool: SurfaceTool, from: Vector3, to: Vector3, half: float) -> void:
	var along := to - from
	if along.is_zero_approx():
		return
	var dir := along.normalized()
	var up_hint := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var side := dir.cross(up_hint).normalized() * half
	var up := side.cross(dir).normalized() * half
	var ring: Array[Vector3] = [up + side, up - side, -up - side, -up + side]
	for k in range(ring.size()):
		var a0 := from + ring[k]
		var a1 := from + ring[(k + 1) % ring.size()]
		var b0 := to + ring[k]
		var b1 := to + ring[(k + 1) % ring.size()]
		for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
			tool.add_vertex(v)


func _rebuild_snap_shapes() -> void:
	for child in _snap_area.get_children():
		_snap_area.remove_child(child)
		child.queue_free()
	var total := length()
	if total <= 0.0:
		return
	var segments := maxi(1, ceili(total / snap_segment_length))
	var step := total / segments
	for i in range(segments):
		var from := curve.sample_baked(i * step, true)
		var to := curve.sample_baked((i + 1) * step, true)
		_snap_area.add_child(_capsule_between(from, to))


func _capsule_between(from: Vector3, to: Vector3) -> CollisionShape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = snap_radius
	capsule.height = from.distance_to(to) + snap_radius * 2.0
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	var dir := (to - from).normalized()
	var shape_basis := Basis.IDENTITY
	if dir.dot(Vector3.UP) < -0.999:
		shape_basis = Basis(Vector3.RIGHT, PI)
	elif not dir.is_zero_approx():
		shape_basis = Basis(Quaternion(Vector3.UP, dir))
	shape.transform = Transform3D(shape_basis, (from + to) * 0.5)
	return shape
