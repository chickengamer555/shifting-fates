class_name SkaterRig
extends Node3D
## The skater's look: a white mannequin (Quaternius, CC0) on a white board (Kenney, CC0).
##
## Pure presentation, driven by the [Skater] through a few setters. Two layers animate it:
## [br]- an [AnimationTree] state machine picks the clip for [member anim_state] (idle
##   stance, push, crouch, air, trick, grab, land, grind, bail);
## [br]- a SkaterPose modifier ([code]skater_pose.gd[/code]) bends that clip into a skate
##   pose: hips dropped, head looking down the board, feet held on the deck by IK,
##   hands reaching for grabs.
## Tricks ([constant TRICK_MOTIONS]) are procedural, every value a smooth function of the
## trick's progress, so nothing pops:
## [br]- body flips turn the whole [code]TrickPivot[/code] (rider and board) about the
##   rider's centre of mass ([member flip_centre_height]) with a tuck: the board comes up to
##   the hips (knees up), the back rounds, the hands go to the shins; it opens out again
##   for the landing.
## [br]- board flips and shove-its turn only the [code]Board[/code] (about its long axis,
##   its vertical, or both) while the feet lift off it, then catch it. The feet move in the
##   rider's own frame while the board turns, so they never follow its spin.
## [br]Everything a trick or a state adds is blended: a trick that stops early (a bail, a
## landing part way round) eases its turn and tuck out instead of snapping, hand targets
## follow a critically damped spring, and pose values ease toward their targets.
## Spins turn the whole rig about the vertical ([method set_spin]); turns lean the pivot.
##
## Layout: the board's nose is -Z and the rider faces +X (regular stance, left foot
## forward). Every body and board part is its own [MeshInstance3D] in group
## [code]paintable[/code] with a UV0 unwrap and its own material (see [method _ready]).

## Every state [member anim_state] can take, with the clip it plays.
const STATE_CLIPS: Dictionary[StringName, StringName] = {
	&"idle": &"Idle_Loop",
	&"push": &"Idle_Loop",
	&"crouch": &"Idle_Loop",
	&"air": &"Jump_Loop",
	&"trick": &"Jump_Loop",
	&"grab": &"Jump_Loop",
	&"land": &"Idle_Loop",
	&"grind": &"Idle_Loop",
	&"bail": &"Hit_Chest",
}
const SKATER_POSE := preload("res://scripts/player/skater_pose.gd")
const CLIPS := preload("res://third_party/models/baked/mannequin_clips.res")
const FULL_TURN := TAU
## Per trick, what turns over the trick (radians): "body" the whole rider and board about
## the rider's side-to-side axis (front flips negative), "roll" the board about its long
## axis (kickflips positive), "yaw" the board about its vertical (shove-its). "flick" is
## how far the front foot flicks sideways off the board (m, + toward the toes).
const TRICK_MOTIONS := {
	&"front_flip": {"body": -FULL_TURN},
	&"back_flip": {"body": FULL_TURN},
	&"kickflip": {"roll": FULL_TURN, "flick": -0.07},
	&"heelflip": {"roll": -FULL_TURN, "flick": 0.07},
	&"front_kickflip": {"body": -FULL_TURN, "roll": FULL_TURN},
	&"front_heelflip": {"body": -FULL_TURN, "roll": -FULL_TURN},
	&"back_kickflip": {"body": FULL_TURN, "roll": FULL_TURN},
	&"back_heelflip": {"body": FULL_TURN, "roll": -FULL_TURN},
	&"pop_shove_it": {"yaw": PI},
	&"fs_shove_it": {"yaw": -PI},
	&"shove_it_360": {"yaw": FULL_TURN},
	&"varial_kickflip": {"yaw": PI, "roll": FULL_TURN, "flick": -0.05},
	&"varial_heelflip": {"yaw": -PI, "roll": -FULL_TURN, "flick": 0.05},
	&"tre_flip": {"yaw": FULL_TURN, "roll": FULL_TURN, "flick": -0.05},
	&"laser_flip": {"yaw": -FULL_TURN, "roll": -FULL_TURN, "flick": 0.05},
	&"hardflip": {"yaw": -PI, "roll": FULL_TURN, "flick": -0.04},
	&"inward_heelflip": {"yaw": PI, "roll": -FULL_TURN, "flick": 0.04},
}
## Each grab: the hand (0 front/left, 1 back/right), the board marker it holds, and how the
## board is held: extra lift (m), pitch (+ nose up), roll (+ toe edge up) in radians, and
## how far the spine twists toward the nose (+) or tail (-).
const GRAB_POSES := {
	&"melon_grab": {"hand": 0, "edge": &"GrabHeel", "lift": 0.0, "pitch": 0.0,
		"roll": -0.15, "twist": 0.0},
	&"indy_grab": {"hand": 1, "edge": &"GrabToe", "lift": 0.0, "pitch": 0.0,
		"roll": 0.12, "twist": 0.0},
	&"nosegrab": {"hand": 0, "edge": &"Nose", "lift": 0.06, "pitch": 0.45, "roll": 0.0,
		"twist": 0.35},
	&"tailgrab": {"hand": 1, "edge": &"Tail", "lift": 0.06, "pitch": -0.45, "roll": 0.0,
		"twist": -0.35},
	&"method_grab": {"hand": 0, "edge": &"GrabHeel", "lift": 0.1, "pitch": 0.1,
		"roll": -0.7, "twist": -0.2},
	&"mute_grab": {"hand": 0, "edge": &"GrabToeFront", "lift": 0.0, "pitch": 0.15,
		"roll": 0.3, "twist": 0.25},
	&"seatbelt_grab": {"hand": 0, "edge": &"Tail", "lift": 0.08, "pitch": -0.35,
		"roll": 0.0, "twist": -0.45},
	&"crail_grab": {"hand": 1, "edge": &"Nose", "lift": 0.08, "pitch": 0.35, "roll": 0.0,
		"twist": 0.45},
	&"stalefish_grab": {"hand": 1, "edge": &"GrabHeelBack", "lift": 0.04, "pitch": -0.1,
		"roll": -0.35, "twist": -0.15},
	&"roast_beef_grab": {"hand": 1, "edge": &"GrabHeelMid", "lift": 0.04, "pitch": 0.0,
		"roll": -0.3, "twist": 0.0},
}
## Grab markers made on the board if the scene lacks them (board space).
const EXTRA_MARKERS := {
	&"Nose": Vector3(0.0, 0.07, -0.36),
	&"Tail": Vector3(0.0, 0.07, 0.36),
	&"GrabToeFront": Vector3(0.14, 0.06, -0.15),
	&"GrabHeelBack": Vector3(-0.13, 0.06, 0.15),
	&"GrabHeelMid": Vector3(-0.13, 0.06, 0.05),
}
const LEFT := 0
const RIGHT := 1
## Seconds the state machine takes to blend between clips.
const CLIP_BLEND := 0.15
## The board turns about this point (board space): the middle of deck, trucks and wheels.
const BOARD_CENTRE := Vector3(0.0, -0.02, 0.0)
## Rest height of the TrickPivot above the rig (the scene's value).
const PIVOT_REST := Vector3(0.0, 0.9, 0.0)

@export_group("Lean")
## Roll at full lean (radians).
@export var max_lean: float = 0.3
## How quickly the lean follows the steering (1/s).
@export var lean_rate: float = 8.0

@export_group("Stance")
## How far the hips sit below standing height when cruising (m).
@export var stance_drop: float = 0.15
## How far the hips drop at a full jump charge, on top of the stance (m).
@export var crouch_depth: float = 0.28
## How quickly the pose follows its targets (1/s).
@export var pose_rate: float = 12.0

@export_group("Push kick")
## Seconds one push kick takes.
@export var kick_duration: float = 0.55

@export_group("Air")
## How far the board comes up to the rider in a grab or flip tuck (m).
@export var tuck_lift: float = 0.34
## Height of the rider's centre of mass above the rig, the point body flips turn about (m).
@export var flip_centre_height: float = 0.95
## How high the board pops in a board flip or shove-it (m).
@export var board_pop: float = 0.12
## How far the feet rise above the popped board while it turns under them (m).
@export var foot_gap: float = 0.16
## Seconds the landing crouch lasts.
@export var land_duration: float = 0.35
## How deep the landing crouch absorbs the impact (m of hip drop).
@export var land_depth: float = 0.2
## Seconds a bail stumble lasts.
@export var bail_duration: float = 0.9
## How quickly a trick that stopped early eases its turn and tuck out (1/s).
@export var settle_rate: float = 14.0
## Stiffness of the hand spring (1/s): higher reaches faster.
@export var hand_spring: float = 16.0

@export_group("Phase")
## Transparency of every body and board part while shifted (0 solid, 1 invisible).
@export_range(0.0, 1.0) var phased_transparency: float = 0.6

## State the animation follows: idle, push, crouch, air, trick, grab, land, grind or bail.
var anim_state: StringName = &"idle"

var _lean_target: float = 0.0
var _lean: float = 0.0
var _crouch: float = 0.0
var _airborne: bool = false
var _cruising: bool = false
var _grinding: bool = false
var _balance: float = 0.0
var _grab: StringName = &""
var _trick: StringName = &""
var _trick_progress: float = 0.0
## Time left in the current push kick, 0 when none.
var _kick_left: float = 0.0
var _land_left: float = 0.0
var _bail_left: float = 0.0
## Smoothed pose values, keyed like [method _pose_targets].
var _pose: Dictionary[StringName, float] = {}
## What the trick adds this frame (exact while it plays, easing out after it stops):
## body turn, board pitch/yaw/roll, tuck 0..1, feet off the board 0..1, board pop 0..1,
## front foot flick (m).
var _body_turn: float = 0.0
var _board_turn: Vector3 = Vector3.ZERO
var _tuck: float = 0.0
var _off: float = 0.0
var _pop: float = 0.0
var _flick: float = 0.0
## True while the same trick will repeat right after this one (keys held, air left): a
## body flip then stays tucked into the next instead of opening out.
var _chain: bool = false
var _was_chain: bool = false
## Tuck carried in from a chained flip, and the progress the tuck starts opening from.
var _carry_tuck: float = 0.0
var _release_from: float = 0.72
## Hands: spring position (TrickPivot space), velocity and weight, per hand.
var _hand_at: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _hand_speed: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _hand_weight: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _hand_weight_speed: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _board_rest: Transform3D
var _playback: AnimationNodeStateMachinePlayback

@onready var trick_pivot: Node3D = $TrickPivot
@onready var board: Node3D = $TrickPivot/Board
@onready var body: Node3D = $TrickPivot/Body
@onready var pose: SKATER_POSE = $TrickPivot/Body/Skeleton3D/SkaterPose
@onready var anim_tree: AnimationTree = $TrickPivot/Body/AnimationTree
@onready var foot_front: Marker3D = $TrickPivot/Board/FootFront
@onready var foot_back: Marker3D = $TrickPivot/Board/FootBack


func _ready() -> void:
	_board_rest = board.transform
	_add_markers()
	_own_materials()
	_build_tree()
	_pose = _pose_targets()
	for side in 2:
		_hand_at[side] = _rest_hand(side)
	_apply(0.0)


func _process(delta: float) -> void:
	_kick_left = maxf(_kick_left - delta, 0.0)
	if _cruising and _kick_left <= 0.0 and not _airborne:
		_kick_left = kick_duration
	_land_left = maxf(_land_left - delta, 0.0)
	_bail_left = maxf(_bail_left - delta, 0.0)
	_lean = lerpf(_lean, _lean_target, 1.0 - exp(-lean_rate * delta))
	_set_state(_pick_state())
	_settle(delta)
	_apply(delta)


## Lean into a turn: -1 full left, 1 full right.
func set_lean(amount: float) -> void:
	_lean_target = clampf(amount, -1.0, 1.0)


## Crouch depth 0..1 (the jump charge).
func set_crouch(amount: float) -> void:
	_crouch = clampf(amount, 0.0, 1.0)


## Plays one kick of the back foot on the ground.
func play_push() -> void:
	if _kick_left <= 0.0:
		_kick_left = kick_duration


## Keeps kicking while [param on] (the gentle W push).
func set_cruising(on: bool) -> void:
	_cruising = on


## Whether the board is off the ground.
func set_airborne(on: bool) -> void:
	_airborne = on


## Grinding a rail, with the balance bar's value -1..1 (leans that way).
func set_grind(on: bool, balance: float) -> void:
	_grinding = on
	_balance = clampf(balance, -1.0, 1.0) if on else 0.0


## Holds the grab [param grab_id] ([TrickCatalog] grab id), or none when empty.
func set_grab(grab_id: StringName) -> void:
	_grab = grab_id if GRAB_POSES.has(grab_id) else &""


## Whether the trick playing will repeat straight after it ends (see [member _chain]).
func set_trick_chain(on: bool) -> void:
	_was_chain = _chain
	if _chain and not on:
		# Let go late: open out from here rather than snapping open.
		_release_from = maxf(_trick_progress, 0.72)
	elif on:
		_release_from = 2.0
	_chain = on


## Turns the whole rig (rider and board) [param yaw] radians about the vertical: a spin.
func set_spin(yaw: float) -> void:
	rotation.y = yaw


## Touched down: a short crouch that absorbs the impact when [param clean], else a stumble.
func play_landing(clean: bool) -> void:
	if clean:
		_land_left = land_duration
	else:
		_bail_left = bail_duration
		_land_left = 0.0


## Poses the trick [param trick_id] at [param progress] 0..1. An empty id lets the last
## trick ease out.
func set_trick(trick_id: StringName, progress: float) -> void:
	var known := trick_id if TRICK_MOTIONS.has(trick_id) else &""
	var restarted := known != &"" and (known != _trick or progress < _trick_progress - 0.5)
	if restarted:
		# A flip straight after a chained one starts as tucked as the last one ended.
		_carry_tuck = _tuck if _was_chain else 0.0
		_release_from = 0.72 if not _chain else 2.0
	_trick = known
	_trick_progress = clampf(progress, 0.0, 1.0)
	if _trick_active():
		_follow_trick()
	_place_trick()


## How much of its full turn the trick [param trick_id] shows at [param progress] 0..1
## (0 = upright, 1 = all the way round). The [Skater] judges landings with the same curve,
## so what the player sees is what gets judged. 0 for an unknown id.
static func trick_turn(trick_id: StringName, progress: float) -> float:
	if not TRICK_MOTIONS.has(trick_id):
		return 0.0
	var p := clampf(progress, 0.0, 1.0)
	if (TRICK_MOTIONS[trick_id] as Dictionary).has("body"):
		return smoothstep(0.0, 0.85, p)
	return smoothstep(0.15, 0.7, p)


## The clip state the [AnimationTree] is in (follows [member anim_state]).
func clip_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## Distance from the grabbing hand to the board edge it grabs, or INF when not grabbing.
func grab_reach() -> float:
	if _grab.is_empty():
		return INF
	var entry: Dictionary = GRAB_POSES[_grab]
	var hand := &"hand_l" if int(entry["hand"]) == LEFT else &"hand_r"
	return pose.bone_global_position(hand).distance_to(_edge(_grab).global_position)


## See-through while shifted out of the world. Uses each part's
## [member GeometryInstance3D.transparency] (and paint decals' alpha), never
## [code]material_override[/code], so a painted [Appearance] is left intact.
func set_phased(on: bool) -> void:
	var value := phased_transparency if on else 0.0
	for part in find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).transparency = value
	for node in find_children("*", "Decal", true, false):
		var dab := node as Decal
		dab.modulate.a = 1.0 - value


## Gives every paintable part a material of its own, so painting one rig (or one part)
## never paints another that shares the baked mesh.
func _own_materials() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.is_in_group(&"paintable") and part.mesh != null:
			var material := part.mesh.surface_get_material(0)
			part.set_surface_override_material(0, material.duplicate() as Material)


func _add_markers() -> void:
	for marker_name: StringName in EXTRA_MARKERS:
		if board.has_node(NodePath(marker_name)):
			continue
		var marker := Marker3D.new()
		marker.name = marker_name
		marker.position = EXTRA_MARKERS[marker_name]
		board.add_child(marker)


func _build_tree() -> void:
	var machine := AnimationNodeStateMachine.new()
	for state: StringName in STATE_CLIPS:
		var clip := AnimationNodeAnimation.new()
		clip.animation = STATE_CLIPS[state]
		machine.add_node(state, clip)
	for from: StringName in STATE_CLIPS:
		for to: StringName in STATE_CLIPS:
			if from != to:
				var blend := AnimationNodeStateMachineTransition.new()
				blend.xfade_time = CLIP_BLEND
				machine.add_transition(from, to, blend)
	anim_tree.add_animation_library(&"", CLIPS)
	anim_tree.tree_root = machine
	anim_tree.active = true
	_playback = anim_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	_playback.start(anim_state)


func _pick_state() -> StringName:
	if _bail_left > 0.0:
		return &"bail"
	if _grinding:
		return &"grind"
	if _airborne:
		if not _grab.is_empty():
			return &"grab"
		return &"trick" if not _trick.is_empty() else &"air"
	if _land_left > 0.0:
		return &"land"
	if _crouch > 0.05:
		return &"crouch"
	if _kick_left > 0.0:
		return &"push"
	return &"idle"


func _set_state(state: StringName) -> void:
	if state == anim_state and clip_state() == state:
		return
	anim_state = state
	if _playback != null:
		_playback.travel(state)


## Pose values each state aims for (hips, spine, head, board lift and tilt).
func _pose_targets() -> Dictionary[StringName, float]:
	var targets: Dictionary[StringName, float] = {
		&"drop": stance_drop, &"bend": 0.15, &"twist": 0.3, &"head": 0.9, &"lift": 0.0,
		&"roll": 0.0, &"grab_pitch": 0.0, &"grab_roll": 0.0,
	}
	match anim_state:
		&"push":
			targets[&"drop"] = stance_drop + 0.08
			targets[&"bend"] = 0.3
			targets[&"twist"] = 0.75
			targets[&"head"] = 0.5
		&"crouch":
			targets[&"drop"] = stance_drop + crouch_depth * _crouch
			targets[&"bend"] = 0.15 + 0.45 * _crouch
		&"air":
			# Knees soft, board drawn up a little: never a straight-legged statue.
			targets[&"lift"] = 0.16
			targets[&"bend"] = 0.45
			targets[&"drop"] = stance_drop + 0.18
		&"grab":
			var entry: Dictionary = GRAB_POSES[_grab]
			targets[&"lift"] = tuck_lift + 0.08 + float(entry["lift"])
			targets[&"drop"] = 0.32
			targets[&"bend"] = 1.0
			targets[&"twist"] = 0.3 + float(entry["twist"])
			targets[&"grab_pitch"] = float(entry["pitch"])
			targets[&"grab_roll"] = float(entry["roll"])
		&"trick":
			targets[&"lift"] = 0.16
			targets[&"bend"] = 0.5
			targets[&"drop"] = stance_drop + 0.18
		&"land":
			# Quick down, slower up: the knees soak up the impact.
			var t := 1.0 - _land_left / land_duration
			var absorb := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.35, 1.0, t))
			targets[&"drop"] = stance_drop + land_depth * absorb
			targets[&"bend"] = 0.15 + 0.35 * absorb
		&"grind":
			targets[&"drop"] = stance_drop + 0.06
			targets[&"roll"] = -_balance * 0.45
			targets[&"bend"] = 0.2
		&"bail":
			targets[&"drop"] = stance_drop + 0.2
			targets[&"bend"] = 0.7
			targets[&"roll"] = 0.35 * sin(_bail_left * 14.0)
			targets[&"head"] = 0.4
	return targets


func _apply(delta: float) -> void:
	var targets := _pose_targets()
	var follow := 1.0 - exp(-pose_rate * delta) if delta > 0.0 else 1.0
	for key: StringName in targets:
		_pose[key] = lerpf(float(_pose.get(key, targets[key])), targets[key], follow)
	trick_pivot.rotation.z = -_lean * max_lean
	pose.pelvis_drop = _pose[&"drop"] + 0.12 * _tuck + 0.06 * _off
	pose.spine_bend = _pose[&"bend"] + 0.85 * _tuck + 0.25 * _off
	pose.spine_twist = _pose[&"twist"]
	pose.spine_roll = _pose[&"roll"]
	pose.head_yaw = _pose[&"head"]
	_place_trick()
	_place_feet()
	_place_hands(delta)


func _trick_active() -> bool:
	return not _trick.is_empty() and _airborne


## Sets the trick's contributions exactly from its progress.
func _follow_trick() -> void:
	var motion: Dictionary = TRICK_MOTIONS[_trick]
	var p := _trick_progress
	var turn := trick_turn(_trick, p)
	_body_turn = float(motion.get("body", 0.0)) * turn
	var board_turn := turn if not motion.has("body") else smoothstep(0.15, 0.7, p)
	_board_turn = Vector3(0.0, float(motion.get("yaw", 0.0)), float(motion.get("roll", 0.0)))
	_board_turn *= board_turn
	var turns_board := motion.has("yaw") or motion.has("roll")
	# Body flips: tuck in by a fifth of the way, open out over the last quarter.
	var tuck_in := maxf(smoothstep(0.0, 0.2, p), _carry_tuck)
	var tuck_out := 1.0 - smoothstep(_release_from, _release_from + 0.25, p)
	_tuck = tuck_in * tuck_out if motion.has("body") else 0.0
	# Board tricks: feet up before the board starts turning, back on once it is round.
	_off = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.7, 0.9, p)) \
			if turns_board else 0.0
	# The board pops up to the feet, rides up while it turns and comes down with them.
	_pop = smoothstep(0.0, 0.28, p) * (1.0 - smoothstep(0.68, 1.0, p)) \
			if turns_board and not motion.has("body") else 0.0
	_flick = float(motion.get("flick", 0.0)) * _bump(p, 0.02, 0.42)


## A trick that stopped (or landed part way round) eases its turn, tuck and lift out.
func _settle(delta: float) -> void:
	if _trick_active():
		_follow_trick()
		return
	var fade := 1.0 - exp(-settle_rate * delta)
	_body_turn = lerpf(wrapf(_body_turn, -PI, PI), 0.0, fade)
	_board_turn = Vector3(wrapf(_board_turn.x, -PI, PI), wrapf(_board_turn.y, -PI, PI),
		wrapf(_board_turn.z, -PI, PI)).lerp(Vector3.ZERO, fade)
	_tuck = lerpf(_tuck, 0.0, fade)
	_off = lerpf(_off, 0.0, fade)
	_pop = lerpf(_pop, 0.0, fade)
	_flick = lerpf(_flick, 0.0, fade)


## Board and pivot for the current trick, grab and tuck.
func _place_trick() -> void:
	if not is_node_ready():
		return
	# Body flip about the centre of mass: the pivot turns and slides so that point stays.
	trick_pivot.rotation.x = _body_turn
	var centre := Vector3.UP * flip_centre_height
	trick_pivot.position = centre + (PIVOT_REST - centre).rotated(Vector3.RIGHT, _body_turn)
	var pitch := _board_turn.x + float(_pose.get(&"grab_pitch", 0.0))
	var roll := _board_turn.z + float(_pose.get(&"grab_roll", 0.0))
	var yaw := _board_turn.y
	if _bail_left > 0.0:
		var shake := _bail_left / bail_duration
		yaw += 0.3 * shake * sin(_bail_left * 13.0)
		roll += 0.12 * shake * sin(_bail_left * 21.0)
	var turn := Vector3(pitch, yaw, roll)
	var turned := Basis.from_euler(turn)
	var lift := float(_pose.get(&"lift", 0.0)) + tuck_lift * _tuck + board_pop * _pop
	board.position = _board_rest.origin + Vector3.UP * lift + BOARD_CENTRE \
			- turned * BOARD_CENTRE
	board.rotation = turn


func _place_feet() -> void:
	var up := trick_pivot.global_basis.y.normalized()
	var facing := trick_pivot.global_basis.x.normalized()
	var board_up := board.global_basis.y.normalized()
	var board_facing := board.global_basis.x.normalized()
	var front := _foot_frame(foot_front, board_facing, board_up, 0.35)
	var back := _foot_frame(foot_back, board_facing, board_up, -0.1)
	if _off > 0.0:
		# Feet up off the board, in the rider's own frame, while it turns beneath them.
		var lift := float(_pose.get(&"lift", 0.0)) + board_pop * _pop + foot_gap
		var hover := up * lift * _world_scale()
		var free_front := _rest_frame(foot_front, 0.35).translated(
			hover + facing * _flick * _world_scale())
		var free_back := _rest_frame(foot_back, -0.1).translated(hover)
		front = front.interpolate_with(free_front, _off)
		back = back.interpolate_with(free_back, _off)
	if _kick_left > 0.0 and not _airborne:
		back = back.interpolate_with(_kick_frame(back), _bump(_kick_phase(), 0.0, 1.0))
	pose.foot_targets = [front, back]
	pose.foot_weights = PackedFloat32Array([1.0, 1.0])
	# Knees point the way the rider faces, never the way the board spins.
	pose.knee_pole = (facing + up * 0.3).normalized()


## Ankle frame above [param marker]: toes along [param facing], turned [param yaw] toward
## the nose, sole on the deck.
func _foot_frame(marker: Marker3D, facing: Vector3, up: Vector3, yaw: float) -> Transform3D:
	var toes := facing.rotated(up, yaw)
	var basis := Basis(up.cross(toes).normalized(), up, toes)
	return Transform3D(basis, marker.global_position + up * _ankle_height())


## The foot frame as if the board were at rest under the rider (no turn, no lift).
func _rest_frame(marker: Marker3D, yaw: float) -> Transform3D:
	var rest := trick_pivot.global_transform * _board_rest * marker.transform
	var up := trick_pivot.global_basis.y.normalized()
	var toes := trick_pivot.global_basis.x.normalized().rotated(up, yaw)
	var basis := Basis(up.cross(toes).normalized(), up, toes)
	return Transform3D(basis, rest.origin + up * _ankle_height())


## Where the back foot is during a push kick: down on the ground on the toe side, sweeping
## from beside the front truck to behind the tail.
func _kick_frame(on_board: Transform3D) -> Transform3D:
	var up := trick_pivot.global_basis.y.normalized()
	var facing := trick_pivot.global_basis.x.normalized()
	var nose := -trick_pivot.global_basis.z.normalized()
	var ground := global_position + up * _ankle_height()
	var size := _world_scale()
	var sweep := lerpf(0.15, -0.45, smoothstep(0.15, 0.85, _kick_phase())) * size
	var lift := 0.06 * _bump(_kick_phase(), 0.75, 1.0) * size
	var spot := ground + facing * 0.12 * size + nose * sweep + up * lift
	return Transform3D(on_board.basis.rotated(up, 1.2), spot)


## Hand targets per state (TrickPivot space), followed by a critically damped spring so
## hands ease into grabs, tucks and balance instead of jumping.
func _place_hands(delta: float) -> void:
	var targets := PackedVector3Array([_hand_at[LEFT], _hand_at[RIGHT]])
	var weights := PackedFloat32Array([0.0, 0.0])
	var chest := Vector3(0.0, 0.45 - float(_pose.get(&"drop", 0.0)), 0.0)
	var nose := Vector3.FORWARD
	match anim_state:
		&"grind":
			# Arms out along the board for balance, see-sawing with the balance bar.
			targets[LEFT] = chest + nose * 0.62 + Vector3.UP * (0.12 + 0.25 * _balance)
			targets[RIGHT] = chest - nose * 0.62 + Vector3.UP * (0.12 - 0.25 * _balance)
			weights = PackedFloat32Array([0.9, 0.9])
		&"grab":
			var hand := int((GRAB_POSES[_grab] as Dictionary)["hand"])
			targets[hand] = _to_pivot(_edge(_grab).global_position)
			weights[hand] = 1.0
			var free := 1 - hand
			targets[free] = chest + (nose if free == LEFT else -nose) * 0.42 \
					- Vector3.UP * 0.12 + Vector3.RIGHT * 0.12
			weights[free] = 0.7
	if anim_state in [&"trick", &"air"]:
		# Relaxed arms in the air (a little out and down, not the clip's flung-wide arms),
		# a touch wider in board tricks for balance, and to the shins in a flip's tuck.
		var board_at := _to_pivot(board.global_position)
		for side in 2:
			var along := 0.14 if side == LEFT else -0.14
			var shin := board_at + Vector3.UP * 0.42 + Vector3.RIGHT * 0.14 + nose * along
			var spread := 0.32 + 0.06 * _off
			var out := chest + nose * (spread if side == LEFT else -spread) \
					- Vector3.UP * 0.3 + Vector3.RIGHT * 0.16
			targets[side] = out.lerp(shin, clampf(_tuck * 1.2, 0.0, 1.0))
			weights[side] = maxf(0.85, 0.9 * _tuck)
	elif anim_state == &"bail":
		var flail := _bail_left * 16.0
		targets[LEFT] = chest + nose * 0.5 + Vector3.UP * 0.35 * sin(flail) + Vector3.RIGHT * 0.2
		targets[RIGHT] = chest - nose * 0.5 + Vector3.UP * 0.35 * cos(flail) \
				+ Vector3.RIGHT * 0.2
		weights = PackedFloat32Array([0.8, 0.8])
	var global_targets := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	for side in 2:
		if weights[side] > 0.0 or delta <= 0.0:
			_spring_hand(side, targets[side], weights[side], delta)
		else:
			_spring_hand(side, _hand_at[side], 0.0, delta)
		global_targets[side] = trick_pivot.global_transform * _hand_at[side]
	pose.hand_targets = global_targets
	pose.hand_weights = PackedFloat32Array([clampf(_hand_weight[LEFT], 0.0, 1.0),
		clampf(_hand_weight[RIGHT], 0.0, 1.0)])
	var facing := trick_pivot.global_basis.x.normalized()
	var up := trick_pivot.global_basis.y.normalized()
	pose.elbow_poles = PackedVector3Array([-facing - up * 0.5, -facing - up * 0.5])


## Moves hand [param side] toward [param target] (TrickPivot space) and its weight toward
## [param weight] on a critically damped spring; with no time step it jumps there.
func _spring_hand(side: int, target: Vector3, weight: float, delta: float) -> void:
	if delta <= 0.0:
		_hand_at[side] = target
		_hand_weight[side] = weight
		return
	var k := hand_spring
	var steps := maxi(ceili(delta / 0.008), 1)
	var dt := delta / steps
	for i in steps:
		var pull := (target - _hand_at[side]) * k * k - _hand_speed[side] * 2.0 * k
		_hand_speed[side] += pull * dt
		_hand_at[side] += _hand_speed[side] * dt
		var weight_pull := (weight - _hand_weight[side]) * k * k \
				- _hand_weight_speed[side] * 2.0 * k
		_hand_weight_speed[side] += weight_pull * dt
		_hand_weight[side] += _hand_weight_speed[side] * dt


## A hand's resting spot (TrickPivot space), where the spring starts.
func _rest_hand(side: int) -> Vector3:
	return Vector3(0.1, -0.1, -0.3 if side == LEFT else 0.3)


func _to_pivot(point: Vector3) -> Vector3:
	return trick_pivot.global_transform.affine_inverse() * point


func _edge(grab_id: StringName) -> Node3D:
	return board.get_node(NodePath(String((GRAB_POSES[grab_id] as Dictionary)["edge"])))


func _kick_phase() -> float:
	return 1.0 - _kick_left / kick_duration if _kick_left > 0.0 else 0.0


## Ankle height above the sole in world metres (the rig may be scaled up).
func _ankle_height() -> float:
	return 0.1 * _world_scale()


## How much bigger than its model the rig is drawn (the Skater scales its Rig up): world
## metres per metre of the rig's own space.
func _world_scale() -> float:
	return global_basis.get_scale().y


## 0 outside [param from]..[param to], rising smoothly to 1 in the middle and back.
static func _bump(p: float, from: float, to: float) -> float:
	if p <= from or p >= to:
		return 0.0
	return sin(PI * (p - from) / (to - from))
