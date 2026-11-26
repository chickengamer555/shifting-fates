class_name LevelController
extends Node3D
## Root script of a gameplay level: puts the skater at the spawn, runs the level's dialogue
## and opens the portal once the gods are appeased.
##
## A level scene instances its art (from [code]Assets/[/code]) and adds a [Marker3D]
## [code]SpawnPoint[/code], a [Portal], an optional [code]UI/DialogueBox[/code] and any
## [InvisibleBarrier]s on top. On ready the controller:
## [br]- reuses a [Skater] found in the art, or instances one, places it at the spawn and
##   binds it to [member game_state] for its ability unlocks;
## [br]- turns off any camera the art brought along and looks through the skater's camera;
## [br]- hands the skater to every [InvisibleBarrier] so their dots react to it, and keeps
##   the skater camera's spring arm from bumping into them;
## [br]- creates [member goal] from [member game_state] and a [ScoreKeeper] scoring the
##   skater into it, and binds the [Hud] (when its scene exists) to both;
## [br]- mounts an [AudioBridge] so the skater and combo are heard;
## [br]- plays the [DialogueSequence] [member dialogue_id], with a [DialogueVoice] for the gods.
## [br]The HUD is hidden while any dialogue is on screen, so it never sits under the text.
## [br]Tricks are the gods' to give ([member trick_gate]): open, closed (the intro) or given
## when the level's opening dialogue ends (the tutorial), which [method GameState.grant_ability]
## records so they stay given. Without [member scoring] nothing scores (no combo, no points)
## and the HUD shows no score, goal or combo.
## With [member freeze_during_dialogue] the opening dialogue is also a cutscene
## ([method set_cutscene]): the skater is frozen until it ends.
## [br]Reaching the goal opens the portal. Riding through it (the camera following the
## skater through the opening, or [constant CROSSING_TIMEOUT] after the skater rode in)
## advances the level (when [member advances_level]), saves, and emits
## [signal level_completed] for the game flow.
## [br]Portals never close: the exit portal is already open at start when the player has
## passed this level before ([member level_number] below [member GameState.current_level])
## or everything is unlocked (the test hub).
## [br]The level art may carry a [code]Spawn[/code] and a [code]Portal[/code] marker
## ([member art_spawn_path], [member art_portal_path]). Then the way in, an always-open,
## not enterable [Portal] onto [member previous_art] ([code]ArrivalPortal[/code]), stands at
## [code]Spawn[/code], the skater starts a few metres in front of it heading for the
## [code]Portal[/code] marker, and the exit portal stands at that marker, facing the same
## way ([PortalPlacement] has the rule). Without markers the scene's
## [code]SpawnPoint[/code] and [code]Portal[/code] stay where they are.
## [br]Riding through is seamless and works both ways, through either face of a portal. When
## the player rides into an open portal (exit or way in) and the camera then passes through
## its opening, the level is left: through the exit forwards ([signal level_completed],
## [member exit_handoff]), through the way in back to the previous world
## ([signal level_left_back], [member back_handoff]). The handoff records the pose relative
## to the opening; the level arrived in puts the player out of the matching portal the same
## way ([method arrive_through] out of its way in, [method arrive_back_through] out of its
## exit), on the same side. A portal just ridden out of waits until the skater has left its
## trigger before it can be ridden again, so arriving never bounces straight back.
## [br]A level can be built ahead of time while another is played: made [member dormant]
## before it enters the tree, it builds everything but stays frozen (processing off, no
## sound, no dialogue, its portal views not drawn) until [method activate];
## [method deactivate] puts a level back to sleep. The game flow keeps the next and the
## previous level ready like this, so crossing a
## portal costs no loading.

## The player rode through the open portal. Progress is already saved, and
## [member exit_handoff] holds how they went through.
signal level_completed
## The player rode back through the way in. [member back_handoff] holds how.
signal level_left_back
## The exit portal opened (the goal was met, or it was open from the start). The game flow
## starts loading the next level then, so riding through needs no wait.
signal exit_opened
## A paint screen opened by [method open_repaint] closed (Done): the look is saved and shown.
signal repaint_finished

## When the player may do tricks in a level: always, never, or once the gods give them at
## the end of the level's opening dialogue (and on any later visit).
enum TrickGate { OPEN, CLOSED, AFTER_DIALOGUE }

const GAME_STATE := preload("res://autoload/game_state.gd")
const SKATER_SCENE := preload("res://scenes/player/skater.tscn")
## Instanced into the UI layer only if the file exists.
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
## Group every level joins; the pause menu finds the one on show here for Repaint.
const LEVEL_GROUP := &"levels"
## The paint screen Repaint opens (loaded when needed).
const REPAINT_SCENE_PATH := "res://scenes/paint/paint_creator.tscn"
const REPAINT_NODE_NAME := &"Repaint"
const PORTAL_SCENE := preload("res://scenes/world/portal.tscn")
## Keys of a handoff ([member exit_handoff], [method arrive_through]). Poses and directions
## are relative to the portal's opening, so they carry from one world to the next.
const HANDOFF_SKATER := &"skater"
const HANDOFF_VELOCITY := &"velocity"
const HANDOFF_HEADING := &"heading"
const HANDOFF_SPEED := &"speed"
const HANDOFF_CAMERA_BASIS := &"camera_basis"
const HANDOFF_CAMERA_PITCH := &"camera_pitch"
## The camera rig's pivot position, the camera's place on its arm and its field of view, so
## the first frame in the next world is seen from exactly where the last one in this world was.
const HANDOFF_CAMERA_PIVOT := &"camera_pivot"
const HANDOFF_CAMERA_OFFSET := &"camera_offset"
const HANDOFF_CAMERA_FOV := &"camera_fov"
## Seconds a field of view carried through a portal (a speed kick) takes to settle back.
const FOV_SETTLE_SECONDS := 0.3
## The crossing is checked after everything else has moved in a physics step, so the frame
## on which the camera first passes the opening is already drawn in the next world.
const CROSSING_CHECK_PRIORITY := 1000
## Marks the rider in the stencil buffer while riding through, so the portal surface never
## hides the part of the rider already through (see portal_rider_mask.gdshader).
const RIDER_MASK_SHADER := preload("res://scenes/world/shaders/portal_rider_mask.gdshader")
## Seconds a ride into a portal waits for the camera to follow through once the rider is no
## longer through the opening; then it is called off (the player turned back inside it).
const CROSSING_TIMEOUT := 2.0
## The camera counts as passing through the opening within this share of its radius.
const CROSSING_REACH := 1.3
## The camera's near plane counts as touching the opening this close to it (m).
const NEAR_MARGIN := 0.01

## Id of the [DialogueSequence] played on entering, e.g. [code]&"level_1"[/code]. Empty: none.
@export var dialogue_id: StringName = &""
## False for levels before the first numbered level (the intro), which must not advance.
@export var advances_level: bool = true
## Instance the HUD when its scene exists. Tests turn it off.
@export var show_hud: bool = true
## Play the opening dialogue as a cutscene: skater frozen, HUD hidden.
@export var freeze_during_dialogue: bool = false
@export var spawn_point_path: NodePath = ^"SpawnPoint"
@export var portal_path: NodePath = ^"Portal"
@export var ui_layer_path: NodePath = ^"UI"
@export var dialogue_box_path: NodePath = ^"UI/DialogueBox"
## Marker in the level art where the player arrives through the way in.
@export var art_spawn_path: NodePath = ^"Art/Spawn"
## Marker in the level art where the exit portal stands.
@export var art_portal_path: NodePath = ^"Art/Portal"
## The previous world's art, seen through the way in. Null: no way-in portal.
@export var previous_art: PackedScene = null
## This level's number in [GameState] (1 for level 1); 0 when it has none.
@export var level_number: int = 0
## When tricks may be done here (see [enum TrickGate]).
@export var trick_gate: TrickGate = TrickGate.OPEN
## Moves score here (combo, points). Off: nothing scores and the HUD shows no score.
@export var scoring: bool = true

## Progress store. Defaults to the [code]GameState[/code] autoload; tests inject their own.
var game_state: GAME_STATE = null
## The player's body in this level.
var skater: Skater = null
## Points needed to open the portal on this level.
var goal: LevelGoal = null
## Scores the skater's moves into [member goal].
var score_keeper: ScoreKeeper = null
var portal: Portal = null
## The always-open way in at the art's [code]Spawn[/code] marker, when there is one.
var arrival_portal: Portal = null
## How the player rode out through the exit (see [method arrive_through]); empty until then.
var exit_handoff: Dictionary = {}
## Set before the level enters the tree to have the player come out of the way in as they
## went into the previous world's exit: same speed, heading and view. Empty: a normal start.
var arrival_handoff: Dictionary = {}
## With [member arrival_handoff]: true when the player comes back from the next world, out
## of this level's exit, instead of out of its way in.
var arrival_via_exit: bool = false
## How the player rode back through the way in; empty until then.
var back_handoff: Dictionary = {}
## True while the level is built but asleep (see the class notes). Set before it enters the
## tree to build it asleep.
var dormant: bool = false
var dialogue_box: DialogueBox = null
## The HUD instance, when one was mounted.
var hud: Hud = null
## Forwards the skater and the combo to the [code]AudioDirector[/code].
var audio_bridge: AudioBridge = null
## Voices the gods' lines of the level's dialogue, once the dialogue starts.
var dialogue_voice: DialogueVoice = null

var _completed: bool = false
## The portal being ridden through (the skater is in its trigger), or null.
var _crossing: Portal = null
## Which side of [member _crossing]'s opening the camera started on (+1 or -1).
var _crossing_side: float = 0.0
## Seconds left for the camera to pass through.
var _crossing_left: float = 0.0
## True when the camera was on its starting side of the opening on the last step.
var _crossing_ahead: bool = false
## Portals that may be ridden into; one just ridden out of waits until the skater leaves it.
var _armed: Dictionary[Portal, bool] = {}
## True once the dialogue has been started (it runs once per level, not on every return).
var _dialogue_started: bool = false
## True while the dialogue playing was started as a cutscene.
var _dialogue_is_cutscene: bool = false
## The paint screen Repaint opened, or null; and whether the HUD showed before it.
var _repaint: PaintCreator = null
var _hud_before_repaint: bool = false
## Whether the dialogue box showed before Repaint hid it.
var _dialogue_before_repaint: bool = false
## The camera on show when Repaint opened (a cutscene's, or the skater's), shown again after.
var _camera_before_repaint: Camera3D = null
## The rider's stencil mark, laid over the skater's meshes while a crossing is under way.
var _rider_mask: ShaderMaterial = null


func _enter_tree() -> void:
	add_to_group(LEVEL_GROUP)
	# The art's collision, shared with every other copy of the same art (see TrimeshCache).
	TrimeshCache.prepare(self)


func _ready() -> void:
	if game_state == null:
		game_state = GameState
	process_physics_priority = CROSSING_CHECK_PRIORITY
	portal = get_node_or_null(portal_path) as Portal
	dialogue_box = get_node_or_null(dialogue_box_path) as DialogueBox
	_place_at_art_markers()
	_place_skater()
	_use_skater_camera()
	_track_barriers()
	_apply_trick_gate()
	game_state.level_changed.connect(_on_game_state_level_changed)
	game_state.ability_unlocked.connect(_on_game_state_ability_unlocked)
	goal = game_state.create_level_goal()
	goal.goal_reached.connect(_on_goal_reached)
	_mount_score_keeper()
	if show_hud:
		_mount_hud()
	for way: Portal in [portal, arrival_portal]:
		if way != null:
			_armed[way] = true
			way.entered.connect(_on_portal_entered.bind(way))
			way.exited.connect(_on_portal_exited.bind(way))
	if portal != null and portal_already_earned():
		open_portal(true)
	if dormant:
		_sleep()
		return
	_wake(arrival_handoff, arrival_via_exit)


## Wakes a [member dormant] level that was built ahead of time, now that it is in the world
## the player sees, and puts the player out of the portal [param handoff] says (see
## [member arrival_handoff], [member arrival_via_exit]).
func activate(handoff: Dictionary, via_exit: bool) -> void:
	if not dormant:
		return
	_wake(handoff, via_exit)


## Puts the level to sleep so it can be kept for the player to ride back into.
func deactivate() -> void:
	if dormant:
		return
	_set_crossing(null)
	if audio_bridge != null:
		audio_bridge.queue_free()
		audio_bridge = null
	_sleep()


## Only the skater and the portal views stop: switching the whole level's processing off
## would take every one of its bodies out of physics, and putting them back is slow.
func _sleep() -> void:
	dormant = true
	skater.set_input_enabled(false)
	skater.process_mode = Node.PROCESS_MODE_DISABLED
	for way: Portal in [portal, arrival_portal]:
		if way != null:
			way.set_asleep(true)
	if hud != null:
		hud.visible = false


func _wake(handoff: Dictionary, via_exit: bool) -> void:
	dormant = false
	_completed = false
	_set_crossing(null)
	skater.process_mode = Node.PROCESS_MODE_INHERIT
	for way: Portal in [portal, arrival_portal]:
		if way != null:
			way.set_asleep(false)
	if not handoff.is_empty():
		var through := portal if via_exit else arrival_portal
		if through != null:
			_arrive_out_of(through, handoff)
			_armed[through] = false
	_use_skater_camera()
	skater.set_input_enabled(true)
	_mount_audio_bridge()
	if hud != null:
		hud.visible = true
	if via_exit and not handoff.is_empty():
		_handle_returned()
	elif not _dialogue_started:
		_dialogue_started = true
		_start_dialogue()
	if portal != null and portal.is_open:
		# Tell the game flow again: it may only listen to the level being played.
		exit_opened.emit()


## Hook for subclasses: the player came back into this level from the next one.
func _handle_returned() -> void:
	pass


## Banks [param amount] extra points towards [member goal], e.g. from a level event.
func add_points(amount: int) -> void:
	goal.add_points(amount)


## Opens the portal (fully at once with [param instant]). Called when the goal is met;
## levels may also call it from a cutscene. It stays open.
func open_portal(instant: bool = false) -> void:
	if portal == null or portal.is_open:
		return
	portal.open(instant)
	exit_opened.emit()


## The player's pose, motion and view relative to the exit's opening, for the next level's
## [method arrive_through]. Empty without an exit portal.
func capture_exit_handoff() -> Dictionary:
	return capture_handoff(portal)


## The player's pose, motion and view relative to [param through]'s opening. Empty without
## that portal.
func capture_handoff(through: Portal) -> Dictionary:
	if through == null:
		return {}
	var inverse := PortalPlacement.opening(through.global_transform).affine_inverse()
	return {
		HANDOFF_SKATER: inverse * skater.global_transform,
		HANDOFF_VELOCITY: inverse.basis * skater.velocity,
		HANDOFF_HEADING: inverse.basis * skater.heading,
		HANDOFF_SPEED: skater.speed,
		HANDOFF_CAMERA_BASIS: inverse.basis * skater.camera_rig.global_basis,
		HANDOFF_CAMERA_PITCH: skater.camera_rig.spring_arm.rotation.x,
		HANDOFF_CAMERA_PIVOT: inverse * skater.camera_rig.global_position,
		HANDOFF_CAMERA_OFFSET: skater.camera.position,
		HANDOFF_CAMERA_FOV: skater.camera.fov,
	}


## Puts the skater out of the way in as [param handoff] (from the previous level's
## [method capture_exit_handoff]) went into the previous exit: the same pose, motion and view
## relative to the opening, so the ride carries on without a cut. Needs the way in.
func arrive_through(handoff: Dictionary) -> void:
	_arrive_out_of(arrival_portal, handoff)


## Puts the skater out of the exit as [param handoff] (from the next level's way in) went
## into that way in: coming back the way they rode.
func arrive_back_through(handoff: Dictionary) -> void:
	_arrive_out_of(portal, handoff)


func _arrive_out_of(through: Portal, handoff: Dictionary) -> void:
	if through == null or handoff.is_empty():
		return
	var out := PortalPlacement.stepping_out_of(through.global_transform)
	skater.global_transform = out * (handoff[HANDOFF_SKATER] as Transform3D)
	skater.set_heading(out.basis * (handoff[HANDOFF_HEADING] as Vector3))
	skater.set_speed(float(handoff[HANDOFF_SPEED]))
	skater.velocity = out.basis * (handoff[HANDOFF_VELOCITY] as Vector3)
	var rig := skater.camera_rig
	var view := out.basis * (handoff[HANDOFF_CAMERA_BASIS] as Basis)
	rig.rotation.y = view.get_euler().y
	rig.spring_arm.rotation.x = float(handoff[HANDOFF_CAMERA_PITCH])
	# The pivot and the camera's place on the arm exactly as they were, so the first frame
	# here is seen from where the last one there was (the arm only moves on its next step).
	if handoff.has(HANDOFF_CAMERA_PIVOT):
		rig.global_position = out * (handoff[HANDOFF_CAMERA_PIVOT] as Vector3)
		rig.camera.position = handoff[HANDOFF_CAMERA_OFFSET] as Vector3
	else:
		rig.global_position = skater.global_position + Vector3.UP * rig.pivot_height
		rig.camera.position = Vector3(0.0, 0.0, rig.spring_arm.spring_length)
	if handoff.has(HANDOFF_CAMERA_FOV):
		_carry_fov(rig.camera, float(handoff[HANDOFF_CAMERA_FOV]))


## Shows [param camera] at the field of view [param fov] carried through a portal, then
## eases it back to its own.
func _carry_fov(camera: Camera3D, fov: float) -> void:
	var own := camera.fov
	if is_equal_approx(own, fov):
		return
	camera.fov = fov
	var tween := create_tween()
	tween.tween_property(camera, "fov", own, FOV_SETTLE_SECONDS)


## True when the exit portal starts open: everything is unlocked (the test hub) or the
## player is already past this level.
func portal_already_earned() -> bool:
	if game_state.unlock_all:
		return true
	return level_number > 0 and game_state.current_level > level_number


## True when Repaint can open here: this level is on show (not dormant), has a skater
## and no paint screen is open.
func can_repaint() -> bool:
	return skater != null and not dormant and is_visible_in_tree() and _repaint == null


## Repaint: opens the paint screen on the skater where it stands, painting [param mode]
## (body or board), carrying on from the saved look and saving to
## [member GameState.appearance_path] on Done. Works while the game is paused. Emits
## [signal repaint_finished] after Done. Returns the paint screen, or null when it cannot open.
func open_repaint(mode: PaintCreator.Mode) -> PaintCreator:
	if not can_repaint():
		return null
	var scene := load(REPAINT_SCENE_PATH) as PackedScene
	var creator := scene.instantiate() as PaintCreator if scene != null else null
	if creator == null:
		push_warning("LevelController: no paint screen at %s" % REPAINT_SCENE_PATH)
		return null
	creator.name = REPAINT_NODE_NAME
	creator.mode = mode
	creator.save_path = game_state.appearance_path
	creator.target_rig = skater.rig
	creator.glide_from = skater.camera
	creator.finished.connect(_on_repaint_finished)
	# A paint screen that leaves without Done (the level is freed, say) still closes Repaint.
	creator.tree_exiting.connect(_on_repaint_exiting.bind(creator))
	_camera_before_repaint = get_viewport().get_camera_3d()
	_hud_before_repaint = hud != null and hud.visible
	if hud != null:
		hud.visible = false
	# The gods' lines would sit over the paint panel and the skater being painted.
	_dialogue_before_repaint = dialogue_box != null and dialogue_box.visible
	if dialogue_box != null:
		dialogue_box.visible = false
	_repaint = creator
	add_child(creator)
	return creator


## Starts or ends a cutscene: the skater loses (or gets back) its controls and the HUD hides
## (or shows again). The HUD is only on screen while the player is free to skate.
func set_cutscene(active: bool) -> void:
	skater.set_input_enabled(not active)
	if hud != null:
		hud.visible = not active


## True when the player may do tricks here now (see [member trick_gate]).
func tricks_allowed() -> bool:
	match trick_gate:
		TrickGate.CLOSED:
			return false
		TrickGate.AFTER_DIALOGUE:
			return game_state.is_ability_unlocked(GAME_STATE.TRICKS)
	return true


## The gods give the tricks (the end of the tutorial's dialogue): from now on, on every level.
func give_tricks() -> void:
	game_state.grant_ability(GAME_STATE.TRICKS)
	_apply_trick_gate()


## Plays [param sequence] in the dialogue box with the HUD hidden until it ends. With
## [param as_cutscene] the skater is frozen as well ([method set_cutscene]).
func play_dialogue(sequence: DialogueSequence, as_cutscene: bool) -> void:
	if dialogue_box == null or sequence == null:
		return
	_dialogue_is_cutscene = as_cutscene
	if as_cutscene:
		set_cutscene(true)
	elif hud != null:
		hud.visible = false
	dialogue_box.play(sequence)


## The [DialogueSequence] with [param id] from the dialogue library, or null (with a warning).
func find_dialogue(id: StringName) -> DialogueSequence:
	var sequence := DialogueLibrary.load_directory().get(id) as DialogueSequence
	if sequence == null:
		push_warning("LevelController: no dialogue sequence '%s'" % id)
	return sequence


## Hook for subclasses: the level's dialogue starts. By default plays [member dialogue_id].
func _begin_dialogue() -> void:
	if dialogue_id != &"":
		play_dialogue(find_dialogue(dialogue_id), freeze_during_dialogue)


## Hook for subclasses: [param line] of the level's dialogue appeared on screen.
func _handle_dialogue_line_started(_line: DialogueLine) -> void:
	pass


## Hook for subclasses: a dialogue line carrying [param event] started.
func _handle_dialogue_event(_event: StringName) -> void:
	pass


## Hook for subclasses: the level's dialogue ended.
func _handle_dialogue_finished() -> void:
	pass


func _place_at_art_markers() -> void:
	var spawn_marker := get_node_or_null(art_spawn_path) as Node3D
	if spawn_marker == null:
		return
	var portal_marker := get_node_or_null(art_portal_path) as Node3D
	var ring := {}
	if portal_marker != null:
		ring = PortalPlacement.find_ring(spawn_marker.get_parent(), portal_marker.global_position)
	var plan := PortalPlacement.plan(get_world_3d().direct_space_state,
		spawn_marker.global_position,
		portal_marker.global_position if portal_marker != null else null, ring)
	var spawn := get_node_or_null(spawn_point_path) as Node3D
	if spawn == null:
		spawn = Marker3D.new()
		spawn.name = String(spawn_point_path.get_name(spawn_point_path.get_name_count() - 1))
		add_child(spawn)
	spawn.global_transform = plan[PortalPlacement.KEY_START] as Transform3D
	if portal != null and plan.has(PortalPlacement.KEY_EXIT):
		portal.global_transform = plan[PortalPlacement.KEY_EXIT] as Transform3D
		if plan.has(PortalPlacement.KEY_EXIT_RADIUS):
			portal.opening_radius = float(plan[PortalPlacement.KEY_EXIT_RADIUS])
	if previous_art != null:
		_mount_arrival_portal(plan[PortalPlacement.KEY_WAY_IN] as Transform3D)


## The way in: looking back through it shows the previous world from its exit portal.
func _mount_arrival_portal(where: Transform3D) -> void:
	arrival_portal = PORTAL_SCENE.instantiate() as Portal
	arrival_portal.name = "ArrivalPortal"
	arrival_portal.enterable = true
	arrival_portal.preview_scene = previous_art
	arrival_portal.opens_onto = Portal.OtherEnd.EXIT
	arrival_portal.preview_scale = 0.5
	add_child(arrival_portal)
	arrival_portal.global_transform = where
	arrival_portal.open(true)


func _place_skater() -> void:
	skater = _find_skater(self)
	var spawn := get_node_or_null(spawn_point_path) as Node3D
	if skater == null:
		skater = SKATER_SCENE.instantiate() as Skater
		skater.name = "Skater"
		if spawn != null:
			skater.transform = global_transform.affine_inverse() * spawn.global_transform
		add_child(skater)
	elif spawn != null:
		skater.global_transform = spawn.global_transform
		skater.set_heading(-spawn.global_basis.z)
		skater.camera_rig.snap_behind(skater.global_position, skater.heading)
	skater.bind_progress(game_state)


func _use_skater_camera() -> void:
	for node: Node in find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if camera.get_viewport() == get_viewport() and camera != skater.camera:
			camera.current = false
	skater.camera.make_current()


func _track_barriers() -> void:
	for node: Node in get_tree().get_nodes_in_group(InvisibleBarrier.GROUP):
		if is_ancestor_of(node):
			var barrier := node as InvisibleBarrier
			barrier.track(skater)
			# The camera looks straight through the see-through walls instead of being pushed
			# in by them.
			skater.camera_rig.spring_arm.add_excluded_object(barrier.get_rid())


func _mount_score_keeper() -> void:
	score_keeper = ScoreKeeper.new()
	score_keeper.name = "ScoreKeeper"
	score_keeper.set_goal(goal)
	add_child(score_keeper)
	if scoring:
		score_keeper.bind(skater)


func _mount_audio_bridge() -> void:
	audio_bridge = AudioBridge.new()
	audio_bridge.name = "AudioBridge"
	add_child(audio_bridge)
	audio_bridge.bind(skater, score_keeper)


func _mount_hud() -> void:
	if not ResourceLoader.exists(HUD_SCENE_PATH):
		return
	var hud_scene := load(HUD_SCENE_PATH) as PackedScene
	hud = hud_scene.instantiate() as Hud if hud_scene != null else null
	if hud == null:
		push_warning("LevelController: %s is not a Hud scene" % HUD_SCENE_PATH)
		return
	var layer := get_node_or_null(ui_layer_path)
	(layer if layer != null else self).add_child(hud)
	hud.shows_score = scoring
	hud.bind(skater, score_keeper)


func _start_dialogue() -> void:
	_dialogue_started = true
	if dialogue_box == null:
		if trick_gate == TrickGate.AFTER_DIALOGUE:
			give_tricks()
		return
	dialogue_box.line_started.connect(_on_dialogue_box_line_started)
	dialogue_box.event_triggered.connect(_on_dialogue_box_event_triggered)
	dialogue_box.sequence_finished.connect(_on_dialogue_box_sequence_finished)
	dialogue_voice = DialogueVoice.new()
	dialogue_voice.name = "DialogueVoice"
	add_child(dialogue_voice)
	dialogue_voice.bind(dialogue_box)
	_begin_dialogue()
	if trick_gate == TrickGate.AFTER_DIALOGUE and not dialogue_box.is_playing():
		# No dialogue to wait for: nothing to hold the gift back.
		give_tricks()


static func _find_skater(node: Node) -> Skater:
	for child: Node in node.get_children():
		if child is Skater:
			return child as Skater
		var found := _find_skater(child)
		if found != null:
			return found
	return null


func _on_goal_reached() -> void:
	open_portal()


func _physics_process(delta: float) -> void:
	if _crossing == null or _completed or dormant:
		return
	_crossing_left -= delta
	# However slowly they ride, the crossing lasts while the rider is through the opening.
	if _in_opening(_crossing, skater.global_position).z * _crossing_side < 0.0:
		_crossing_left = CROSSING_TIMEOUT
	var camera := skater.camera
	var view := _in_opening(_crossing, camera.global_position)
	var flat := Vector2(view.x, view.y).length()
	# Left on the step the camera comes up to the opening from this side: once its near
	# plane would cut the surface (that frame would show this world behind the portal), or
	# it is through.
	var ahead := _near_gap(camera, _crossing) * _crossing_side
	var was_ahead := _crossing_ahead
	_crossing_ahead = view.z * _crossing_side > 0.0
	if was_ahead and ahead <= NEAR_MARGIN and flat < _crossing.opening_radius * CROSSING_REACH:
		_leave_through(_crossing)
	elif _crossing_left <= 0.0:
		_set_crossing(null)


## How far (m) in front of [param through]'s opening plane, on the camera's side (signed
## along the opening's +Z), the nearest corner of [param camera]'s near plane is.
static func _near_gap(camera: Camera3D, through: Portal) -> float:
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var half_h := camera.near * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w := half_h * aspect
	var view := camera.global_transform
	var centre := view.origin - view.basis.z * camera.near
	var inverse := PortalPlacement.opening(through.global_transform).affine_inverse()
	var side := signf((inverse * view.origin).z)
	if side == 0.0:
		side = 1.0
	var gap := INF
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := centre + view.basis.x * half_w * sx + view.basis.y * half_h * sy
			gap = minf(gap, (inverse * corner).z * side)
	return gap * side


## [param point] in [param through]'s opening frame (-Z is the way through).
static func _in_opening(through: Portal, point: Vector3) -> Vector3:
	return PortalPlacement.opening(through.global_transform).affine_inverse() * point


func _on_portal_entered(through: Portal) -> void:
	if _completed or dormant or _crossing != null or not _armed.get(through, true):
		return
	# The level is left when the view itself passes through, so the next world takes over
	# exactly where the opening already showed it, from whichever face it is ridden.
	var side := signf(_in_opening(through, skater.camera.global_position).z)
	if side == 0.0:
		side = signf(_in_opening(through, skater.global_position).z)
	_set_crossing(through)
	_crossing_side = side if side != 0.0 else 1.0
	_crossing_left = CROSSING_TIMEOUT
	_crossing_ahead = true


func _on_portal_exited(through: Portal) -> void:
	_armed[through] = true


## Starts ([param through]) or ends (null) a crossing. While one is under way the rider is
## marked so the portal surface draws around them, not over them.
func _set_crossing(through: Portal) -> void:
	_crossing = through
	if skater == null:
		return
	if _rider_mask == null:
		_rider_mask = ShaderMaterial.new()
		_rider_mask.shader = RIDER_MASK_SHADER
		_rider_mask.render_priority = Material.RENDER_PRIORITY_MIN
	for node: Node in skater.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if through != null and mesh.material_overlay == null:
			mesh.material_overlay = _rider_mask
		elif through == null and mesh.material_overlay == _rider_mask:
			mesh.material_overlay = null


## True while the rider is marked to show through a portal surface (a crossing).
func is_rider_masked() -> bool:
	return _rider_mask != null and _crossing != null


func _leave_through(through: Portal) -> void:
	_set_crossing(null)
	if through == arrival_portal:
		_completed = true
		back_handoff = capture_handoff(arrival_portal)
		level_left_back.emit()
	else:
		_complete()


func _complete() -> void:
	_completed = true
	exit_handoff = capture_exit_handoff()
	# Riding forwards again after coming back must not skip a level.
	if advances_level and game_state.current_level <= level_number:
		game_state.advance_level()
	elif advances_level and level_number == 0:
		game_state.advance_level()
	game_state.save_game()
	level_completed.emit()


func _on_dialogue_box_line_started(line: DialogueLine) -> void:
	_handle_dialogue_line_started(line)


func _on_dialogue_box_event_triggered(event: StringName) -> void:
	_handle_dialogue_event(event)


func _apply_trick_gate() -> void:
	if skater != null:
		skater.tricks_enabled = tricks_allowed()


func _on_game_state_level_changed(_level: int) -> void:
	_apply_trick_gate()


func _on_game_state_ability_unlocked(_id: StringName) -> void:
	_apply_trick_gate()


func _on_dialogue_box_sequence_finished() -> void:
	if trick_gate == TrickGate.AFTER_DIALOGUE:
		give_tricks()
	if _dialogue_is_cutscene:
		_dialogue_is_cutscene = false
		set_cutscene(false)
	elif hud != null:
		hud.visible = true
	_handle_dialogue_finished()


func _on_repaint_finished(_look: Appearance) -> void:
	var creator := _repaint
	if creator != null:
		creator.name = "%sClosing" % REPAINT_NODE_NAME
		creator.hide_ui()
		creator.queue_free()
	_close_repaint()


func _on_repaint_exiting(creator: PaintCreator) -> void:
	if creator == _repaint:
		_close_repaint()


func _close_repaint() -> void:
	if _repaint == null:
		return
	_repaint = null
	var camera := _camera_before_repaint
	_camera_before_repaint = null
	if is_instance_valid(camera) and camera.is_inside_tree():
		camera.make_current()
	elif skater != null:
		skater.camera.make_current()
	if hud != null:
		hud.visible = _hud_before_repaint
	if is_instance_valid(dialogue_box) and _dialogue_before_repaint:
		dialogue_box.visible = true
	repaint_finished.emit()
