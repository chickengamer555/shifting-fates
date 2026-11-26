@tool
class_name InvisibleBarrier
extends StaticBody3D
## A solid wall the player cannot see until they get close: then ordered-dither dots in the
## floor's colour fade in on it, so the edge of the level is readable.
##
## The box is [member size] metres, centred on the node, on physics layer 1 [code]world[/code].
## The level calls [method track] with the skater; each frame the barrier hands the skater's
## position to the [code]dither_barrier[/code] shader, which does the per-pixel fade.
##
## The shader material (local to each instance) and the default box ship in
## [code]invisible_barrier.tscn[/code]. In the editor the script only resizes the shape and
## mesh to [member size], and only when the size really changed, so saving a level does not
## rewrite its barriers.

## Group every barrier joins, so a level can hand them all the player at once.
const GROUP := &"invisible_barrier"
const PARAM_FLOOR_COLOR := &"floor_color"
const PARAM_PLAYER_POSITION := &"player_position"
const PARAM_REVEAL_DISTANCE := &"reveal_distance"

## Box size (m).
@export var size: Vector3 = Vector3(10.0, 6.0, 1.0):
	set(value):
		size = value
		_apply_size()
## The colour of the floor next to the wall; the dots are drawn in it.
@export var floor_color: Color = Color.WHITE:
	set(value):
		floor_color = value
		_set_param(PARAM_FLOOR_COLOR, floor_color)
## The dots start to appear when the player is this close (m).
@export var reveal_distance: float = 6.0:
	set(value):
		reveal_distance = maxf(value, 0.01)
		_set_param(PARAM_REVEAL_DISTANCE, reveal_distance)

var _target: Node3D = null
var _material: ShaderMaterial = null

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		set_process(false)
		return
	set_meta("verify_unit", "InvisibleBarrier")
	add_to_group(GROUP)
	_material = _mesh.material_override as ShaderMaterial
	if _material == null:
		push_warning("InvisibleBarrier: Mesh has no ShaderMaterial; the dots stay hidden")
	_set_param(PARAM_FLOOR_COLOR, floor_color)
	_set_param(PARAM_REVEAL_DISTANCE, reveal_distance)


func _process(_delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		_set_param(PARAM_PLAYER_POSITION, _target.global_position)


## Fades the dots in around [param target] (normally the skater) from now on.
func track(target: Node3D) -> void:
	_target = target
	if target != null:
		_set_param(PARAM_PLAYER_POSITION, target.global_position)


## Gives the shape and mesh new boxes of [member size]; boxes that already fit are kept.
func _apply_size() -> void:
	if not is_node_ready():
		return
	var box_shape := _shape.shape as BoxShape3D
	if box_shape == null or not box_shape.size.is_equal_approx(size):
		box_shape = BoxShape3D.new()
		box_shape.size = size
		_shape.shape = box_shape
	var box_mesh := _mesh.mesh as BoxMesh
	if box_mesh == null or not box_mesh.size.is_equal_approx(size):
		box_mesh = BoxMesh.new()
		box_mesh.size = size
		_mesh.mesh = box_mesh


func _set_param(param: StringName, value: Variant) -> void:
	if _material != null:
		_material.set_shader_parameter(param, value)
