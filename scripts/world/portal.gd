class_name Portal
extends Node3D
## The way out of a level: a ring showing a live view of the next area, opened by the level
## once its point goal is reached.
##
## Hidden and closed until [method open]. Opening mounts [member preview_scene] in its own
## world inside [code]PreviewViewport[/code], looked at from [member preview_view], and puts
## that view on the [code]Surface[/code]. The [code]Trigger[/code] (layer 5 [code]trigger[/code],
## watching layer 2 [code]player[/code]) emits [signal entered] the first time a player body
## passes through an open portal. Works headless: the viewport simply renders nothing.

## The player passed through the open portal. Emitted at most once.
signal entered

## Scene shown through the portal, e.g. the next level's art. Optional.
@export var preview_scene: PackedScene = null
## Where the preview camera stands inside [member preview_scene].
@export var preview_view: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
## Pixel size of the preview render.
@export var preview_resolution: Vector2i = Vector2i(512, 512)

## True once [method open] has been called.
var is_open: bool = false

var _used: bool = false
var _preview_mounted: bool = false

@onready var _surface: MeshInstance3D = $Surface
@onready var _viewport: SubViewport = $PreviewViewport
@onready var _preview_camera: Camera3D = $PreviewViewport/PreviewCamera
@onready var _trigger: Area3D = $Trigger


func _ready() -> void:
	set_meta("verify_unit", "Portal")
	visible = false
	_viewport.own_world_3d = true
	_viewport.size = preview_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	_surface.material_override = material
	_trigger.body_entered.connect(_on_trigger_body_entered)


## Shows the portal and its preview and lets the player through. Calling it again is harmless.
func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_mount_preview()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# A player already standing in the ring when it opens goes through too.
	_check_bodies_inside.call_deferred()


func _mount_preview() -> void:
	if _preview_mounted or preview_scene == null:
		return
	_preview_mounted = true
	var preview := preview_scene.instantiate()
	_viewport.add_child(preview)
	# Art scenes may bring their own camera; the portal's camera is the one that looks.
	_preview_camera.transform = preview_view
	_preview_camera.make_current()


func _check_bodies_inside() -> void:
	for body: Node3D in _trigger.get_overlapping_bodies():
		_on_trigger_body_entered(body)


func _on_trigger_body_entered(_body: Node3D) -> void:
	if not is_open or _used:
		return
	_used = true
	entered.emit()
