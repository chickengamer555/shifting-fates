extends Node3D
## Chickbry 3D Lo-fi export: the 3D is rendered at render_scale of the window and scaled up
## (Viewport.scaling_3d_scale): the lo-fi look for far less GPU work. 1.0 turns it off.
## The viewport's own scale comes back when the level leaves the tree.

@export_range(0.1, 1.0, 0.05) var render_scale := 0.5
var _before := 1.0


func _enter_tree() -> void:
	_before = get_viewport().scaling_3d_scale
	get_viewport().scaling_3d_scale = render_scale


func _exit_tree() -> void:
	get_viewport().scaling_3d_scale = _before
