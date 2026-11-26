class_name GrappleAbility
extends SkaterAbility
## Two grapple hooks: left mouse fires the left hook, right mouse the right one.
##
## A fresh press casts a ray from the skater's hand along [member aim_forward] turned
## [member side_angle_deg] to that side and pitched [member aim_pitch_deg] up; if it hits
## world geometry within [member max_fire_range] the hook sticks there and stays while the
## button is held. Each hook's line is a [GrappleRope]: it stops the skater moving further
## away than the line (a swing), pays out while airborne and lets go once it is too long.
## With both hooks stuck (both buttons held) the skater is reeled in towards the midpoint
## of the two anchors. A thin bar is drawn from the hand to each anchor.
##
## The ability only edits [code]velocity[/code], so the Skater keeps applying gravity and
## [code]move_and_slide()[/code]. The Skater feeds [member aim_forward] (the camera's
## forward) through [method update_aim] every frame. Locked until the story unlocks it:
## [member enabled] starts false and [member SkaterAbility.unlock_id] is
## [code]grapple[/code]. Disabling it lets go of both hooks.

## Emitted when a hook sticks; [param side] is a [enum Side], [param point] the anchor.
signal hook_attached(side: int, point: Vector3)
## Emitted when a hook lets go (button released, line too long, or input switched off).
signal hook_released(side: int)
## Emitted when a hook is cast on [param side], whether or not it then sticks.
signal hook_fired(side: int)

enum Side { LEFT, RIGHT }

const SIDES: Array[int] = [Side.LEFT, Side.RIGHT]
const ACTIONS: Array[String] = ["grapple_left", "grapple_right"]
const LINE_NAMES: Array[String] = ["LeftLine", "RightLine"]
## Hooks stick to world and phaseable geometry.
const DEFAULT_HIT_MASK := PhysicsLayers.WORLD_MASK | PhysicsLayers.PHASEABLE_MASK
## Above this |dot| with UP a direction counts as vertical (see [MathLimits]).
const VERTICAL_LIMIT := MathLimits.NEAR_PARALLEL_DOT
## GameState id that unlocks the hooks.
const UNLOCK_ID := &"grapple"

## Longest shot (m) a hook can make.
@export var max_fire_range: float = 30.0
## How far (degrees) each hook aims to its side of [member aim_forward].
@export var side_angle_deg: float = 35.0
## How far (degrees) the hooks aim above [member aim_forward].
@export var aim_pitch_deg: float = 30.0
## Height (m) of the hand (ray start and line end) above the skater's origin.
@export var fire_height: float = 0.5
## What the hooks can stick to.
@export_flags_3d_physics var hit_mask: int = DEFAULT_HIT_MASK
## Pull (m/s²) towards the anchors' midpoint while reeling in.
@export var reel_acceleration: float = 30.0
## Fastest (m/s) the skater is pulled towards the midpoint.
@export var max_reel_speed: float = 18.0

@export_group("Rope")
## How fast (m/s) a line pays out while airborne.
@export var payout_speed: float = 2.5
## Longest usable line (m); past this the hook lets go.
@export var max_rope_length: float = 25.0
## Shortest line (m).
@export var min_rope_length: float = 1.5

@export_group("Line")
## Thickness (m) of the drawn line.
@export var line_thickness: float = 0.04
## Colour of the drawn line.
@export var line_color: Color = Color(0.85, 0.9, 1.0)

## Direction the player is aiming (usually the camera's forward), set by the Skater.
var aim_forward: Vector3 = Vector3.FORWARD
## True while the left hook is stuck.
var left_attached: bool:
	get:
		return _ropes[Side.LEFT].attached
## True while the right hook is stuck.
var right_attached: bool:
	get:
		return _ropes[Side.RIGHT].attached
## Where the left hook is stuck (meaningless while not attached).
var left_anchor: Vector3:
	get:
		return _ropes[Side.LEFT].anchor
## Where the right hook is stuck (meaningless while not attached).
var right_anchor: Vector3:
	get:
		return _ropes[Side.RIGHT].anchor
## Current left line length (m).
var left_length: float:
	get:
		return _ropes[Side.LEFT].length
## Current right line length (m).
var right_length: float:
	get:
		return _ropes[Side.RIGHT].length

var _ropes: Array[GrappleRope] = []
var _lines: Array[MeshInstance3D] = []
var _was_held: Array[bool] = [false, false]


func _init() -> void:
	enabled = false
	unlock_id = UNLOCK_ID
	for side: int in SIDES:
		var rope := GrappleRope.new()
		rope.detached.connect(_on_rope_detached.bind(side))
		_ropes.append(rope)


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(line_thickness, line_thickness, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = line_color
	mesh.material = material
	for line_name in LINE_NAMES:
		var line := MeshInstance3D.new()
		line.name = line_name
		line.mesh = mesh
		line.top_level = true
		line.visible = false
		add_child(line)
		_lines.append(line)


func physics_tick(skater: CharacterBody3D, delta: float) -> void:
	for side: int in SIDES:
		_update_button(skater, side)
	var airborne := not skater.is_on_floor()
	for rope in _ropes:
		_apply_rope_tuning(rope)
		rope.tick(delta, airborne)
	if left_attached and right_attached:
		_reel_in(skater, delta)
	else:
		for rope in _ropes:
			if rope.attached:
				skater.velocity = rope.constrain_velocity(_hand(skater), skater.velocity, delta)
	_draw_lines(skater)


func update_aim(view_forward: Vector3, _facing: Vector3) -> void:
	aim_forward = view_forward


func is_active() -> bool:
	return left_attached or right_attached


## Casts a hook to [param side] along [param direction]; true if it stuck.
func fire(skater: CharacterBody3D, side: Side, direction: Vector3) -> bool:
	hook_fired.emit(side)
	var from := _hand(skater)
	var to := from + direction.normalized() * max_fire_range
	var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask, [skater.get_rid()])
	var hit := skater.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var rope := _ropes[side]
	_apply_rope_tuning(rope)
	var was_active := is_active()
	rope.attach(hit["position"] as Vector3, from)
	hook_attached.emit(side, rope.anchor)
	if not was_active:
		activated.emit()
	return true


## Lets go of the hook on [param side], if it is stuck.
func release(side: Side) -> void:
	var rope := _ropes[side]
	if not rope.attached:
		return
	rope.release()
	_hook_gone(side)


## World direction a hook on [param side] is fired along.
func aim_direction(side: Side) -> Vector3:
	var forward := aim_forward.normalized()
	if forward.is_zero_approx() or absf(forward.dot(Vector3.UP)) > VERTICAL_LIMIT:
		forward = Vector3.FORWARD
	var turn := deg_to_rad(side_angle_deg) * (1.0 if side == Side.LEFT else -1.0)
	var turned := forward.rotated(Vector3.UP, turn)
	var right := turned.cross(Vector3.UP).normalized()
	return turned.rotated(right, deg_to_rad(aim_pitch_deg)).normalized()


func _on_disabled() -> void:
	for side: int in range(_ropes.size()):
		release(side)
	_was_held = [false, false]


func _update_button(skater: CharacterBody3D, side: Side) -> void:
	var held := input_enabled and Input.is_action_pressed(ACTIONS[side])
	if held and not _was_held[side] and not _ropes[side].attached:
		fire(skater, side, aim_direction(side))
	elif not held:
		release(side)
	_was_held[side] = held


func _reel_in(skater: CharacterBody3D, delta: float) -> void:
	var hand := _hand(skater)
	var midpoint := (left_anchor + right_anchor) * 0.5
	var to_mid := midpoint - hand
	if to_mid.is_zero_approx():
		return
	var pull := to_mid.normalized()
	var velocity := skater.velocity + pull * reel_acceleration * delta
	var along := velocity.dot(pull)
	if along > max_reel_speed:
		velocity -= pull * (along - max_reel_speed)
	skater.velocity = velocity
	for rope in _ropes:
		rope.wind_in(hand)


func _apply_rope_tuning(rope: GrappleRope) -> void:
	rope.payout_speed = payout_speed
	rope.max_length = max_rope_length
	rope.min_length = min_rope_length


func _draw_lines(skater: CharacterBody3D) -> void:
	var hand := _hand(skater)
	for side: int in SIDES:
		var line := _lines[side]
		var rope := _ropes[side]
		var span := rope.anchor - hand
		line.visible = rope.attached and not span.is_zero_approx()
		if not line.visible:
			continue
		var up := Vector3.RIGHT if absf(span.normalized().dot(Vector3.UP)) > VERTICAL_LIMIT \
				else Vector3.UP
		var line_basis := Basis.looking_at(span, up).scaled_local(Vector3(1.0, 1.0, span.length()))
		line.global_transform = Transform3D(line_basis, hand + span * 0.5)


func _hand(skater: CharacterBody3D) -> Vector3:
	return skater.global_position + Vector3.UP * fire_height


func _hook_gone(side: Side) -> void:
	_lines[side].visible = false
	hook_released.emit(side)
	if not is_active():
		deactivated.emit()


func _on_rope_detached(side: Side) -> void:
	_hook_gone(side)
