class_name LevelRide
extends Node
## Hosts the levels: each in a world of its own, so the levels on either side of the one
## being played can stay built and asleep, and riding through a portal (either way) is only a
## switch of which world is on screen: no loading, nothing rebuilt or moved, no freeze.
##
## Every level lives in its own full-screen [SubViewport] (with its own [World3D]: its own
## physics, light and sky) inside a [SubViewportContainer], a "view". Only the view of the
## level being played is shown, drawn and heard; the others are hidden and not drawn.
## [br]- [method host] puts a new level on screen in a fresh view;
## [br]- [method prepare] builds a level from its scene in the background: the scene loads
##   on a thread, the slow part (collision of detailed meshes, see [TrimeshCache]) is spread
##   over frames, then the level is built [member LevelController.dormant] in a hidden view
##   that is drawn once, which prepares its shaders before the player first sees it;
## [br]- [method keep] puts the level just left to sleep in its view, to ride back into;
## [br]- [method take] hands a kept level back, still asleep, for [method show_level] and
##   [method LevelController.activate];
## [br]- [method keep_only] frees the kept levels no longer next to the player;
##   [method discard] frees one level's view.
## The owner (the game flow, the test hub) wires each level through [param configure].
## [br]For [constant ARRIVAL_QUIET_SECONDS] after [method show_level] puts a built level on
## screen (a ride through a portal) nothing is built on the main thread (scene loads go on in
## their thread): the last step of a build (the level entering its view, its skater and look
## made) takes a few frames' time, and a stutter just as the player comes out of a portal
## would undo a seamless ride. A level [method host]ed from scratch builds the others at once.

## Microseconds a frame may spend building a level's collision ahead of time.
const BUILD_BUDGET_USEC := 6000
## Seconds after a level is shown before building on the main thread resumes.
const ARRIVAL_QUIET_SECONDS := 2.0

## Kept (asleep) levels by scene path.
var _kept: Dictionary[String, LevelController] = {}
## Scene paths being loaded, with the callable that wires the level once built.
var _loading: Dictionary[String, Callable] = {}
## Levels instantiated but still having their collision built, a little each frame.
var _building: Dictionary[String, LevelController] = {}
## Copies of the worlds the levels being built show through their portals, warmed first.
var _warming: Array[Node] = []
## Seconds left before main-thread building resumes, just after a level is shown.
var _quiet_left: float = 0.0


func _ready() -> void:
	set_process(false)


## Puts [param level] (not yet in the tree) on screen in a new view and returns the view.
func host(level: LevelController) -> SubViewportContainer:
	var view := _new_view()
	add_child(view)
	_viewport_of(view).add_child(level)
	show_level(level)
	_quiet_left = 0.0
	return view


## Shows [param level]'s view (drawn, heard, taking input) and hides every other view.
func show_level(level: LevelController) -> void:
	_quiet_left = ARRIVAL_QUIET_SECONDS
	for child: Node in get_children():
		var view := child as SubViewportContainer
		if view == null:
			continue
		var showing := view.is_ancestor_of(level)
		view.visible = showing
		var viewport := _viewport_of(view)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing \
			else SubViewport.UPDATE_DISABLED
		viewport.audio_listener_enable_3d = showing
		viewport.gui_disable_input = not showing


## True when the level from [param path] is kept and ready to take.
func has_level(path: String) -> bool:
	return _kept.has(path)


## Starts building the level from [param path] asleep, unless it is kept or under way.
## [param configure] is called with the new level before it enters the tree.
func prepare(path: String, configure: Callable) -> void:
	if path.is_empty() or _kept.has(path) or _loading.has(path) or _building.has(path):
		return
	if ResourceLoader.load_threaded_request(path) != OK:
		return
	_loading[path] = configure
	set_process(true)


## Puts [param level] (from [param path]) to sleep in its view, replacing a kept copy.
func keep(level: LevelController, path: String) -> void:
	if level == null or path.is_empty():
		return
	if _kept.has(path) and _kept[path] != level:
		discard(_kept[path])
	level.deactivate()
	_kept[path] = level


## The kept level from [param path], still asleep in its hidden view; null if none.
func take(path: String) -> LevelController:
	if not _kept.has(path):
		return null
	var level := _kept[path]
	_kept.erase(path)
	return level


## Frees every kept or under-way level whose path is not in [param paths].
func keep_only(paths: PackedStringArray) -> void:
	for path: String in _kept.keys():
		if not paths.has(path):
			discard(_kept[path])
			_kept.erase(path)
	for path: String in _loading.keys():
		if not paths.has(path):
			_loading.erase(path)
	for path: String in _building.keys():
		if not paths.has(path):
			_building[path].free()
			_building.erase(path)


## Frees [param level] with its view.
func discard(level: LevelController) -> void:
	if level == null or not is_instance_valid(level):
		return
	var view := _view_of(level)
	if view != null:
		view.queue_free()
	else:
		level.queue_free()


func _process(delta: float) -> void:
	if _quiet_left > 0.0:
		_quiet_left -= delta
		return
	# Spread the slow part (collision from detailed meshes) over frames.
	if not _warming.is_empty():
		if TrimeshCache.prepare(_warming[0], BUILD_BUDGET_USEC):
			_warming.pop_front().free()
		return
	for path: String in _building.keys():
		var building := _building[path]
		if not TrimeshCache.prepare(building, BUILD_BUDGET_USEC):
			return
		_building.erase(path)
		_kept[path] = building
		var view := _new_view()
		view.visible = false
		add_child(view)
		var viewport := _viewport_of(view)
		viewport.audio_listener_enable_3d = false
		viewport.gui_disable_input = true
		viewport.add_child(building)
		# Drawn once while hidden, so its shaders are ready before it is first seen.
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	for path: String in _loading.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var configure: Callable = _loading[path]
		_loading.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		var level := scene.instantiate() as LevelController if scene != null else null
		if level == null:
			continue
		level.dormant = true
		if configure.is_valid():
			configure.call(level)
		_building[path] = level
		_warm_views_of(level)
		return
	if _loading.is_empty() and _building.is_empty() and _warming.is_empty():
		set_process(false)


## Queues copies of the worlds [param level]'s portals will show, so their collision is
## built (and cached) a little at a time before the level is.
func _warm_views_of(level: LevelController) -> void:
	var scenes: Array[PackedScene] = [level.previous_art]
	var exit := level.get_node_or_null(level.portal_path) as Portal
	if exit != null:
		scenes.append(exit.preview_scene)
	for scene: PackedScene in scenes:
		if scene != null:
			_warming.append(scene.instantiate())


func _new_view() -> SubViewportContainer:
	var view := SubViewportContainer.new()
	view.name = "LevelView"
	view.stretch = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_PASS
	var viewport := SubViewport.new()
	viewport.name = "World"
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.audio_listener_enable_3d = true
	view.add_child(viewport)
	return view


static func _viewport_of(view: SubViewportContainer) -> SubViewport:
	return view.get_child(0) as SubViewport


func _view_of(level: Node) -> SubViewportContainer:
	var node := level.get_parent()
	while node != null and node != self:
		if node is SubViewportContainer and node.get_parent() == self:
			return node as SubViewportContainer
		node = node.get_parent()
	return null
