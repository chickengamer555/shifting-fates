class_name SurfaceGuard
extends Node3D
## Walls a raised floor of the level art in on every side with [InvisibleBarrier]s, so the
## player can ride and jump on it but never fall off it (e.g. the intro's walkway, high above
## the ground, where falling would soft-lock the intro).
##
## On ready it measures the floor at [member surface_path] from its mesh and builds four
## walls whose inner faces stand on the floor's edges, from [member footroom] m below its top
## to [member height] m above it. The walls show the usual proximity dots in the floor's
## colour and join [constant InvisibleBarrier.GROUP], so the level tracks the player on them.

const BARRIER_SCENE := preload("res://scenes/world/invisible_barrier.tscn")
const THICKNESS := 1.0
const WALL_NAMES: Array[String] = ["North", "South", "East", "West"]

## The floor to wall in.
@export var surface_path: NodePath
## How far (m) the walls reach above the floor.
@export var height: float = 14.0
## How far (m) the walls reach below the floor's top.
@export var footroom: float = 2.0


func _ready() -> void:
	var surface := get_node_or_null(surface_path)
	if surface == null:
		push_warning("SurfaceGuard: no surface at %s" % surface_path)
		return
	var box: Variant = _bounds(surface)
	if box == null:
		return
	_build_walls(box as AABB)


func _build_walls(box: AABB) -> void:
	var low := box.end.y - footroom
	var tall := footroom + height
	var mid_y := low + tall * 0.5
	var centre := box.get_center()
	var half := THICKNESS * 0.5
	var span_x := box.size.x + THICKNESS * 2.0
	var span_z := box.size.z + THICKNESS * 2.0
	var places := {
		"North": [Vector3(centre.x, mid_y, box.position.z - half), Vector3(span_x, tall, THICKNESS)],
		"South": [Vector3(centre.x, mid_y, box.end.z + half), Vector3(span_x, tall, THICKNESS)],
		"West": [Vector3(box.position.x - half, mid_y, centre.z), Vector3(THICKNESS, tall, span_z)],
		"East": [Vector3(box.end.x + half, mid_y, centre.z), Vector3(THICKNESS, tall, span_z)],
	}
	for wall_name: String in WALL_NAMES:
		var wall := BARRIER_SCENE.instantiate() as InvisibleBarrier
		wall.name = wall_name
		wall.size = places[wall_name][1] as Vector3
		add_child(wall)
		wall.global_transform = Transform3D(Basis.IDENTITY, places[wall_name][0] as Vector3)


## Global bounds of the meshes under [param surface], or null.
static func _bounds(surface: Node) -> Variant:
	var bounds: Variant = null
	var nodes: Array[Node] = [surface]
	nodes.append_array(surface.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var box := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		bounds = box if bounds == null else (bounds as AABB).merge(box)
	return bounds
