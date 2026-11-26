@tool
extends Node3D
## Chickbry 3D: the sky Godot really draws, for reflections. Six small cameras see only the
## sky (the level's own, or one you set on its WorldEnvironment) and every Chickbry shader in
## the level reads them (cb_sky_seen), so mirrors, metals and water show your sky the way
## Chickbry shows its own. Nothing goes into the scene file, and the cameras live in the
## renderer only (no Camera3D nodes): the pictures go straight to the materials.

@export var resolution := 64
@export var refresh_seconds := 0.5   # the sky's clouds drift: draw it again this often

const DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const UPS := [Vector3.UP, Vector3.UP, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.UP]

var _vps: Array[RID] = []
var _cams: Array[RID] = []
var _wait := 0.0
var _frames := 0


func _ready() -> void:
	for i in 6:
		var vp := RenderingServer.viewport_create()
		var cam := RenderingServer.camera_create()
		RenderingServer.viewport_set_size(vp, resolution, resolution)
		RenderingServer.viewport_set_scenario(vp, get_world_3d().scenario)
		RenderingServer.viewport_attach_camera(vp, cam)
		RenderingServer.viewport_set_update_mode(vp, RenderingServer.VIEWPORT_UPDATE_ONCE)
		RenderingServer.viewport_set_active(vp, true)
		RenderingServer.camera_set_perspective(cam, 90.0, 0.05, 100.0)
		RenderingServer.camera_set_cull_mask(cam, 0)   # the sky alone
		RenderingServer.camera_set_transform(cam, Transform3D(Basis.looking_at(DIRS[i], UPS[i]), Vector3.ZERO))
		_vps.append(vp)
		_cams.append(cam)


func _exit_tree() -> void:
	for r in _vps + _cams:
		RenderingServer.free_rid(r)
	_vps.clear()
	_cams.clear()


func _process(delta: float) -> void:
	if _vps.is_empty():
		return
	_frames += 1
	_wait += delta
	if _frames == 3:   # the first pictures are drawn: hand them over
		_share()
	if _wait < refresh_seconds:
		return
	_wait = 0.0
	for vp in _vps:
		RenderingServer.viewport_set_update_mode(vp, RenderingServer.VIEWPORT_UPDATE_ONCE)
	if _frames > 3:
		_share()


# every Chickbry material in the level (and the mirrors' private copies) reads the six faces
func _share() -> void:
	var level := get_parent()
	if level == null:
		return
	var mats: Array[ShaderMaterial] = []
	for n in level.find_children("*", "", true, false):
		for prop in ["material_override", "material", "_mat"]:
			var m = n.get(prop)
			if m is ShaderMaterial and not mats.has(m):
				mats.append(m)
	for m in mats:
		var rid := m.get_rid()
		RenderingServer.material_set_param(rid, "cb_sky_live", true)
		for i in 6:
			RenderingServer.material_set_param(rid, "cb_sky_f%d" % i, RenderingServer.viewport_get_texture(_vps[i]))
