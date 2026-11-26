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
## Tricks: flips turn the whole [code]TrickPivot[/code] (rider and board) with a tuck;
## kickflip and heelflip roll only the [code]Board[/code] under the tucked rider, who
## catches it at the end. Turns lean the pivot.
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
## Per trick: whether only the board turns (else rider and board together), the rotation
## it turns and by how many radians over the trick.
const TRICK_MOTIONS := {
	&"front_flip": {"board_only": false, "property": ^"rotation:x", "angle": -FULL_TURN},
	&"back_flip": {"board_only": false, "property": ^"rotation:x", "angle": FULL_TURN},
	&"kickflip": {"board_only": true, "property": ^"rotation:z", "angle": FULL_TURN},
	&"heelflip": {"board_only": true, "property": ^"rotation:z", "angle": -FULL_TURN},
}
## Which hand reaches for which edge marker in each grab: melon is the front (left)
## hand on the heel edge, indy the back (right) hand on the toe edge.
const GRAB_HANDS := {
	&"melon_grab": {"hand": 0, "edge": ^"TrickPivot/Board/GrabHeel"},
	&"indy_grab": {"hand": 1, "edge": ^"TrickPivot/Board/GrabToe"},
}
const LEFT := 0
const RIGHT := 1
## Seconds the state machine takes to blend between clips.
const CLIP_BLEND := 0.15

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
@export var tuck_lift: float = 0.32
## Seconds the landing dip lasts.
@export var land_duration: float = 0.3
## Seconds a bail stumble lasts.
@export var bail_duration: float = 0.9

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
	_own_materials()
	_build_tree()
	_pose = _pose_targets()
	_apply(0.0)


func _process(delta: float) -> void:
	_kick_left = maxf(_kick_left - delta, 0.0)
	if _cruising and _kick_left <= 0.0 and not _airborne:
		_kick_left = kick_duration
	_land_left = maxf(_land_left - delta, 0.0)
	_bail_left = maxf(_bail_left - delta, 0.0)
	_lean = lerpf(_lean, _lean_target, 1.0 - exp(-lean_rate * delta))
	_set_state(_pick_state())
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
	_grab = grab_id if GRAB_HANDS.has(grab_id) else &""


## Touched down: a short dip when [param clean], else a stumble (bail).
func play_landing(clean: bool) -> void:
	if clean:
		_land_left = land_duration
	else:
		_bail_left = bail_duration
		_land_left = 0.0


## Poses the trick [param trick_id] at [param progress] 0..1. An empty id resets the pose.
func set_trick(trick_id: StringName, progress: float) -> void:
	_trick = trick_id if TRICK_MOTIONS.has(trick_id) else &""
	_trick_progress = clampf(progress, 0.0, 1.0)
	_place_trick()


## How much of its full turn the trick [param trick_id] shows at [param progress] 0..1
## (0 = upright, 1 = all the way round). The [Skater] judges landings with the same curve,
## so what the player sees is what gets judged. 0 for an unknown id.
static func trick_turn(trick_id: StringName, progress: float) -> float:
	if not TRICK_MOTIONS.has(trick_id):
		return 0.0
	var p := clampf(progress, 0.0, 1.0)
	if bool((TRICK_MOTIONS[trick_id] as Dictionary)["board_only"]):
		return smoothstep(0.1, 0.8, p)
	return smoothstep(0.0, 1.0, p)


## The clip state the [AnimationTree] is in (follows [member anim_state]).
func clip_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## Distance from the grabbing hand to the board edge it grabs, or INF when not grabbing.
func grab_reach() -> float:
	if _grab.is_empty():
		return INF
	var entry: Dictionary = GRAB_HANDS[_grab]
	var hand := &"hand_l" if int(entry["hand"]) == LEFT else &"hand_r"
	var edge := get_node(entry["edge"] as NodePath) as Node3D
	return pose.bone_global_position(hand).distance_to(edge.global_position)


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


## Pose values each state aims for (hips, spine, head, board lift).
func _pose_targets() -> Dictionary[StringName, float]:
	var targets: Dictionary[StringName, float] = {
		&"drop": stance_drop, &"bend": 0.15, &"twist": 0.3, &"head": 0.9, &"lift": 0.0,
		&"roll": 0.0,
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
			targets[&"lift"] = 0.08
			targets[&"bend"] = 0.2
		&"grab":
			targets[&"lift"] = tuck_lift + 0.08
			targets[&"drop"] = 0.32
			targets[&"bend"] = 1.0
		&"trick":
			targets[&"bend"] = 0.3
		&"land":
			targets[&"drop"] = stance_drop + 0.16
			targets[&"bend"] = 0.35
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
	pose.pelvis_drop = _pose[&"drop"]
	pose.spine_bend = _pose[&"bend"]
	pose.spine_twist = _pose[&"twist"]
	pose.spine_roll = _pose[&"roll"]
	pose.head_yaw = _pose[&"head"]
	_place_trick()
	_place_feet()
	_place_hands()


## Board and pivot for the current trick (plus the tuck lift outside of tricks).
func _place_trick() -> void:
	if not is_node_ready():
		return
	trick_pivot.rotation.x = 0.0
	board.transform = _board_rest
	board.position.y += float(_pose.get(&"lift", 0.0))
	if _bail_left > 0.0:
		var shake := _bail_left / bail_duration
		board.rotation.y = 0.3 * shake * sin(_bail_left * 13.0)
		board.rotation.z = 0.12 * shake * sin(_bail_left * 21.0)
	if _trick.is_empty():
		return
	var motion: Dictionary = TRICK_MOTIONS[_trick]
	var p := _trick_progress
	var turned := float(motion["angle"]) * trick_turn(_trick, p)
	if bool(motion["board_only"]):
		# Pop, flip under the rider, catch: roll around the long axis while lifted.
		board.position.y += tuck_lift * 0.8 * sin(PI * p)
		board.rotation.x = 0.35 * _bump(p, 0.0, 0.3)
		board.rotation.z = turned
	else:
		board.position.y += tuck_lift * _bump(p, 0.0, 1.0)
		trick_pivot.rotation.x = turned


func _place_feet() -> void:
	var board_up := board.global_basis.y.normalized()
	var facing := board.global_basis.x.normalized()
	var front := _foot_frame(foot_front, facing, board_up, 0.35)
	var back := _foot_frame(foot_back, facing, board_up, -0.1)
	var off_board := 0.0
	if _trick_is_board_only():
		off_board = _bump(_trick_progress, 0.08, 0.88)
	if off_board > 0.0:
		# Feet stay with the rider (tucked) while the board flips beneath them.
		# Knees up and together: lifted, and drawn in toward the middle of the board.
		var tuck_up := trick_pivot.global_basis.y.normalized() * tuck_lift * 0.8
		var nose := -trick_pivot.global_basis.z.normalized() * 0.07
		var rest_front := _rest_frame(foot_front).translated(tuck_up - nose)
		var rest_back := _rest_frame(foot_back).translated(tuck_up + nose)
		front = front.interpolate_with(rest_front, off_board)
		back = back.interpolate_with(rest_back, off_board)
	if _kick_left > 0.0 and not _airborne:
		back = back.interpolate_with(_kick_frame(back), _bump(_kick_phase(), 0.0, 1.0))
	pose.foot_targets = [front, back]
	pose.foot_weights = PackedFloat32Array([1.0, 1.0])
	pose.knee_pole = (facing + board_up * 0.3).normalized()


## Ankle frame above [param marker]: toes along [param facing], turned [param yaw] toward
## the nose, sole on the deck.
func _foot_frame(marker: Marker3D, facing: Vector3, up: Vector3, yaw: float) -> Transform3D:
	var toes := facing.rotated(up, yaw)
	var basis := Basis(up.cross(toes).normalized(), up, toes)
	return Transform3D(basis, marker.global_position + up * _ankle_height())


## The foot frame as if the board were at rest (no trick, no lift).
func _rest_frame(marker: Marker3D) -> Transform3D:
	var rest := board.get_parent_node_3d().global_transform * _board_rest * marker.transform
	var up := trick_pivot.global_basis.y.normalized()
	var facing := trick_pivot.global_basis.x.normalized()
	var basis := Basis(up.cross(facing).normalized(), up, facing)
	return Transform3D(basis, rest.origin + up * _ankle_height())


## Where the back foot is during a push kick: down on the ground on the toe side, sweeping
## from beside the front truck to behind the tail.
func _kick_frame(on_board: Transform3D) -> Transform3D:
	var up := trick_pivot.global_basis.y.normalized()
	var facing := trick_pivot.global_basis.x.normalized()
	var nose := -trick_pivot.global_basis.z.normalized()
	var ground := global_position + up * _ankle_height()
	var sweep := lerpf(0.15, -0.45, smoothstep(0.15, 0.85, _kick_phase()))
	var lift := 0.06 * _bump(_kick_phase(), 0.75, 1.0)
	var spot := ground + facing * 0.12 + nose * sweep + up * lift
	return Transform3D(on_board.basis.rotated(up, 1.2), spot)


func _place_hands() -> void:
	var weights := PackedFloat32Array([0.0, 0.0])
	var targets := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var up := trick_pivot.global_basis.y.normalized()
	var nose := -trick_pivot.global_basis.z.normalized()
	var facing := trick_pivot.global_basis.x.normalized()
	var chest := body.global_position + up * 1.2
	match anim_state:
		&"grind":
			# Arms out along the board for balance, see-sawing with the balance bar.
			targets[LEFT] = chest + nose * 0.62 + up * (0.12 + 0.25 * _balance)
			targets[RIGHT] = chest - nose * 0.62 + up * (0.12 - 0.25 * _balance)
			weights = PackedFloat32Array([0.9, 0.9])
		&"grab":
			var entry: Dictionary = GRAB_HANDS[_grab]
			var hand := int(entry["hand"])
			targets[hand] = (get_node(entry["edge"] as NodePath) as Node3D).global_position
			weights[hand] = 1.0
			var free := 1 - hand
			targets[free] = chest + (nose if free == LEFT else -nose) * 0.5 - up * 0.1 \
					+ facing * 0.15
			weights[free] = 0.7
		&"trick":
			if not _trick_is_board_only():
				# Tuck: hands to the shins.
				for side in 2:
					var shin := board.global_position + up * 0.45 + facing * 0.12
					targets[side] = shin + nose * (0.12 if side == LEFT else -0.12)
				weights = PackedFloat32Array([0.9, 0.9])
			else:
				targets[LEFT] = chest + nose * 0.4 - up * 0.25 + facing * 0.1
				targets[RIGHT] = chest - nose * 0.4 - up * 0.25 + facing * 0.1
				weights = PackedFloat32Array([0.6, 0.6])
		&"bail":
			var flail := _bail_left * 16.0
			targets[LEFT] = chest + nose * 0.5 + up * 0.35 * sin(flail) + facing * 0.2
			targets[RIGHT] = chest - nose * 0.5 + up * 0.35 * cos(flail) + facing * 0.2
			weights = PackedFloat32Array([0.8, 0.8])
	pose.hand_targets = targets
	pose.hand_weights = weights
	pose.elbow_poles = PackedVector3Array([-facing - up * 0.5, -facing - up * 0.5])


func _trick_is_board_only() -> bool:
	return not _trick.is_empty() and bool((TRICK_MOTIONS[_trick] as Dictionary)["board_only"])


func _kick_phase() -> float:
	return 1.0 - _kick_left / kick_duration if _kick_left > 0.0 else 0.0


func _ankle_height() -> float:
	return 0.1


## 0 outside [param from]..[param to], rising smoothly to 1 in the middle and back.
static func _bump(p: float, from: float, to: float) -> float:
	if p <= from or p >= to:
		return 0.0
	return sin(PI * (p - from) / (to - from))
