class_name SurfaceColor
extends RefCounted
## The colour of the world surface under or nearest to a point, read from the surface's own
## material: a Chickbry art material's [code]base_color[/code] (Vector3 or Color) or a
## [StandardMaterial3D]'s [code]albedo_color[/code]. Used so level edges are drawn in the
## colour of the material nearest to them.

## How far (m) below the point the surface is looked for.
const REACH := 600.0
## How far (m) [method nearest] looks around a point.
const NEAR_REACH := 300.0
const BASE_COLOR := &"base_color"
const ALBEDO_COLOR := &"albedo_color"


## The colour of the first surface within [constant REACH] below [param point] on
## [param mask], skipping the bodies in [param exclude]; null when there is none or it has
## no readable colour.
static func below(space: PhysicsDirectSpaceState3D, point: Vector3, mask: int,
		exclude: Array[RID] = []) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * REACH, mask,
		exclude)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return of_object(hit["collider"] as Node)


## The colour of the closest surface around [param point] (looked for in 26 directions,
## within [constant NEAR_REACH] m) on [param mask], skipping the bodies in [param exclude];
## null when nothing readable is near.
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
				var query := PhysicsRayQueryParameters3D.create(point,
					point + direction * NEAR_REACH, mask, exclude)
				query.collide_with_areas = true
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					continue
				var distance := point.distance_to(hit["position"] as Vector3)
				if distance >= best_distance:
					continue
				var color: Variant = of_object(hit["collider"] as Node)
				if color != null:
					best = color
					best_distance = distance
	return best


## The colour of the first mesh with a readable material on or under [param object].
static func of_object(object: Node) -> Variant:
	if object == null:
		return null
	var meshes: Array[Node] = [object]
	meshes.append_array(object.find_children("*", "MeshInstance3D", true, false))
	for node: Node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null:
			continue
		var color: Variant = of_material(mesh_node.material_override)
		if color == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			color = of_material(mesh_node.get_active_material(0))
		if color != null:
			return color
	return null


## The colour a material paints with, or null.
static func of_material(material: Material) -> Variant:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		var value: Variant = shader_material.get_shader_parameter(BASE_COLOR)
		if value is Vector3:
			var v := value as Vector3
			return Color(v.x, v.y, v.z)
		if value is Color:
			return value as Color
		return null
	var standard := material as BaseMaterial3D
	if standard != null:
		return standard.albedo_color
	return null
