extends Node3D
## Developer preview of the [Portal]: level art with the level's real portal into the next
## world, opened at start, while a camera drifts towards it and back so the parallax of the
## window shows. [code]--from=x,y,z[/code] and [code]--to=x,y,z[/code] (user arguments)
## override the camera path, in the portal's frame.

const PORTAL_SCENE := preload("res://scenes/world/portal.tscn")

@export var stage: PackedScene = null
@export var next_world: PackedScene = null
@export var portal_transform: Transform3D = Transform3D.IDENTITY
@export var preview_view: Transform3D = Transform3D.IDENTITY
## Markers of [member next_world] the view is taken from (see [member Portal.preview_from]).
@export var preview_from: NodePath = ^"Spawn"
@export var preview_toward: NodePath = ^"Portal"
## Camera path in the portal's frame: from [member camera_from] to [member camera_to].
@export var camera_from: Vector3 = Vector3(-3.0, 2.2, 9.5)
@export var camera_to: Vector3 = Vector3(1.6, 2.0, 5.5)
@export var camera_seconds: float = 6.0
@export var open_delay: float = 0.4

var _portal: Portal = null
var _camera: Camera3D = null
var _time: float = 0.0


func _ready() -> void:
	if stage != null:
		add_child(stage.instantiate())
	for node: Node in find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
	_portal = PORTAL_SCENE.instantiate() as Portal
	_portal.transform = portal_transform
	_portal.preview_scene = next_world
	_portal.preview_view = preview_view
	_portal.preview_from = preview_from
	_portal.preview_toward = preview_toward
	camera_from = _vector_arg("--from=", camera_from)
	camera_to = _vector_arg("--to=", camera_to)
	add_child(_portal)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.make_current()
	_place_camera(0.0)


func _process(delta: float) -> void:
	_time += delta
	if not _portal.is_open and _time >= open_delay:
		_portal.open()
	# Back and forth: 0 -> 1 -> 0 over two camera_seconds.
	_place_camera(pingpong(_time / camera_seconds, 1.0))


func _place_camera(weight: float) -> void:
	var eased := weight * weight * (3.0 - 2.0 * weight)
	var local := camera_from.lerp(camera_to, eased)
	var target := _portal.global_transform * Vector3(0.0, Portal.CENTRE_HEIGHT, 0.0)
	_camera.global_position = _portal.global_transform * local
	_camera.look_at(target, Vector3.UP)


## The value of the user argument [param prefix] as "x,y,z", or [param fallback].
func _vector_arg(prefix: String, fallback: Vector3) -> Vector3:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			var parts := arg.trim_prefix(prefix).split_floats(",")
			if parts.size() == 3:
				return Vector3(parts[0], parts[1], parts[2])
	return fallback

