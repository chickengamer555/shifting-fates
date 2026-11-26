class_name Portal
extends Node3D
## An opening of light that is a window into another world: the way out of a level (opened
## once its point goal is reached) or the way the player came in (open from the start).
##
## Hidden and closed until [method open]; once open it never closes. Opening mounts
## [member preview_scene] in its own world inside [code]PreviewViewport[/code] and blooms the
## opening out from a point of light. While open, the preview camera copies the viewer's
## camera, re-expressed relative to the opening and carried over to [member preview_view] in
## the other world, and the [code]Surface[/code] shader
## ([code]scenes/world/shaders/portal.gdshader[/code]) samples that render in screen space:
## the opening reads as a hole through to the other world, with parallax.
## [br]With [member opens_onto] set, the view is the matching portal of the preview world,
## found from its art's markers by [PortalPlacement] (the same rule the levels place their
## portals by), instead of [member preview_view]: an exit opens onto the next world's way
## in, a way in onto the previous world's exit, so looking through is exactly what the
## player rides into.
## [br]With [member auto_rim_color] the rim takes the other world's main colour
## ([method dominant_color] of its render) a moment after opening.
## [br]Both faces of the opening are windows: from behind, the view is of the other world
## behind its matching portal, as if the two portals were one doorway.
## [br]The [code]Trigger[/code] (layer 5 [code]trigger[/code], watching layer 2
## [code]player[/code]), deep enough that even a dash cannot skip it, emits [signal entered]
## each time a player body comes into an open, [member enterable] portal (from either
## face) and [signal exited] when it leaves. Works headless: the viewport simply renders
## nothing.

## A player body came into the open, enterable portal (from either face).
signal entered
## A player body left the portal's trigger.
signal exited

## Which portal of the preview world this one opens onto (see [member opens_onto]).
enum OtherEnd { NONE, WAY_IN, EXIT }

## Height of the opening's centre above the portal's origin (metres).
const CENTRE_HEIGHT := 1.9
## Quad half-side, trigger size and glow reach per metre of [member opening_radius] (the
## shapes the scene ships with are for the default 1.4 m).
const QUAD_PER_RADIUS := 2.5 / 1.4
const TRIGGER_PER_RADIUS := Vector2(2.8 / 1.4, 3.6 / 1.4)
const TRIGGER_DEPTH := 3.0
const GLOW_PER_RADIUS := 8.0 / 1.4
## Frames the preview renders before its colour is read for the rim.
const RIM_SAMPLE_DELAY_FRAMES := 12
## Side of the thumbnail the main colour is counted on.
const COLOR_SAMPLE_SIZE := 24
## Hue buckets for [method dominant_color]; one more bucket holds the greys.
const HUE_BUCKETS := 12
## Pixels less saturated than this count as grey (white, black, fog).
const GREY_SATURATION := 0.18
## Pixels darker than this are ignored: shadows say little about a world's colour.
const MIN_VALUE := 0.12

## Scene shown through the portal, e.g. the next level's art. Optional.
@export var preview_scene: PackedScene = null
## Where, inside [member preview_scene], the viewer stands when standing at the opening's
## centre facing through it (the portal's -Z). Seen from elsewhere, the preview camera moves
## with the viewer around this point. Replaced when [member opens_onto] is set.
@export var preview_view: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
## The portal of [member preview_scene] this one opens onto; NONE keeps
## [member preview_view].
@export var opens_onto: OtherEnd = OtherEnd.NONE
## Preview render size as a fraction of the screen's size (keeps the screen's aspect).
@export_range(0.25, 1.0) var preview_scale: float = 0.75
## Seconds the opening takes to bloom out from a point once [method open] is called.
@export var open_seconds: float = 1.2
## False for a way in: the player can pass through without anything happening.
@export var enterable: bool = true
## Colour of the rim's light and mist (see [member auto_rim_color]).
@export var rim_color: Color = Color(1.0, 0.86, 0.62):
	set(value):
		rim_color = value
		if _material != null:
			_material.set_shader_parameter(&"rim_color", value)
		if _glow != null:
			_glow.light_color = value
## Set [member rim_color] from the other world's render shortly after opening.
@export var auto_rim_color: bool = true
## Radius (m) of the opening. The frame is never scaled: the surface, trigger and glow are
## resized instead, so the view through and the ride through stay true to scale.
@export var opening_radius: float = 1.4:
	set(value):
		opening_radius = maxf(value, 0.1)
		_apply_radius()

## True once [method open] has been called.
var is_open: bool = false

var _preview_mounted: bool = false
var _asleep: bool = false
var _material: ShaderMaterial = null
var _frames_until_rim_sample: int = -1

@onready var _surface: MeshInstance3D = $Surface
@onready var _glow: OmniLight3D = $Glow
@onready var _viewport: SubViewport = $PreviewViewport
@onready var _preview_camera: Camera3D = $PreviewViewport/PreviewCamera
@onready var _trigger: Area3D = $Trigger


func _ready() -> void:
	set_meta("verify_unit", "Portal")
	visible = false
	set_process(false)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_material = (_surface.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	_material.set_shader_parameter(&"preview", _viewport.get_texture())
	_material.set_shader_parameter(&"openness", 0.0)
	_surface.material_override = _material
	rim_color = rim_color
	_apply_radius()
	_trigger.body_entered.connect(_on_trigger_body_entered)
	_trigger.body_exited.connect(_on_trigger_body_exited)


func _process(_delta: float) -> void:
	_follow_viewer()
	if _frames_until_rim_sample > 0:
		_frames_until_rim_sample -= 1
		if _frames_until_rim_sample == 0:
			_sample_rim_color()


## Shows the portal and its preview and, when [member enterable], lets the player through.
## With [param instant] it is fully open at once instead of blooming. Calling it again is
## harmless; nothing closes it.
func open(instant: bool = false) -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_mount_preview()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if _asleep \
		else SubViewport.UPDATE_ALWAYS
	set_process(not _asleep)
	_follow_viewer()
	if auto_rim_color and _preview_mounted and DisplayServer.get_name() != "headless":
		_frames_until_rim_sample = RIM_SAMPLE_DELAY_FRAMES
	if instant:
		_set_openness(1.0)
	else:
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_openness, 0.0, 1.0, maxf(open_seconds, 0.01))
	# A player already standing in the ring when it opens goes through too.
	_check_bodies_inside.call_deferred()


## Stops (or restarts) drawing the view through an open portal, for a level kept asleep.
func set_asleep(asleep: bool) -> void:
	_asleep = asleep
	if not is_open:
		return
	set_process(not asleep)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if asleep \
		else SubViewport.UPDATE_ALWAYS


## Where the preview camera should be for a viewer at [param viewer] (global): the viewer's
## pose relative to the opening's centre, carried over to [member preview_view].
func preview_pose_for(viewer: Transform3D) -> Transform3D:
	var centre := global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * CENTRE_HEIGHT)
	return preview_view * centre.affine_inverse() * viewer


## The main colour of [param image]: pixels are sorted into hue buckets (greys in a bucket of
## their own, dark pixels ignored) and the average of the fullest bucket is returned, kept
## bright enough to glow. White when nothing counts.
static func dominant_color(image: Image) -> Color:
	if image == null or image.is_empty():
		return Color.WHITE
	var small := image.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	small.convert(Image.FORMAT_RGBA8)
	small.resize(COLOR_SAMPLE_SIZE, COLOR_SAMPLE_SIZE, Image.INTERPOLATE_BILINEAR)
	var counts := PackedInt32Array()
	counts.resize(HUE_BUCKETS + 1)
	var sums: Array[Color] = []
	sums.resize(HUE_BUCKETS + 1)
	sums.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y: int in COLOR_SAMPLE_SIZE:
		for x: int in COLOR_SAMPLE_SIZE:
			var pixel := small.get_pixel(x, y)
			if pixel.v < MIN_VALUE:
				continue
			var bucket := HUE_BUCKETS
			if pixel.s >= GREY_SATURATION:
				bucket = mini(int(pixel.h * HUE_BUCKETS), HUE_BUCKETS - 1)
			counts[bucket] += 1
			sums[bucket] += pixel
	var best := -1
	for bucket: int in counts.size():
		if counts[bucket] > 0 and (best < 0 or counts[bucket] > counts[best]):
			best = bucket
	if best < 0:
		return Color.WHITE
	var mean := sums[best] / float(counts[best])
	return Color.from_hsv(mean.h, mean.s, maxf(mean.v, 0.85))


func _follow_viewer() -> void:
	var viewer := get_viewport().get_camera_3d()
	if viewer == null:
		return
	_preview_camera.transform = preview_pose_for(viewer.global_transform)
	_preview_camera.fov = viewer.fov
	_preview_camera.near = viewer.near
	_preview_camera.far = viewer.far
	var screen := get_viewport().get_visible_rect().size * preview_scale
	var wanted := Vector2i(maxi(int(screen.x), 1), maxi(int(screen.y), 1))
	if _viewport.size != wanted:
		_viewport.size = wanted


func _apply_radius() -> void:
	if not is_node_ready() or _material == null:
		return
	var half := opening_radius * QUAD_PER_RADIUS
	var quad := QuadMesh.new()
	quad.size = Vector2(half, half) * 2.0
	_surface.mesh = quad
	_material.set_shader_parameter(&"half_size", half)
	_material.set_shader_parameter(&"radius", opening_radius)
	var trigger_shape := _trigger.get_node("CollisionShape3D") as CollisionShape3D
	var box := BoxShape3D.new()
	var face := TRIGGER_PER_RADIUS * opening_radius
	box.size = Vector3(face.x, face.y, TRIGGER_DEPTH)
	trigger_shape.shape = box
	_glow.omni_range = GLOW_PER_RADIUS * opening_radius


func _set_openness(value: float) -> void:
	_material.set_shader_parameter(&"openness", value)
	_glow.light_energy = 2.0 * value


func _sample_rim_color() -> void:
	rim_color = dominant_color(_viewport.get_texture().get_image())


func _mount_preview() -> void:
	if _preview_mounted or preview_scene == null:
		return
	_preview_mounted = true
	var preview := preview_scene.instantiate()
	TrimeshCache.prepare(preview)
	_viewport.add_child(preview)
	_place_view_at_anchors(preview)
	# Art scenes may bring their own camera; the portal's camera is the one that looks.
	_preview_camera.make_current()


func _place_view_at_anchors(preview: Node) -> void:
	if opens_onto == OtherEnd.NONE:
		return
	var plan := PortalPlacement.plan_for_art(preview, _viewport.find_world_3d().direct_space_state)
	var key := PortalPlacement.KEY_WAY_IN if opens_onto == OtherEnd.WAY_IN \
		else PortalPlacement.KEY_EXIT
	if not plan.has(key):
		push_warning("Portal: preview has no markers for the portal it opens onto")
		return
	preview_view = PortalPlacement.stepping_out_of(plan[key] as Transform3D)


func _check_bodies_inside() -> void:
	for body: Node3D in _trigger.get_overlapping_bodies():
		_on_trigger_body_entered(body)


func _on_trigger_body_entered(_body: Node3D) -> void:
	if not is_open or not enterable:
		return
	entered.emit()


func _on_trigger_body_exited(_body: Node3D) -> void:
	exited.emit()
