extends Node3D
## Dev preview: the skater rig cycling through every animation state and trick, with an
## orbiting camera and the state's name on screen.
##
## User args (after [code]--[/code]) freeze one moment for screenshots:
## [code]--state=<step> --t=<0..1> --cam=<angle degrees> --dist=<m>[/code], where step is a
## name from [constant SEQUENCE].

## Steps: name and seconds. Trick and grab steps are airborne.
const SEQUENCE: Array[Array] = [
	[&"idle", 2.0], [&"push", 2.0], [&"crouch", 1.5], [&"kickflip", 0.6], [&"land", 0.6],
	[&"heelflip", 0.6], [&"melon_grab", 1.5], [&"indy_grab", 1.5], [&"front_flip", 0.6],
	[&"back_flip", 0.6], [&"air", 1.0], [&"pop_shove_it", 0.6], [&"tre_flip", 0.7],
	[&"front_kickflip", 0.7], [&"nosegrab", 1.5], [&"tailgrab", 1.5], [&"method_grab", 1.5],
	[&"stalefish_grab", 1.5], [&"grind", 2.5], [&"bail", 1.0], [&"turn", 2.0],
]
const RIG_SCENE := preload("res://scenes/player/skater_rig.tscn")
const ORBIT_RATE := 0.25
const CAMERA_HEIGHT := 1.3

var _step: int = 0
var _elapsed: float = 0.0
var _frozen: bool = false
var _freeze_t: float = 0.0
var _camera_angle: float = 0.6
var _camera_distance: float = 3.2
var _rig: SkaterRig
var _debug: bool = false
var _frames: int = 0

@onready var camera: Camera3D = $Camera3D
@onready var label: Label = $Overlay/StateLabel


func _ready() -> void:
	_rig = RIG_SCENE.instantiate() as SkaterRig
	add_child(_rig)
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"--state":
				_frozen = true
				_step = _index_of(StringName(value))
			"--t":
				_freeze_t = value.to_float()
			"--cam":
				_camera_angle = deg_to_rad(value.to_float())
			"--dist":
				_camera_distance = value.to_float()
			"--debug":
				_debug = true


func _process(delta: float) -> void:
	var length := float(SEQUENCE[_step][1])
	if _frozen:
		_elapsed = _freeze_t * length
	else:
		_elapsed += delta
		_camera_angle += ORBIT_RATE * delta
		if _elapsed >= length:
			_elapsed = 0.0
			_step = (_step + 1) % SEQUENCE.size()
			_enter(SEQUENCE[_step][0] as StringName)
	_drive(SEQUENCE[_step][0] as StringName, _elapsed / length)
	var orbit := Vector3(sin(_camera_angle), 0.0, cos(_camera_angle)) * _camera_distance
	camera.position = orbit + Vector3.UP * CAMERA_HEIGHT
	camera.look_at(Vector3.UP * 0.75)
	label.text = "%s  (anim_state: %s)" % [SEQUENCE[_step][0], _rig.anim_state]
	_frames += 1
	if _debug and _frames % 4 == 0:
		_print_debug()


func _print_debug() -> void:
	var bones: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l", &"upperarm_r",
			&"lowerarm_r", &"hand_r", &"foot_l", &"foot_r"]
	var line := "state %s reach %.3f" % [_rig.anim_state, _rig.grab_reach()]
	for bone in bones:
		line += " %s%s" % [bone, _rig.pose.bone_global_position(bone)]
	line += " targets %s w %s" % [_rig.pose.hand_targets, _rig.pose.hand_weights]
	print(line)


func _index_of(step: StringName) -> int:
	for i in SEQUENCE.size():
		if SEQUENCE[i][0] == step:
			return i
	return 0


## One-shot cues when a step starts.
func _enter(step: StringName) -> void:
	match step:
		&"land":
			_rig.play_landing(true)
		&"bail":
			_rig.play_landing(false)


func _drive(step: StringName, progress: float) -> void:
	var is_trick := SkaterRig.TRICK_MOTIONS.has(step)
	var is_grab := SkaterRig.GRAB_POSES.has(step)
	var airborne := is_trick or is_grab or step == &"air"
	_rig.set_airborne(airborne)
	_rig.set_cruising(step == &"push")
	_rig.set_crouch(progress if step == &"crouch" else 0.0)
	_rig.set_grind(step == &"grind", sin(progress * TAU) * 0.8)
	_rig.set_grab(step if is_grab else &"")
	_rig.set_trick(step if is_trick else &"", progress)
	_rig.set_lean(sin(progress * TAU) if step == &"turn" else 0.0)
	if _frozen and step in [&"land", &"bail"]:
		_rig.play_landing(step == &"land")
