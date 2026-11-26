@tool
extends MeshInstance3D
## Chickbry 3D's mirror plane (a reflective Ground Plane, or water). Chickbry ray traces
## reflections, so the plane is a true planar mirror here too: a second camera, flipped under
## it, draws the scene each frame (in the game and in the editor's 3D view) and the plane's
## shader shows it as Chickbry would. The camera lives in the renderer only (no Camera3D node),
## so the level's own camera stays the only one a game finds.

## The plane draws on this render layer only, which its mirror camera skips (the ground 20,
## water 19); the level's shaders show nothing under the plane to that camera.
@export_range(1, 20) var mirror_layer := 20

var _vp := RID()
var _cam := RID()
var _size := Vector2i.ZERO
var _mat: ShaderMaterial


func _ready() -> void:
	var bit := 1 << (mirror_layer - 1)
	layers = bit
	_vp = RenderingServer.viewport_create()
	_cam = RenderingServer.camera_create()
	RenderingServer.viewport_set_scenario(_vp, get_world_3d().scenario)
	RenderingServer.viewport_attach_camera(_vp, _cam)
	RenderingServer.viewport_set_update_mode(_vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.viewport_set_active(_vp, true)
	RenderingServer.camera_set_cull_mask(_cam, 0xFFFFF & ~bit)
	# a private copy of the plane's material, so the scene file never stores the mirror picture
	if material_override is ShaderMaterial:
		_mat = material_override.duplicate()
		RenderingServer.material_set_param(_mat.get_rid(), "mirror", RenderingServer.viewport_get_texture(_vp))
		RenderingServer.instance_geometry_set_material_override(get_instance(), _mat.get_rid())


func _exit_tree() -> void:
	if _vp.is_valid():
		RenderingServer.free_rid(_vp)
	if _cam.is_valid():
		RenderingServer.free_rid(_cam)
	_vp = RID()
	_cam = RID()


func _main_camera() -> Camera3D:
	if Engine.is_editor_hint():
		var ei := Engine.get_singleton("EditorInterface")
		return ei.get_editor_viewport_3d(0).get_camera_3d() if ei else null
	return get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	var main := _main_camera()
	if main == null or not _vp.is_valid():
		return
	var vp := main.get_viewport()
	var size := Vector2i(vp.get_visible_rect().size)
	if size.x < 1 or size.y < 1:
		return
	if size != _size:
		_size = size
		RenderingServer.viewport_set_size(_vp, size.x, size.y)
	RenderingServer.viewport_set_scaling_3d_scale(_vp, vp.scaling_3d_scale)
	var h := global_position.y
	var t := main.global_transform
	var o := t.origin
	o.y = 2.0 * h - o.y
	var flip := Vector3(1, -1, 1)
	RenderingServer.camera_set_transform(_cam, Transform3D(Basis.looking_at(-t.basis.z * flip, t.basis.y * flip), o))
	if main.projection == Camera3D.PROJECTION_ORTHOGONAL:
		RenderingServer.camera_set_orthogonal(_cam, main.size, main.near, main.far)
	else:
		RenderingServer.camera_set_perspective(_cam, main.fov, main.near, main.far)
	RenderingServer.camera_set_use_vertical_aspect(_cam, main.keep_aspect == Camera3D.KEEP_WIDTH)
	RenderingServer.camera_set_environment(_cam, main.environment.get_rid() if main.environment else RID())
