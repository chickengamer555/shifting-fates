class_name MenuLivePan
extends Control
## The main menu's live background: the real level art, rendered in a SubViewport, with a
## camera slowly orbiting through it, fading to [member fade_color] between levels.
##
## Only one level is loaded at a time: every [member seconds_per_level] the current one is
## freed and the next of [member level_paths] is loaded. Each level is shown as scenery only:
## its cameras and character bodies are stripped and the viewport's physics space is paused.
## The camera path is worked out from the level's meshes: an orbit around their centre at a
## height above the floor, its radius slowly breathing in and out (a dolly). Meshes wider than
## [member floor_extent] (ground planes) count as floor, not as scenery to frame. A level may
## carry its own [Path3D]; then the camera travels along that instead.

## Emitted when a level has been loaded and the camera placed in it.
signal level_loaded(path: String)

const LEVEL_ONE := "res://Assets/Levels/level 1.tscn"
const LEVEL_TWO := "res://Assets/Levels/level 2.tscn"
const LEVEL_THREE := "res://Assets/Levels/level 3.tscn"
const INTRO_LEVEL := "res://Assets/Levels/intro level.tscn"
## Orbit radius used when a level has no scenery meshes to measure.
const FALLBACK_RADIUS := 20.0
## How far ahead on a [Path3D] the camera looks, in metres.
const PATH_LOOK_AHEAD := 10.0
## How close to straight up or down the view may get before look_at is skipped.
const VERTICAL_LIMIT := 0.999

## Level art scenes shown in turn. Paths (not preloaded scenes) so only one is in memory.
@export_file("*.tscn") var level_paths: PackedStringArray = [
	LEVEL_ONE, LEVEL_TWO, LEVEL_THREE, INTRO_LEVEL,
]:
	set(value):
		level_paths = value
		if is_node_ready():
			_restart()
## Seconds each level is on screen, fades included.
@export_range(0.1, 120.0, 0.1, "suffix:s") var seconds_per_level: float = 14.0
## Seconds of the fade out of a level, and of the fade in of the next.
@export_range(0.0, 10.0, 0.05, "suffix:s") var fade_seconds: float = 1.2
@export var fade_color: Color = Color.WHITE
## Orbit speed of the camera around the level.
@export_range(0.0, 90.0, 0.5, "suffix:deg/s") var orbit_degrees_per_second: float = 5.0
## Orbit radius as a fraction of the scenery's horizontal half-diagonal.
@export_range(0.1, 3.0, 0.05) var orbit_radius_scale: float = 0.8
## How much the radius breathes in and out, as a fraction of it.
@export_range(0.0, 0.9, 0.01) var dolly_fraction: float = 0.15
## Seconds for one in-and-out of the dolly.
@export_range(1.0, 120.0, 0.5, "suffix:s") var dolly_seconds: float = 24.0
## Camera height above the floor as a fraction of the scenery's height.
@export_range(0.0, 2.0, 0.05) var height_fraction: float = 0.55
## The camera never comes closer to the floor than this.
@export_range(0.5, 100.0, 0.5, "suffix:m") var min_floor_clearance: float = 6.0
## Meshes wider than this are floor (ground planes), not scenery.
@export_range(10.0, 100000.0, 10.0, "suffix:m") var floor_extent: float = 2000.0
## Camera speed along a level's own [Path3D].
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var path_speed: float = 6.0

## Index in [member level_paths] of the level on screen; -1 when none.
var level_index: int = -1
## Levels loaded since the list was set, the first one included.
var levels_shown: int = 0
## Path of the level on screen; empty when none.
var current_level_path: String = ""
## Levels currently in the viewport (1 while panning, 0 with no levels).
var loaded_level_count: int:
	get:
		return _level_slot.get_child_count()
## Cameras of the level art that would draw into this background (stripped, so 0). Cameras
## of the art's own inner viewports (a mirror floor's reflection camera) do not count.
var level_camera_count: int:
	get:
		if _level == null:
			return 0
		var count := 0
		for node: Node in _level.find_children("*", "Camera3D", true, false):
			if node.get_viewport() == _viewport:
				count += 1
		return count
## True while the viewport's physics space is switched off.
var physics_paused: bool:
	get:
		return not PhysicsServer3D.space_is_active(_viewport.find_world_3d().space)
## Height of the camera above the level's floor.
var camera_clearance: float:
	get:
		return _camera.global_position.y - _floor_y
## Distance the camera moved since the level was loaded.
var camera_travel: float:
	get:
		return _camera.global_position.distance_to(_start_position)

var _level: Node3D = null
var _path: Path3D = null
var _elapsed: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _radius: float = FALLBACK_RADIUS
var _floor_y: float = 0.0
var _height: float = 0.0
var _start_angle: float = 0.0
var _start_position: Vector3 = Vector3.ZERO

@onready var _viewport: SubViewport = %Viewport
@onready var _level_slot: Node3D = %LevelSlot
@onready var _camera: Camera3D = %PanCamera
@onready var _fade: ColorRect = %Fade


func _ready() -> void:
	set_meta("verify_unit", "MenuLivePan")
	PhysicsServer3D.space_set_active(_viewport.find_world_3d().space, false)
	_restart()


func _process(delta: float) -> void:
	if _level == null:
		_fade.color.a = 0.0
		return
	_elapsed += delta
	if _elapsed >= seconds_per_level:
		_elapsed = fmod(_elapsed, seconds_per_level)
		_show_level((level_index + 1) % level_paths.size())
	_place_camera()
	_fade.color = Color(fade_color, _fade_alpha())


func _restart() -> void:
	levels_shown = 0
	_elapsed = 0.0
	_free_level()
	level_index = -1
	current_level_path = ""
	if not level_paths.is_empty():
		_show_level(0)


func _show_level(index: int) -> void:
	_free_level()
	level_index = index
	current_level_path = level_paths[index]
	var scene := load(current_level_path) as PackedScene
	if scene == null:
		return
	var level := scene.instantiate() as Node3D
	if level == null:
		return
	_strip(level)
	_level = level
	_level_slot.add_child(level)
	_path = _find_path(level)
	_frame_level(level)
	levels_shown += 1
	_place_camera()
	_start_position = _camera.global_position
	level_loaded.emit(current_level_path)


func _free_level() -> void:
	_path = null
	if _level == null:
		return
	_level_slot.remove_child(_level)
	_level.queue_free()
	_level = null


## Removes what would make the art more than scenery: its cameras (one is current) and any
## character bodies (a skater) with their scripts.
func _strip(level: Node) -> void:
	for type: String in ["CharacterBody3D", "Camera3D"]:
		for node: Node in level.find_children("*", type, true, false):
			if is_instance_valid(node):
				node.get_parent().remove_child(node)
				node.free()


func _find_path(level: Node) -> Path3D:
	var paths := level.find_children("*", "Path3D", true, false)
	for node: Node in paths:
		var path := node as Path3D
		if path.curve != null and path.curve.get_baked_length() > 0.0:
			return path
	return null


## Measures the level's meshes and sets the orbit's centre, radius, floor and height.
func _frame_level(level: Node3D) -> void:
	var scenery := AABB()
	var has_scenery := false
	var floor_top := -INF
	var lowest := INF
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
		if maxf(box.size.x, box.size.z) > floor_extent:
			floor_top = maxf(floor_top, box.end.y)
		elif has_scenery:
			scenery = scenery.merge(box)
		else:
			scenery = box
			has_scenery = true
	_floor_y = floor_top if floor_top > -INF else (lowest if lowest < INF else 0.0)
	if not has_scenery:
		_center = Vector3(0.0, _floor_y, 0.0)
		_radius = FALLBACK_RADIUS
		_height = _floor_y + min_floor_clearance
		return
	_center = scenery.get_center()
	var half_diagonal := Vector2(scenery.size.x, scenery.size.z).length() * 0.5
	_radius = maxf(half_diagonal * orbit_radius_scale, FALLBACK_RADIUS)
	var scenery_height := maxf(scenery.end.y - _floor_y, 0.0)
	_height = _floor_y + maxf(scenery_height * height_fraction, min_floor_clearance)
	_start_angle = randf() * TAU


func _place_camera() -> void:
	var target := _center
	var position_now: Vector3
	if _path != null:
		var curve := _path.curve
		var length := curve.get_baked_length()
		var offset := fmod(_elapsed * path_speed, length)
		position_now = _path.to_global(curve.sample_baked(offset))
		target = _path.to_global(curve.sample_baked(fmod(offset + PATH_LOOK_AHEAD, length)))
	else:
		var angle := _start_angle + deg_to_rad(orbit_degrees_per_second) * _elapsed
		var breath := 1.0 + dolly_fraction * sin(TAU * _elapsed / dolly_seconds)
		position_now = _center + Vector3(cos(angle), 0.0, sin(angle)) * _radius * breath
		position_now.y = _height
	position_now.y = maxf(position_now.y, _floor_y + min_floor_clearance)
	_camera.global_position = position_now
	if not position_now.is_equal_approx(target):
		var to_target := (target - position_now).normalized()
		if absf(to_target.dot(Vector3.UP)) < VERTICAL_LIMIT:
			_camera.look_at(target, Vector3.UP)


## Fades out over the last [member fade_seconds] of a level and in over its first ones.
func _fade_alpha() -> float:
	var fade := minf(fade_seconds, seconds_per_level * 0.5)
	if fade <= 0.0:
		return 0.0
	if _elapsed > seconds_per_level - fade:
		return clampf((_elapsed - (seconds_per_level - fade)) / fade, 0.0, 1.0)
	return clampf(1.0 - _elapsed / fade, 0.0, 1.0)
