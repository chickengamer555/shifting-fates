class_name SurfaceTable
extends Resource
## Decides what a piece of level geometry is made of, so the board can sound like it.
##
## [method resolve] looks at a collider and the few nodes above it, in this order:
## [br]1. metadata [code]surface[/code] (one of [constant SURFACE_IDS]) on the collider or an
## ancestor: an explicit choice always wins;
## [br]2. [member name_keywords] found in a node name or in the name or file of a mesh,
## material or texture on the collider (for example "Water", "Bark", "Light Wood", "Rock");
## [br]3. the Chickbry export's [code]chickbry_kind[/code] metadata through [member kind_surfaces]
## (a ramp is wood, a ground plane concrete even when it is drawn as a mirror);
## [br]4. a metallic material ([code]metal[/code] shader parameter of the Chickbry level
## shader, or [member BaseMaterial3D.metallic]) at or above [member metal_threshold];
## [br]5. [member default_surface].
## The game's table is [constant TABLE_PATH]; the mapping lives there as data.

enum Surface { CONCRETE, WOOD, METAL, GRASS, WATER }

const TABLE_PATH := "res://data/audio/surface_table.tres"
## Metadata ids, indexed by [enum Surface].
const SURFACE_IDS: Array[StringName] = [&"concrete", &"wood", &"metal", &"grass", &"water"]
const META_SURFACE := &"surface"
const META_KIND := &"chickbry_kind"
## Chickbry's level shader names its metalness uniform this.
const METAL_PARAM := &"metal"
## How many ancestors above the collider are read for metadata and names.
const MAX_DEPTH := 3

## Lower-case word found in a node, mesh, material or texture name -> [enum Surface].
@export var name_keywords: Dictionary[String, Surface] = {}
## Chickbry [code]chickbry_kind[/code] metadata value -> [enum Surface].
@export var kind_surfaces: Dictionary[String, Surface] = {}
## Materials at least this metallic sound like metal.
@export_range(0.0, 1.0) var metal_threshold: float = 0.5
## What anything unrecognised sounds like.
@export var default_surface: Surface = Surface.CONCRETE


## The game's table, or an empty one (everything [member default_surface]) if it is missing.
static func load_default() -> SurfaceTable:
	if ResourceLoader.exists(TABLE_PATH):
		var loaded := load(TABLE_PATH) as SurfaceTable
		if loaded != null:
			return loaded
	return SurfaceTable.new()


## The [enum Surface] for a metadata id such as [code]"wood"[/code]; -1 if unknown.
static func surface_from_id(id: Variant) -> int:
	if not (id is String or id is StringName):
		return -1
	return SURFACE_IDS.find(StringName(String(id).to_lower()))


## The id (e.g. [code]&"metal"[/code]) of [param surface]; empty if out of range.
static func surface_id(surface: int) -> StringName:
	if surface < 0 or surface >= SURFACE_IDS.size():
		return &""
	return SURFACE_IDS[surface]


## What [param collider] is made of (see the class description).
func resolve(collider: Object) -> Surface:
	var node := collider as Node
	if node == null:
		return default_surface
	var chain := _chain(node)
	for link: Node in chain:
		if link.has_meta(META_SURFACE):
			var explicit := surface_from_id(link.get_meta(META_SURFACE))
			if explicit >= 0:
				return explicit as Surface
	var materials := _materials(node)
	var named := _keyword_surface(_names(chain, node, materials))
	if named >= 0:
		return named as Surface
	for link: Node in chain:
		if link.has_meta(META_KIND):
			var kind := String(link.get_meta(META_KIND)).to_lower()
			if kind_surfaces.has(kind):
				return kind_surfaces[kind]
	for material: Material in materials:
		if _metalness(material) >= metal_threshold:
			return Surface.METAL
	return default_surface


## The collider and up to [constant MAX_DEPTH] ancestors.
static func _chain(node: Node) -> Array[Node]:
	var chain: Array[Node] = []
	var link := node
	while link != null and chain.size() <= MAX_DEPTH:
		chain.append(link)
		link = link.get_parent()
	return chain


## Every material on the collider itself (a mesh or CSG body) or on its direct mesh children.
static func _materials(node: Node) -> Array[Material]:
	var found: Array[Material] = []
	var holders: Array[Node] = [node]
	holders.append_array(node.get_children())
	for holder: Node in holders:
		if holder is GeometryInstance3D:
			var geometry := holder as GeometryInstance3D
			if geometry.material_override != null:
				found.append(geometry.material_override)
		if holder is MeshInstance3D:
			var mesh_instance := holder as MeshInstance3D
			var mesh := mesh_instance.mesh
			var count := mesh.get_surface_count() if mesh != null else 0
			for index: int in range(count):
				var material := mesh_instance.get_active_material(index)
				if material != null and not found.has(material):
					found.append(material)
	return found


## Lower-case names to search for keywords: nodes, meshes, materials and their textures.
static func _names(chain: Array[Node], node: Node, materials: Array[Material]) -> PackedStringArray:
	var names := PackedStringArray()
	for link: Node in chain:
		names.append(String(link.name))
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			if mesh != null:
				names.append(mesh.resource_name)
				names.append(mesh.resource_path.get_file())
	for material: Material in materials:
		names.append(material.resource_name)
		names.append(material.resource_path.get_file())
		if material is BaseMaterial3D:
			var texture := (material as BaseMaterial3D).albedo_texture
			if texture != null:
				names.append(texture.resource_name)
				names.append(texture.resource_path.get_file())
	var lowered := PackedStringArray()
	for entry: String in names:
		if not entry.is_empty():
			lowered.append(entry.to_lower())
	return lowered


## The surface of the first keyword (longest first, so "light wood" beats "wood") found in
## any of [param names]; -1 if none matches.
func _keyword_surface(names: PackedStringArray) -> int:
	var keywords: Array[String] = name_keywords.keys()
	keywords.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for keyword: String in keywords:
		for entry: String in names:
			if entry.contains(keyword):
				return name_keywords[keyword]
	return -1


static func _metalness(material: Material) -> float:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).metallic
	if material is ShaderMaterial:
		var value: Variant = (material as ShaderMaterial).get_shader_parameter(METAL_PARAM)
		if value is float or value is int:
			return float(value)
	return 0.0
