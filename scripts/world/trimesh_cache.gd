class_name TrimeshCache
extends RefCounted
## Builds the level art's collision once per mesh and shares it.
##
## The Chickbry art builds each object's collision from its visible mesh when it enters the
## tree (a [CollisionShape3D] with a [code]mesh[/code] property and no shape yet), which is
## slow for detailed meshes and was repeated for every copy of the art: the level itself, the
## portal views of it, levels built ahead. [method prepare] fills those shapes in before the
## art enters the tree, from a cache keyed by mesh, so each mesh is turned into a shape only
## once per run; with a time budget it stops early and is called again next frame, so a
## first build is spread out instead of freezing one frame.

const MESH_PROPERTY := &"mesh"

static var _shapes: Dictionary[Mesh, Shape3D] = {}


## Fills in the art collision shapes under [param root] (not yet in the tree). With
## [param budget_usec] at or above zero it stops once that much time is spent and returns
## false; call it again to go on. Returns true when every shape is in.
static func prepare(root: Node, budget_usec: int = -1) -> bool:
	var start := Time.get_ticks_usec()
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var holder := node as CollisionShape3D
		if holder.shape != null:
			continue
		var mesh := holder.get(MESH_PROPERTY) as Mesh
		if mesh == null:
			continue
		holder.shape = shape_for(mesh)
		if budget_usec >= 0 and Time.get_ticks_usec() - start >= budget_usec:
			return false
	return true


## The shared collision shape for [param mesh], built on first use.
static func shape_for(mesh: Mesh) -> Shape3D:
	if _shapes.has(mesh):
		return _shapes[mesh]
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	_shapes[mesh] = shape
	return shape


## Forgets every shared shape (e.g. to free memory after leaving the game).
static func clear() -> void:
	_shapes.clear()
