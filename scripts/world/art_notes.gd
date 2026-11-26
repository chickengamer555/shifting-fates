class_name ArtNotes
extends Node
## Brings the level art's notes to life. The user names objects in the Chickbry levels with
## what they should do, and this node finds them by those words under [member art_path]:
## [br]- a name holding [constant SPIN_NOTE] (e.g. "Torus (needs to spin)") turns steadily
##   round the vertical line through its centre, [member spin_speed] radians a second,
##   keeping its tilt. (A ring turning about its own axis would look still: it is
##   symmetric.)
## [br]- a name holding [constant BOUNCE_NOTE] (e.g. "Disc (bounce pad needs to launch
##   player into air)") gets a trigger on its top surface that throws any player body
##   landing or rolling onto it up at [member launch_speed] m/s.
## [br]The art itself is never edited: the behaviour is added when the level loads.

## The player was thrown up by the bounce pad [param pad].
signal launched(pad: Node3D)

## Words in an art object's name that make it spin (any case).
const SPIN_NOTE := "needs to spin"
## Words in an art object's name that make it a bounce pad (any case).
const BOUNCE_NOTE := "bounce pad"
## Player bodies are on physics layer 2.
const PLAYER_LAYER_MASK := 2
## How far the pad's trigger reaches above its top (metres).
const PAD_TRIGGER_HEIGHT := 1.2

## Root of the level art searched for notes.
@export var art_path: NodePath = ^"../Art"
## Turn rate of spinning objects (radians per second); alternate objects turn the other way.
@export var spin_speed: float = 0.2
## Upward speed a bounce pad gives the player (m/s).
@export var launch_speed: float = 24.0

## Art objects that spin.
var spinners: Array[Node3D] = []
## Art objects that are bounce pads.
var bounce_pads: Array[Node3D] = []


func _ready() -> void:
	set_meta("verify_unit", "ArtNotes")
	var art := get_node_or_null(art_path)
	if art == null:
		push_warning("ArtNotes: no art at %s" % art_path)
		return
	for node: Node in art.find_children("*", "Node3D", true, false):
		var lower := String(node.name).to_lower()
		if lower.contains(SPIN_NOTE):
			spinners.append(node as Node3D)
		elif lower.contains(BOUNCE_NOTE):
			bounce_pads.append(node as Node3D)
			_add_pad_trigger(node as Node3D)


func _physics_process(delta: float) -> void:
	for index: int in spinners.size():
		var direction := 1.0 if index % 2 == 0 else -1.0
		spinners[index].global_rotate(Vector3.UP, spin_speed * direction * delta)


## Throws [param body] up off a bounce pad, keeping its sideways speed.
func launch(body: CharacterBody3D, pad: Node3D) -> void:
	body.velocity.y = maxf(body.velocity.y, launch_speed)
	launched.emit(pad)


func _add_pad_trigger(pad: Node3D) -> void:
	var top := _top_of(pad)
	var area := Area3D.new()
	area.name = "BounceTrigger"
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER_MASK
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var size := _footprint(pad)
	box.size = Vector3(size.x, PAD_TRIGGER_HEIGHT, size.y)
	shape.shape = box
	area.add_child(shape)
	pad.add_child(area)
	area.global_position = top + Vector3.UP * (PAD_TRIGGER_HEIGHT * 0.5)
	area.body_entered.connect(_on_pad_body_entered.bind(pad))


## World position of the middle of [param pad]'s top surface.
static func _top_of(pad: Node3D) -> Vector3:
	var box := _world_box(pad)
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


## Width and depth (x, z) of [param pad] in metres, at least 1 m each.
static func _footprint(pad: Node3D) -> Vector2:
	var box := _world_box(pad)
	return Vector2(maxf(box.size.x, 1.0), maxf(box.size.z, 1.0))


static func _world_box(pad: Node3D) -> AABB:
	var box := AABB(pad.global_position, Vector3.ZERO)
	for node: Node in pad.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		box = box.merge(visual.global_transform * visual.get_aabb())
	return box


func _on_pad_body_entered(body: Node3D, pad: Node3D) -> void:
	var player := body as CharacterBody3D
	if player != null:
		launch(player, pad)
