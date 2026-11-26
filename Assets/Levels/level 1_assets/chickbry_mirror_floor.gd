@tool
extends MeshInstance3D
## Chickbry 3D's mirror floor. Chickbry ray traces reflections, so a reflective Ground Plane
## is a true planar mirror here too: a second camera, flipped under the floor, draws the
## scene each frame (in the game and in the editor's 3D view) and the floor's shader shows it.
## Things under the floor would show in it; Chickbry's floor hides them, so keep them above.

const MIRROR_LAYER := 1 << 19   # the floor draws on layer 20 only: the mirror camera skips it

## The sky the mirror shows: Chickbry's, whatever sky the level's environment is given later
## (empty: the main camera's environment).
@export var look_environment: Environment

var _view: SubViewport
var _cam: Camera3D
var _mat: ShaderMaterial


func _ready() -> void:
	layers = MIRROR_LAYER
	_view = SubViewport.new()
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.world_3d = get_world_3d()
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~MIRROR_LAYER
	_view.add_child(_cam)
	add_child(_view, false, Node.INTERNAL_MODE_BACK)
	if material_override is ShaderMaterial:
		_ready_material()


func _main_camera() -> Camera3D:
	if Engine.is_editor_hint():
		var ei := Engine.get_singleton("EditorInterface")
		return ei.get_editor_viewport_3d(0).get_camera_3d() if ei else null
	return get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	var main := _main_camera()
	if main == null or _cam == null:
		return
	var vp := main.get_viewport()
	var size := Vector2i(vp.get_visible_rect().size)
	if size.x < 1 or size.y < 1:
		return
	if _view.size != size:
		_view.size = size
	_view.scaling_3d_scale = vp.scaling_3d_scale
	var h := global_position.y
	var t := main.global_transform
	var o := t.origin
	o.y = 2.0 * h - o.y
	var flip := Vector3(1, -1, 1)
	var fwd := -t.basis.z * flip
	var up := t.basis.y * flip
	_cam.global_transform = Transform3D(Basis.looking_at(fwd, up), o)
	_cam.projection = main.projection
	_cam.keep_aspect = main.keep_aspect
	_cam.fov = main.fov
	_cam.size = main.size
	_cam.near = main.near
	_cam.far = main.far
	_cam.environment = look_environment if look_environment else main.environment
	_cam.attributes = main.attributes


# a private copy of the floor's material, so the scene file never stores the mirror texture
func _ready_material() -> void:
	_mat = material_override.duplicate()
	_mat.set_shader_parameter("mirror", _view.get_texture())
	RenderingServer.instance_geometry_set_material_override(get_instance(), _mat.get_rid())
