class_name PaintBrush
extends RefCounted
## Turns a [PaintStroke] into a [Decal] that sits on its part.
##
## Godot ray hits carry no UVs, so dabs are projected decals instead of texture writes:
## each decal is parented to the hit part, faces along the surface normal and tints a
## round soft brush (generated once at runtime, no image file) with the stroke colour.

## Metadata key that marks a node as a paint dab, so it can be cleared again.
const DAB_META := &"paint_dab"
const TEXTURE_SIZE := 64
## Fraction of the radius that is fully opaque before the soft edge starts.
const HARD_CORE := 0.7
## Decal depth as a multiple of the brush size, so dabs wrap over curved parts.
const DEPTH_FACTOR := 1.0
## How much a dab fades on surfaces turned away from its normal (0 none, 1 full).
const NORMAL_FADE := 0.3
## Normals closer than this to the up axis use a different helper axis to build a basis.
const PARALLEL_LIMIT := 0.99

static var _texture: ImageTexture


## The shared round brush texture, white with a soft alpha edge.
static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_round_brush())
	return _texture


## Builds an unparented decal for [param stroke], in its part's local space.
static func make_dab(stroke: PaintStroke) -> Decal:
	var decal := Decal.new()
	decal.set_meta(DAB_META, true)
	decal.texture_albedo = texture()
	decal.modulate = stroke.color
	decal.size = Vector3(stroke.size, stroke.size * DEPTH_FACTOR, stroke.size)
	decal.normal_fade = NORMAL_FADE
	decal.transform = Transform3D(_basis_facing(stroke.normal), stroke.position)
	return decal


## True when [param node] is a dab made by [method make_dab].
static func is_dab(node: Node) -> bool:
	return node is Decal and node.has_meta(DAB_META)


## A basis whose +Y is [param normal]; a decal projects along its local -Y.
static func _basis_facing(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var helper := Vector3.FORWARD if absf(up.dot(Vector3.UP)) > PARALLEL_LIMIT else Vector3.UP
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _round_brush() -> Image:
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEXTURE_SIZE, TEXTURE_SIZE) * 0.5
	var radius := TEXTURE_SIZE * 0.5
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var distance := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) / radius
			var alpha := 1.0 - smoothstep(HARD_CORE, 1.0, distance)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return image
