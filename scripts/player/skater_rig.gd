class_name SkaterRig
extends Node3D
## The skater's look: a white mannequin standing sideways on a white board.
##
## Pure presentation, driven by the [Skater] through a few setters. Animation is
## procedural: lean into turns, crouch while charging a jump, a kick of the back leg on
## each push, and a rotation of the whole rider (flips) or just the board (kick/heelflip)
## for tricks. Body parts are separate [MeshInstance3D] nodes so they can be painted later.
##
## Layout: the rider faces +X (regular stance, left foot forward) on a board that points
## along -Z. Hips and shoulders are pivot nodes so limbs swing from the joint.

const FULL_TURN := TAU
## Per trick: whether only the board turns (else the whole rider), which rotation
## component turns (x = flip over the nose, z = roll around the board's long axis)
## and by how many radians over the trick.
const TRICK_MOTIONS := {
	&"front_flip": {"board_only": false, "property": ^"rotation:x", "angle": -FULL_TURN},
	&"back_flip": {"board_only": false, "property": ^"rotation:x", "angle": FULL_TURN},
	&"kickflip": {"board_only": true, "property": ^"rotation:z", "angle": FULL_TURN},
	&"heelflip": {"board_only": true, "property": ^"rotation:z", "angle": -FULL_TURN},
}

@export_group("Lean")
## Roll at full lean (radians).
@export var max_lean: float = 0.35
## How quickly the lean follows the steering (1/s).
@export var lean_rate: float = 8.0

@export_group("Crouch")
## How far the hips drop at a full jump charge (m).
@export var crouch_depth: float = 0.3
## How quickly the crouch follows the charge (1/s).
@export var crouch_rate: float = 14.0

@export_group("Push kick")
## Seconds one push kick takes.
@export var kick_duration: float = 0.35
## How far the back leg swings back (radians).
@export var kick_angle: float = 0.8

@export_group("Phase")
## Transparency of every body and board part while shifted (0 solid, 1 invisible).
@export_range(0.0, 1.0) var phased_transparency: float = 0.6

var _lean_target: float = 0.0
var _lean: float = 0.0
var _crouch_target: float = 0.0
var _crouch: float = 0.0
## Time left in the current push kick, 0 when none.
var _kick_left: float = 0.0
var _hip_height: float = 0.0

@onready var trick_pivot: Node3D = $TrickPivot
@onready var board: Node3D = $TrickPivot/Board
@onready var upper_body: Node3D = $TrickPivot/Body/UpperBody
@onready var hip_left: Node3D = $TrickPivot/Body/UpperBody/HipL
@onready var hip_right: Node3D = $TrickPivot/Body/UpperBody/HipR


func _ready() -> void:
	_hip_height = hip_left.position.y


func _process(delta: float) -> void:
	_lean = lerpf(_lean, _lean_target, 1.0 - exp(-lean_rate * delta))
	_crouch = lerpf(_crouch, _crouch_target, 1.0 - exp(-crouch_rate * delta))
	trick_pivot.rotation.z = -_lean * max_lean
	_apply_crouch(_crouch * crouch_depth)
	_kick_left = maxf(_kick_left - delta, 0.0)
	var kick_phase := 1.0 - _kick_left / kick_duration if _kick_left > 0.0 else 0.0
	hip_right.rotation.x = sin(kick_phase * PI) * kick_angle


## Lean into a turn: -1 full left, 1 full right.
func set_lean(amount: float) -> void:
	_lean_target = clampf(amount, -1.0, 1.0)


## Crouch depth 0..1 (the jump charge).
func set_crouch(amount: float) -> void:
	_crouch_target = clampf(amount, 0.0, 1.0)


## Plays one kick of the back leg.
func play_push() -> void:
	_kick_left = kick_duration


## Poses the trick [param trick_id] at [param progress] 0..1. An empty id resets the pose.
func set_trick(trick_id: StringName, progress: float) -> void:
	trick_pivot.rotation.x = 0.0
	board.rotation.z = 0.0
	if not TRICK_MOTIONS.has(trick_id):
		return
	var motion: Dictionary = TRICK_MOTIONS[trick_id]
	var angle := float(motion["angle"]) * smoothstep(0.0, 1.0, progress)
	var target := board if bool(motion["board_only"]) else trick_pivot
	target.set_indexed(motion["property"] as NodePath, angle)


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


## Drops the upper body and shortens the legs from the hip so the feet stay on the deck.
func _apply_crouch(drop: float) -> void:
	upper_body.position.y = -drop
	var leg_scale := (_hip_height - drop) / _hip_height
	hip_left.scale.y = leg_scale
	hip_right.scale.y = leg_scale
