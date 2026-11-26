class_name Appearance
extends Resource
## How the player painted their body and board: one painted texture per paintable surface.
##
## Textures are PNG bytes keyed by layer id ([method PaintCanvas.layer_id]: the mesh's path
## from the rig root, or its [code]paint_id[/code] metadata, plus the surface index), saved
## inside the resource. [method apply_to] gives each saved surface of a rig its own material
## showing the saved texture; the rig's shared materials are never changed, and surfaces
## with nothing saved keep their own look.

## Version 2 holds painted textures. The old file name (version 1: colours and decal
## strokes, whose scripts are gone) is never read, so an old save shows as "no paint".
const DEFAULT_PATH := "user://appearance_v2.tres"
const FORMAT_VERSION := 2
## Text a saved file must contain to be read (its format version), checked before loading
## so a stale or foreign file never reaches the resource loader.
const VERSION_MARKER := "format_version = 2"

## Painted texture per layer id, as PNG bytes.
@export var textures: Dictionary[String, PackedByteArray] = {}
## Saved format, stamped by [method save] (0 until then, so the resource saver always
## writes it); files without [constant VERSION_MARKER] are ignored by [method load_from].
@export var format_version: int = 0


## Loads the appearance at [param path] and applies it to [param rig_root]. Returns the
## loaded appearance, or null (rig left as is) when there is no saved one.
static func apply_saved(rig_root: Node3D, path: String = DEFAULT_PATH) -> Appearance:
	var appearance := load_from(path)
	if appearance != null:
		appearance.apply_to(rig_root)
	return appearance


## Reads an appearance from [param path]; null (quietly) when missing, of an old format or
## not an Appearance.
static func load_from(path: String = DEFAULT_PATH) -> Appearance:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if not FileAccess.get_file_as_string(path).contains(VERSION_MARKER):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Appearance


## Writes this appearance to [param path].
func save(path: String = DEFAULT_PATH) -> Error:
	format_version = FORMAT_VERSION
	return ResourceSaver.save(self, path)


## True when a texture is saved for layer [param layer_id].
func has_layer(layer_id: String) -> bool:
	return textures.has(layer_id)


## Stores the PNG bytes of layer [param layer_id].
func set_layer_png(layer_id: String, png: PackedByteArray) -> void:
	textures[layer_id] = png


## The saved image of layer [param layer_id], or null when none (or unreadable).
func layer_image(layer_id: String) -> Image:
	if not textures.has(layer_id):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(textures[layer_id]) != OK:
		push_warning("Appearance: the texture of %s is not a readable PNG" % layer_id)
		return null
	return image


## A copy of this appearance (the PNG bytes are copied on write, so it is cheap).
func snapshot() -> Appearance:
	var copy := Appearance.new()
	copy.copy_from(self)
	return copy


## Makes this appearance equal to [param other] (keeps this object's identity).
func copy_from(other: Appearance) -> void:
	textures = other.textures.duplicate()


## Shows the saved textures on the paintable meshes under [param rig_root] (pass the
## skater's [code]Rig[/code]). Surfaces without a saved texture drop any paint material they
## wore. Returns how many surfaces now show a saved texture.
func apply_to(rig_root: Node3D) -> int:
	var applied := 0
	for mesh_instance in PaintCanvas.paintable_meshes(rig_root):
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var layer_id := PaintCanvas.layer_id(rig_root, mesh_instance, surface)
			var current := mesh_instance.get_surface_override_material(surface)
			if PaintLayer.is_paint_material(current):
				mesh_instance.set_surface_override_material(surface,
						PaintLayer.replaced_material(current))
			var image := layer_image(layer_id)
			var layer := PaintLayer.create(mesh_instance, surface, layer_id)
			if image == null or layer == null:
				continue
			layer.load_image(image)
			layer.finalize_for_play()
			applied += 1
	return applied
