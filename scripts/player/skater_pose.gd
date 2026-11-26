extends SkeletonModifier3D
## SkaterPose: the procedural layer on top of the skater's animation clips.
##
## Runs after the [AnimationTree] each frame and bends the clip's pose into a skate pose:
## hips dropped, spine bent, twisted and rolled, head turned to look down the board, and
## two-bone IK for the legs (feet planted on the board, or on any target the [SkaterRig]
## gives) and the arms (grabs, balancing, tucks). The [SkaterRig] sets the fields below
## every frame; targets are in global space so they follow the board through any trick.
##
## Model space of the mannequin: +Z is where the rider faces, +X is the rider's left, +Y up.

## Bone names of the Quaternius mannequin.
const PELVIS := &"pelvis"
const SPINE: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
const NECK := &"neck_01"
const HEAD := &"Head"
const LEG_L: Array[StringName] = [&"thigh_l", &"calf_l", &"foot_l"]
const LEG_R: Array[StringName] = [&"thigh_r", &"calf_r", &"foot_r"]
const ARM_L: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]
const ARM_R: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## Below this the chain counts as straight and the pole sets its bend plane.
const STRAIGHT_EPSILON := 0.001
## Below this squared sine two directions count as the same (no turn needed).
const ALIGNED_EPSILON := 1e-12

## How far the hips drop (model metres).
var pelvis_drop: float = 0.0
## Forward bend of the spine (radians, split over the spine bones).
var spine_bend: float = 0.0
## Spine twist toward the board's nose (radians, + turns toward the rider's left).
var spine_twist: float = 0.0
## Sideways lean of the spine (radians, + leans to the rider's left).
var spine_roll: float = 0.0
## Head turn toward the nose on top of the spine twist (radians).
var head_yaw: float = 0.0
## Ankle targets (global): index 0 left foot, 1 right foot. Basis: +Y sole up, +Z toes.
var foot_targets: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
## How much each foot follows its target (0 keeps the clip's foot).
var foot_weights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Hand targets (global): index 0 left hand, 1 right hand.
var hand_targets: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
## How much each hand follows its target.
var hand_weights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Where knees and elbows point, global directions.
var knee_pole: Vector3 = Vector3.FORWARD
var elbow_poles: PackedVector3Array = PackedVector3Array([Vector3.BACK, Vector3.BACK])

var _bones: Dictionary[StringName, int] = {}
## Skeleton-space positions of the limb ends as this modifier left them. The skeleton
## restores the clip pose after its modifiers run, so reading bones later shows the clip.
var _solved: Dictionary[StringName, Vector3] = {}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bones.is_empty():
		_cache_bones(skeleton)
	var to_skeleton := skeleton.global_transform.affine_inverse()
	_drop_pelvis(skeleton)
	_bend_spine(skeleton)
	_turn_head(skeleton)
	var pole := (to_skeleton.basis * knee_pole).normalized()
	for side in 2:
		var leg := LEG_L if side == 0 else LEG_R
		if foot_weights[side] > 0.0:
			var target := to_skeleton * foot_targets[side]
			_solve_limb(skeleton, leg, target.origin, pole, foot_weights[side])
			_orient_end(skeleton, leg[2], target.basis.orthonormalized(), foot_weights[side])
		var arm := ARM_L if side == 0 else ARM_R
		if hand_weights[side] > 0.0:
			var elbow := (to_skeleton.basis * elbow_poles[side]).normalized()
			_solve_limb(skeleton, arm, to_skeleton * hand_targets[side], elbow,
					hand_weights[side])
	for end: StringName in [LEG_L[2], LEG_R[2], ARM_L[2], ARM_R[2]]:
		_solved[end] = skeleton.get_bone_global_pose(_bones[end]).origin


## Global position of [param bone] as posed by this modifier, for tests and tools. Limb
## ends (hands, feet) report the solved pose; other bones the skeleton's current pose.
func bone_global_position(bone: StringName) -> Vector3:
	var skeleton := get_skeleton()
	if _solved.has(bone):
		return skeleton.global_transform * _solved[bone]
	var index := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _cache_bones(skeleton: Skeleton3D) -> void:
	var names: Array[StringName] = [PELVIS, NECK, HEAD]
	names.append_array(SPINE + LEG_L + LEG_R + ARM_L + ARM_R)
	for bone_name in names:
		_bones[bone_name] = skeleton.find_bone(bone_name)


func _drop_pelvis(skeleton: Skeleton3D) -> void:
	var bone := _bones[PELVIS]
	var pose := skeleton.get_bone_global_pose(bone)
	pose.origin.y -= pelvis_drop
	skeleton.set_bone_global_pose(bone, pose)


func _bend_spine(skeleton: Skeleton3D) -> void:
	var share := 1.0 / SPINE.size()
	var turn := Basis(Vector3.UP, spine_twist * share) \
			* Basis(Vector3.BACK, -spine_roll * share) \
			* Basis(Vector3.RIGHT, spine_bend * share)
	for bone_name in SPINE:
		_rotate_global(skeleton, _bones[bone_name], turn)


func _turn_head(skeleton: Skeleton3D) -> void:
	var half := Basis(Vector3.UP, head_yaw * 0.5)
	_rotate_global(skeleton, _bones[NECK], half)
	_rotate_global(skeleton, _bones[HEAD], half)


## Turns [param bone] by [param turn] (skeleton space) about its own origin.
static func _rotate_global(skeleton: Skeleton3D, bone: int, turn: Basis) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = turn * pose.basis
	skeleton.set_bone_global_pose(bone, pose)


## Two-bone IK: bends [param chain] (root, middle, end) so the end reaches toward
## [param target] by [param weight], the middle joint bending toward [param pole].
## The root turns the whole old bend plane onto the new one, so knees and elbows stay
## hinges instead of twisting.
func _solve_limb(skeleton: Skeleton3D, chain: Array[StringName], target: Vector3,
		pole: Vector3, weight: float) -> void:
	var root := _bones[chain[0]]
	var middle := _bones[chain[1]]
	var end := _bones[chain[2]]
	var root_pose := skeleton.get_bone_global_pose(root)
	var middle_pose := skeleton.get_bone_global_pose(middle)
	var end_pose := skeleton.get_bone_global_pose(end)
	var a := root_pose.origin
	var b := middle_pose.origin
	var c := end_pose.origin
	var upper := a.distance_to(b)
	var lower := b.distance_to(c)
	var goal := c.lerp(target, clampf(weight, 0.0, 1.0))
	var reach := clampf(a.distance_to(goal), absf(upper - lower) + 0.001,
			(upper + lower) * 0.999)
	var along := (goal - a).normalized()
	var bend := _perpendicular(pole, along)
	var cos_root := (upper * upper + reach * reach - lower * lower) / (2.0 * upper * reach)
	var sin_root := sqrt(maxf(1.0 - cos_root * cos_root, 0.0))
	var new_b := a + (along * cos_root + bend * sin_root) * upper
	var new_c := a + along * reach
	var old_frame := _frame(b - a, c - a, pole)
	var new_frame := _frame(new_b - a, new_c - a, pole)
	var root_turn := new_frame * old_frame.inverse()
	var new_root := Transform3D(root_turn * root_pose.basis, a)
	var new_middle := new_root * (root_pose.affine_inverse() * middle_pose)
	var new_end := new_middle * (middle_pose.affine_inverse() * end_pose)
	var from := (new_end.origin - new_b).normalized()
	var to := (new_c - new_b).normalized()
	# Any turn left at all is applied: skipping small ones left the end up to a few cm off
	# its target on some frames, which read as feet jiggling.
	if from.cross(to).length_squared() > ALIGNED_EPSILON:
		new_middle.basis = Basis(Quaternion(from, to)) * new_middle.basis
	skeleton.set_bone_global_pose(root, new_root)
	skeleton.set_bone_global_pose(middle, new_middle)


## Blends the end bone's orientation toward [param basis] (skeleton space, the target's
## sole frame): the rest pose stands flat, so the rest orientation maps onto it.
func _orient_end(skeleton: Skeleton3D, bone_name: StringName, basis: Basis,
		weight: float) -> void:
	var bone := _bones[bone_name]
	var pose := skeleton.get_bone_global_pose(bone)
	var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var wanted := Quaternion(basis * rest)
	var current := Quaternion(pose.basis.orthonormalized())
	pose.basis = Basis(current.slerp(wanted, clampf(weight, 0.0, 1.0)))
	skeleton.set_bone_global_pose(bone, pose)


## Orthonormal frame: X along [param first], Y toward [param second] (or the pole when the
## two are parallel).
static func _frame(first: Vector3, second: Vector3, pole: Vector3) -> Basis:
	var x := first.normalized()
	var y := _perpendicular(second, x)
	if y.is_zero_approx():
		y = _perpendicular(pole, x)
	return Basis(x, y, x.cross(y))


## The part of [param vector] perpendicular to unit [param axis], normalized.
static func _perpendicular(vector: Vector3, axis: Vector3) -> Vector3:
	var off := vector - axis * vector.dot(axis)
	if off.length_squared() < STRAIGHT_EPSILON * STRAIGHT_EPSILON:
		return Vector3.ZERO
	return off.normalized()
