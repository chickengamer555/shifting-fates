class_name SurfaceColor
extends RefCounted
## The colour a world surface under or nearest to a point is SEEN in, worked out from the
## surface's own material, so level edges are drawn in the colour of the material nearest
## to them.
## [br]A plain material gives its colour: a Chickbry art material's [code]base_color[/code]
## (Vector3 or Color; its texture palette or image instead when it has one) or a
## [StandardMaterial3D]'s [code]albedo_color[/code]. A Chickbry material also shades as the
## art shader does: its own light ([code]diffusion[/code] + [code]ambience[/code] +
## [code]glow[/code]), a mirror's [code]reflection[/code] and, for see-through glass
## ([code]transparency[/code]), what lies behind it filtered by the glass. That is why the
## intro walkway, a pale pink glass over the red mirror ground, reads dark red.

## How far (m) below the point the surface is looked for.
const REACH := 600.0
## How far (m) [method nearest] looks around a point.
const NEAR_REACH := 300.0
const BASE_COLOR := &"base_color"
const ALBEDO_COLOR := &"albedo_color"
## Chickbry art material parameters (see the art's chickbry shaders), with their defaults.
const DIFFUSION := &"diffusion"
const AMBIENCE := &"ambience"
const GLOW := &"glow"
const REFLECTION := &"reflection"
const METAL := &"metal"
const TRANSPARENCY := &"transparency"
const CLOSED := &"closed"
const TEX_MODE := &"tex_mode"
const TEX_COLS := &"tex_cols"
const TEX_CUM := &"tex_cum"
const TEX_N := &"tex_n"
const TEX_SHADE := &"tex_shade"
const TEX_IMAGE := &"tex_image"
const DEFAULT_DIFFUSION := 0.8
const DEFAULT_AMBIENCE := 0.2
const TEX_PALETTE := 1
const TEX_PICTURE := 2
## What a mirror is taken to reflect: a mid grey, so a metal mirror reads as its own hue
## at about half brightness (the shader tints the reflected world by the metal's colour).
const MIRROR_WORLD := Color(0.5, 0.5, 0.5)
## How much of its own colour glass lays over what is seen through it (as the art shader).
const GLASS_TINT := 0.6
## How many see-through surfaces a look goes through before it stops.
const MAX_LAYERS := 3
## How far (m) past a see-through surface the look carries on from.
const STEP_THROUGH := 0.01

## Average colours of texture images, by the texture's instance id.
static var _image_colors: Dictionary[int, Color] = {}
## Uniform names of each shader, by the shader's instance id.
static var _uniforms: Dictionary[int, Dictionary] = {}


## The colour the first surface within [constant REACH] below [param point] on
## [param mask] is seen in, skipping the bodies in [param exclude]; null when there is none
## or it has no readable colour.
static func below(space: PhysicsDirectSpaceState3D, point: Vector3, mask: int,
		exclude: Array[RID] = []) -> Variant:
	var hit := _cast(space, point, Vector3.DOWN, REACH, mask, exclude)
	if hit.is_empty():
		return null
	return _seen(space, hit, Vector3.DOWN, mask, exclude, 0)


## The colour the closest surface around [param point] (looked for in 26 directions, within
## [constant NEAR_REACH] m) on [param mask] is seen in, skipping the bodies in
## [param exclude]; null when nothing readable is near.
static func nearest(space: PhysicsDirectSpaceState3D, point: Vector3, mask: int,
		exclude: Array[RID] = []) -> Variant:
	var best: Variant = null
	var best_distance := INF
	for x: int in [-1, 0, 1]:
		for y: int in [-1, 0, 1]:
			for z: int in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				var direction := Vector3(x, y, z).normalized()
				var hit := _cast(space, point, direction, NEAR_REACH, mask, exclude)
				if hit.is_empty():
					continue
				var distance := point.distance_to(hit["position"] as Vector3)
				if distance >= best_distance:
					continue
				var color: Variant = _seen(space, hit, direction, mask, exclude, 0)
				if color != null:
					best = color
					best_distance = distance
	return best


## The plain colour of the first mesh with a readable material on or under [param object].
static func of_object(object: Node) -> Variant:
	var material := material_of(object)
	return of_material(material) if material != null else null


## The first material with a readable colour on or under [param object], or null.
static func material_of(object: Node) -> Material:
	if object == null:
		return null
	var meshes: Array[Node] = [object]
	meshes.append_array(object.find_children("*", "MeshInstance3D", true, false))
	for node: Node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null:
			continue
		if of_material(mesh_node.material_override) != null:
			return mesh_node.material_override
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			var surface := mesh_node.get_active_material(0)
			if of_material(surface) != null:
				return surface
	return null


## The colour a material paints with (its texture's average colour when it is textured),
## or null.
static func of_material(material: Material) -> Variant:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		var value: Variant = shader_material.get_shader_parameter(BASE_COLOR)
		var base: Variant = null
		if value is Vector3:
			var v := value as Vector3
			base = Color(v.x, v.y, v.z)
		elif value is Color:
			base = value as Color
		if base == null:
			return null
		var textured: Variant = _texture_color(shader_material)
		return textured if textured != null else base
	var standard := material as BaseMaterial3D
	if standard != null:
		return standard.albedo_color
	return null


## The colour [param material] is seen in with [param behind] showing through it (when it
## is see-through; null = nothing behind), or null when it has no readable colour.
static func seen_through(material: Material, behind: Variant) -> Variant:
	var plain: Variant = of_material(material)
	if plain == null:
		return null
	var base := plain as Color
	var shade := _shading(material)
	var own := shade["own"] as float
	var glow := shade["glow"] as float
	var rw := shade["reflection"] as float
	var tw := shade["transparency"] as float
	var metal := shade["metal"] as float
	if rw + tw > 1.0:
		rw /= rw + tw
		tw = 1.0 - rw
	var lit := _rgb(base) * (own + glow)
	var rest := Vector3.ZERO
	if rw > 0.0:
		rest = _mirror_tint(_rgb(MIRROR_WORLD), _rgb(base), metal * (1.0 - tw)) * rw
	var back := _rgb(behind as Color) if behind != null else _rgb(base)
	var filt := Vector3.ONE.lerp(_rgb(base), GLASS_TINT)
	var front_share := 1.0 - rw - tw
	var result := lit * front_share + rest + back * filt * tw
	if tw > 0.0 and shade["closed"] as bool:
		# A solid: the ray passes its far face first, then the near one.
		result = lit * front_share + rest + result * filt * tw
	return Color(result.x, result.y, result.z, base.a)


## How the material shades: own light share, glow, reflection, transparency, metal, closed.
static func _shading(material: Material) -> Dictionary:
	var shade := {
		"own": 1.0, "glow": 0.0, "reflection": 0.0, "transparency": 0.0, "metal": 0.0,
		"closed": false,
	}
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		if not _has_uniform(shader_material, DIFFUSION):
			return shade
		var diffusion := _float(shader_material, DIFFUSION, DEFAULT_DIFFUSION)
		var ambience := _float(shader_material, AMBIENCE, DEFAULT_AMBIENCE)
		shade["own"] = clampf(diffusion + ambience, 0.0, 1.0)
		shade["glow"] = maxf(_float(shader_material, GLOW, 0.0), 0.0)
		shade["reflection"] = clampf(_float(shader_material, REFLECTION, 0.0), 0.0, 1.0)
		shade["transparency"] = clampf(_float(shader_material, TRANSPARENCY, 0.0), 0.0, 1.0)
		shade["metal"] = clampf(_float(shader_material, METAL, 0.0), 0.0, 1.0)
		var closed: Variant = shader_material.get_shader_parameter(CLOSED)
		shade["closed"] = closed as bool if closed is bool else _has_uniform(shader_material,
			CLOSED)
		return shade
	var standard := material as BaseMaterial3D
	if standard != null and standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		shade["transparency"] = 1.0 - standard.albedo_color.a
	return shade


## The art shader's metal tint of a reflected colour [param seen] by [param base].
static func _mirror_tint(seen: Vector3, base: Vector3, metal: float) -> Vector3:
	var tinted := seen * Vector3.ONE.lerp(base, 0.3 + 0.7 * metal)
	if metal > 0.0:
		var brightness := seen.dot(Vector3(0.299, 0.587, 0.114)) * 1.2
		tinted = tinted.lerp(base * brightness, 0.6 * metal)
	return tinted


## The colour the surface at [param hit] is seen in, looking along [param direction];
## see-through surfaces show what the look meets behind them.
static func _seen(space: PhysicsDirectSpaceState3D, hit: Dictionary, direction: Vector3,
		mask: int, exclude: Array[RID], layer: int) -> Variant:
	var material := material_of(hit["collider"] as Node)
	if material == null:
		return null
	var behind: Variant = null
	if layer < MAX_LAYERS and (_shading(material)["transparency"] as float) > 0.0:
		var past: Array[RID] = exclude.duplicate()
		past.append(hit["rid"] as RID)
		var from := (hit["position"] as Vector3) + direction * STEP_THROUGH
		var next := _cast(space, from, direction, REACH, mask, past)
		if not next.is_empty():
			behind = _seen(space, next, direction, mask, past, layer + 1)
	return seen_through(material, behind)


static func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, direction: Vector3,
		reach: float, mask: int, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach, mask,
		exclude)
	query.collide_with_areas = true
	return space.intersect_ray(query)


## A textured Chickbry material's average texture colour, or null when it is untextured.
static func _texture_color(material: ShaderMaterial) -> Variant:
	var mode_value: Variant = material.get_shader_parameter(TEX_MODE)
	var mode := mode_value as int if mode_value is int else 0
	var shade := _float(material, TEX_SHADE, 1.0)
	if mode == TEX_PALETTE:
		var palette: Variant = _palette_color(material)
		return (palette as Color) * shade if palette != null else null
	if mode == TEX_PICTURE:
		var texture := material.get_shader_parameter(TEX_IMAGE) as Texture2D
		var average: Variant = _image_color(texture)
		return (average as Color) * shade if average != null else null
	return null


## The palette's colours mixed by each one's share of the surface.
static func _palette_color(material: ShaderMaterial) -> Variant:
	var count_value: Variant = material.get_shader_parameter(TEX_N)
	var count := count_value as int if count_value is int else 0
	var colors_value: Variant = material.get_shader_parameter(TEX_COLS)
	var shares_value: Variant = material.get_shader_parameter(TEX_CUM)
	if count <= 0 or not colors_value is PackedVector4Array:
		return null
	var colors := colors_value as PackedVector4Array
	var cumulative := shares_value as PackedFloat32Array if shares_value is PackedFloat32Array \
		else PackedFloat32Array()
	count = mini(count, colors.size())
	var sum := Vector3.ZERO
	var previous := 0.0
	for k: int in count:
		var upto := 1.0 if k == count - 1 or k >= cumulative.size() else cumulative[k]
		var share := clampf(upto - previous, 0.0, 1.0)
		previous = maxf(previous, upto)
		var c := colors[k]
		sum += Vector3(c.x, c.y, c.z) * share
	return Color(sum.x, sum.y, sum.z)


## The average colour of [param texture] (cached), or null.
static func _image_color(texture: Texture2D) -> Variant:
	if texture == null:
		return null
	var key := texture.get_instance_id()
	if _image_colors.has(key):
		return _image_colors[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var average := image.get_pixel(0, 0)
	_image_colors[key] = average
	return average


static func _has_uniform(material: ShaderMaterial, uniform: StringName) -> bool:
	if material.shader == null:
		return false
	var key := material.shader.get_instance_id()
	if not _uniforms.has(key):
		var names: Dictionary[StringName, bool] = {}
		for entry: Dictionary in material.shader.get_shader_uniform_list():
			names[StringName(entry.get("name", "") as String)] = true
		_uniforms[key] = names
	return (_uniforms[key] as Dictionary).has(uniform)


static func _float(material: ShaderMaterial, param: StringName, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(param)
	if value is float or value is int:
		return float(value)
	return fallback


static func _rgb(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)
