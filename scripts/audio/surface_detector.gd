class_name SurfaceDetector
extends RefCounted
## Finds the [enum SurfaceTable.Surface] under a [CharacterBody3D], once per physics frame.
##
## [method detect] reads the floor contact that [code]move_and_slide()[/code] left behind (a
## slide collision whose normal is within the body's floor angle); when there is none it casts
## a ray [member probe_depth] metres straight down from the body, on the body's own collision
## mask. The collider found is resolved through [member table]; each collider is resolved only
## once and cached. With nothing below it keeps the last surface, so a hop does not flicker
## the sound.

## Metres below the body's origin the fallback ray reaches.
const DEFAULT_PROBE_DEPTH := 1.2
## Height above the origin the fallback ray starts at, so a body resting on the floor still
## hits it.
const PROBE_LIFT := 0.3

## Name to surface mapping. Null means [method SurfaceTable.load_default].
var table: SurfaceTable = null
var probe_depth: float = DEFAULT_PROBE_DEPTH
## The last surface found.
var surface: SurfaceTable.Surface = SurfaceTable.Surface.CONCRETE
## The collider the last surface came from (null before the first hit).
var last_collider: Object = null

var _cache: Dictionary[int, SurfaceTable.Surface] = {}


func _init(surface_table: SurfaceTable = null) -> void:
	table = surface_table if surface_table != null else SurfaceTable.load_default()
	surface = table.default_surface


## The surface under [param body] (see the class description).
func detect(body: CharacterBody3D) -> SurfaceTable.Surface:
	if body == null or not body.is_inside_tree():
		return surface
	var collider := _floor_collider(body)
	if collider == null:
		collider = _ray_collider(body)
	if collider != null:
		surface = surface_of(collider)
		last_collider = collider
	return surface


## [param collider]'s surface, resolved once and then cached.
func surface_of(collider: Object) -> SurfaceTable.Surface:
	var key := collider.get_instance_id()
	if not _cache.has(key):
		_cache[key] = table.resolve(collider)
	return _cache[key]


static func _floor_collider(body: CharacterBody3D) -> Object:
	var up := body.up_direction
	for index: int in range(body.get_slide_collision_count()):
		var hit := body.get_slide_collision(index)
		if hit != null and hit.get_angle(0, up) <= body.floor_max_angle + 0.01:
			return hit.get_collider()
	return null


func _ray_collider(body: CharacterBody3D) -> Object:
	var space := body.get_world_3d().direct_space_state
	var start := body.global_position + body.up_direction * PROBE_LIFT
	var query := PhysicsRayQueryParameters3D.create(
		start, body.global_position - body.up_direction * probe_depth, body.collision_mask,
		[body.get_rid()])
	var hit := space.intersect_ray(query)
	return hit.get("collider") as Object if not hit.is_empty() else null
