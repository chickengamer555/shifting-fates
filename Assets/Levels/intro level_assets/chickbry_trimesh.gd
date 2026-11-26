extends CollisionShape3D
## Chickbry 3D Lo-fi export: this collision is the visible mesh's own triangles, built when
## the level loads instead of being stored a second time in the scene file.

@export var mesh: Mesh


func _enter_tree() -> void:
	if mesh != null and shape == null:
		var s := mesh.create_trimesh_shape()
		s.backface_collision = true
		shape = s
