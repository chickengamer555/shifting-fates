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
## [br]With [member preview_from] (and [member preview_toward]) naming nodes of the preview
## scene, e.g. the art's [code]Spawn[/code] and [code]Portal[/code] markers, the view is
## placed there instead of at [member preview_view].
## [br]With [member auto_rim_color] the rim takes the other world's main colour
## ([method dominant_color] of its render) a moment after opening.
## [br]The [code]Trigger[/code] (layer 5 [code]trigger[/code], watching layer 2
## [code]player[/code]) emits [signal entered] the first time a player body passes through an
## open, [member enterable] portal. Works headless: the viewport simply renders nothing.

## The player passed through the open portal. Emitted at most once.
signal entered

## Height of the opening's centre above the portal's origin (metres).
const CENTRE_HEIGHT := 1.9
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
## with the viewer around this point. Replaced when [member preview_from] is found.
@export var preview_view: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
## Node of [member preview_scene] (path from its root) to stand at instead, e.g. ^"Spawn".
@export var preview_from: NodePath = ^""
## Node of [member preview_scene] to look towards from [member preview_from] (level, no
## tilt). Empty or missing: keep [member preview_view]'s facing.
@export var preview_toward: NodePath = ^""
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

## True once [method open] has been called.
var is_open: bool = false

var _used: bool = false
var _preview_mounted: bool = false
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
	_trigger.body_entered.connect(_on_trigger_body_entered)


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
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
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
	_viewport.add_child(preview)
	_place_view_at_anchors(preview)
	# Art scenes may bring their own camera; the portal's camera is the one that looks.
	_preview_camera.make_current()


func _place_view_at_anchors(preview: Node) -> void:
	if preview_from.is_empty():
		return
	var from := preview.get_node_or_null(preview_from) as Node3D
	if from == null:
		push_warning("Portal: preview has no node '%s'" % preview_from)
		return
	# Markers stand where a portal's base would; the view is taken from its centre.
	var centre := from.global_position + Vector3.UP * CENTRE_HEIGHT
	var view := Transform3D(preview_view.basis, centre)
	var toward: Node3D = null
	if not preview_toward.is_empty():
		toward = preview.get_node_or_null(preview_toward) as Node3D
	if toward != null:
		var flat := toward.global_position - from.global_position
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			view.basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	preview_view = view


func _check_bodies_inside() -> void:
	for body: Node3D in _trigger.get_overlapping_bodies():
		_on_trigger_body_entered(body)


func _on_trigger_body_entered(_body: Node3D) -> void:
	if not is_open or _used or not enterable:
		return
	_used = true
	entered.emit()
