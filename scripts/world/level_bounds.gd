class_name LevelBounds
extends Node3D
## Fits a level's four [InvisibleBarrier] walls (children [code]North[/code],
## [code]South[/code], [code]East[/code], [code]West[/code]) around everything solid in the
## level art when the level loads, so the walls never cut through art the player can reach.
##
## The art is every [CollisionObject3D] under [member art_path], measured from its meshes;
## the endless ground and water planes (wider than [constant ENDLESS] m) are left out. Each
## object counts with its widest horizontal reach in every direction, so art that spins
## round the vertical (ArtNotes "needs to spin") stays inside too. The walls then stand
## [member margin] m outside that, from below the lowest art up to [member headroom] m above
## the highest.

## Meshes wider than this (m) are endless planes, not reachable art.
const ENDLESS := 5000.0
## Wall thickness (m).
const THICKNESS := 1.0
const NORTH := ^"North"
const SOUTH := ^"South"
const EAST := ^"East"
const WEST := ^"West"

## The level art to fit around.
@export var art_path: NodePath = ^"../Art"
## Open space (m) between the outermost art and the walls.
@export var margin: float = 30.0
## How far (m) the walls reach above the highest art.
@export var headroom: float = 80.0
## How far (m) the walls reach below the lowest art.
@export var footroom: float = 20.0


func _ready() -> void:
	fit()


## Moves and sizes the walls around the art. Does nothing without art or walls.
func fit() -> void:
	var art := get_node_or_null(art_path)
	if art == null:
		return
	var bounds: Variant = art_bounds(art)
	if bounds == null:
		return
	var box := bounds as AABB
	var low := box.position.y - footroom
	var high := box.end.y + headroom
	var height := high - low
	var mid_y := (low + high) * 0.5
	var inner_min := Vector2(box.position.x - margin, box.position.z - margin)
	var inner_max := Vector2(box.end.x + margin, box.end.z + margin)
	var span_x := inner_max.x - inner_min.x + THICKNESS * 2.0
	var span_z := inner_max.y - inner_min.y + THICKNESS * 2.0
	var mid_x := (inner_min.x + inner_max.x) * 0.5
	var mid_z := (inner_min.y + inner_max.y) * 0.5
	var half := THICKNESS * 0.5
	_place(NORTH, Vector3(mid_x, mid_y, inner_min.y - half), Vector3(span_x, height, THICKNESS))
	_place(SOUTH, Vector3(mid_x, mid_y, inner_max.y + half), Vector3(span_x, height, THICKNESS))
	_place(WEST, Vector3(inner_min.x - half, mid_y, mid_z), Vector3(THICKNESS, height, span_z))
	_place(EAST, Vector3(inner_max.x + half, mid_y, mid_z), Vector3(THICKNESS, height, span_z))


## Global bounds of the solid art under [param art], each object widened to its full
## horizontal reach round its own centre; null when there is none.
static func art_bounds(art: Node) -> Variant:
	var bounds: Variant = null
	for node: Node in art.find_children("*", "CollisionObject3D", true, false):
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var box := mesh_node.global_transform * mesh_node.mesh.get_aabb()
			if box.size.x > ENDLESS or box.size.z > ENDLESS:
				continue
			var reach := Vector2(box.size.x, box.size.z).length() * 0.5
			var centre := box.get_center()
			var round_box := AABB(Vector3(centre.x - reach, box.position.y, centre.z - reach),
				Vector3(reach * 2.0, box.size.y, reach * 2.0))
			bounds = round_box if bounds == null else (bounds as AABB).merge(round_box)
	return bounds


func _place(wall_name: NodePath, centre: Vector3, size: Vector3) -> void:
	var wall := get_node_or_null(wall_name) as InvisibleBarrier
	if wall == null:
		return
	wall.global_transform = Transform3D(Basis.IDENTITY, centre)
	wall.size = size
