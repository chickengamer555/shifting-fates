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

## Chickbry's objects also draw on this layer: the depth camera sees only them.
const DEPTH_LAYER := 18

var _vp := RID()
var _cam := RID()
var _dvp := RID()
var _dcam := RID()
var _denv := RID()
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
	# no sky in the picture: the plane's shader tells objects (solid) from sky (clear) and draws
	# the sky itself, bent by its ripples as Chickbry's reflected rays are
	RenderingServer.viewport_set_transparent_background(_vp, true)
	RenderingServer.camera_set_cull_mask(_cam, 0xFFFFF & ~bit)
	# the depth picture: Chickbry's objects give their distance behind the plane (a float picture,
	# no tone mapping), so the shader moves each reflection by as much as Chickbry's rays move
	var dbit := 1 << (DEPTH_LAYER - 1)
	_tag_objects(dbit)
	_dvp = RenderingServer.viewport_create()
	_dcam = RenderingServer.camera_create()
	_denv = RenderingServer.environment_create()
	RenderingServer.environment_set_tonemap(_denv, RenderingServer.ENV_TONE_MAPPER_LINEAR, 1.0, 1.0)
	RenderingServer.viewport_set_scenario(_dvp, get_world_3d().scenario)
	RenderingServer.viewport_attach_camera(_dvp, _dcam)
	RenderingServer.viewport_set_update_mode(_dvp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.viewport_set_active(_dvp, true)
	RenderingServer.viewport_set_transparent_background(_dvp, true)
	RenderingServer.viewport_set_use_hdr_2d(_dvp, true)
	RenderingServer.camera_set_cull_mask(_dcam, dbit)
	RenderingServer.camera_set_environment(_dcam, _denv)
	# a private copy of the plane's material, so the scene file never stores the mirror picture
	if material_override is ShaderMaterial:
		_mat = material_override.duplicate()
		RenderingServer.material_set_param(_mat.get_rid(), "mirror", RenderingServer.viewport_get_texture(_vp))
		RenderingServer.material_set_param(_mat.get_rid(), "mirror_depth", RenderingServer.viewport_get_texture(_dvp))
		RenderingServer.instance_geometry_set_material_override(get_instance(), _mat.get_rid())


# Chickbry's surfaces in the level (not this plane, fires or cloud layers) also draw on `bit`,
# in the renderer only: the scene file keeps its layers.
func _tag_objects(bit: int) -> void:
	var objects := get_parent().get_parent() if get_parent() else null
	if objects == null:
		return
	for node in objects.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		var kind := String(gi.get_parent().get_meta("chickbry_kind", "")) if gi.get_parent() else ""
		if gi == self or kind in ["fire", "cloud_plane", "water_plane"] or gi.get_meta("chickbry_kind", "") == "fire":
			continue
		RenderingServer.instance_set_layer_mask(gi.get_instance(), gi.layers | bit)


func _exit_tree() -> void:
	for rid in [_vp, _cam, _dvp, _dcam, _denv]:
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	_vp = RID()
	_cam = RID()
	_dvp = RID()
	_dcam = RID()
	_denv = RID()


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
		RenderingServer.viewport_set_size(_dvp, size.x, size.y)
	RenderingServer.viewport_set_scaling_3d_scale(_vp, vp.scaling_3d_scale)
	RenderingServer.viewport_set_scaling_3d_scale(_dvp, vp.scaling_3d_scale)
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
	# the depth camera sees from the same place through the same lens
	RenderingServer.camera_set_transform(_dcam, Transform3D(Basis.looking_at(-t.basis.z * flip, t.basis.y * flip), o))
	if main.projection == Camera3D.PROJECTION_ORTHOGONAL:
		RenderingServer.camera_set_orthogonal(_dcam, main.size, main.near, main.far)
	else:
		RenderingServer.camera_set_perspective(_dcam, main.fov, main.near, main.far)
	RenderingServer.camera_set_use_vertical_aspect(_dcam, main.keep_aspect == Camera3D.KEEP_WIDTH)
