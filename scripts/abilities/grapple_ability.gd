class_name GrappleAbility
extends SkaterAbility
## Two grapple hooks: left mouse fires the left hook, right mouse the right one, one line per
## hand at a time and as many shots as the player likes. A momentum grapple: hooks fire
## instantly, swings keep their speed, the reel is a steady hoist.
##
## A fresh press fires the hook exactly at the crosshair: the centre of the screen. A ray from
## the current camera through the screen centre finds the point the player is looking at,
## and the hook sticks there at once (no travel time; the drawn line whips out over
## [member hook_fly_time]); with no camera the ray goes from the hand along
## [member aim_forward]. If it hits world geometry the hook sticks there, however far away
## (shooting has no reach limit: [member max_fire_range] is 10 km), and stays while the
## button is held. The level's invisible walls never catch a hook. Every physics frame the
## same ray is cast to tell the HUD whether the crosshair is on something hookable
## ([member target_hookable]).
##
## Each hook's line is a [GrappleRope]. While the button is held on the ground the line
## pays out ([member payout_speed]) up to its longest ([member max_rope_length]); in the air
## it keeps its length, and it never lets go for being long. A hook lets go when its button
## is released, or when the skater lands after [member landing_air_time] in the air (not
## while reeling). With one hook stuck the skater swings under it on real gravity (the
## Skater's own): the line only turns the velocity, so a swing keeps its speed
## ([method GrappleRope.swing_velocity], with a tiny [member swing_damping]) and letting go
## at the bottom or on the upswing flings the skater on with it. With both hooks stuck the
## skater is hoisted smoothly towards the midpoint of the two anchors: the pull ramps up
## over [member reel_ramp_time] to [member max_reel_speed], eases off on arrival and never
## unhooks on its own; sideways drift is bled off so the pull goes where it points.
## After a hook lets go it recharges for [member cooldown] seconds; a press while it
## recharges fires as soon as it is ready if the button is still held.
##
## A black line with a small hook head is drawn from the rider's hand bone (left hook from
## the left hand, right from the right) to each anchor, following the animated rig every
## frame, sagging while the line is slack, with a faint light edge so it reads on dark skies.
## The rope physics uses a steady point [member fire_height] above the skater's origin.
##
## The ability only edits [code]velocity[/code], so the Skater keeps applying gravity and
## [code]move_and_slide()[/code]. The Skater feeds [member aim_forward] (the camera's
## forward) through [method update_aim] every frame. Locked until the story unlocks it:
## [member enabled] starts false and [member SkaterAbility.unlock_id] is
## [code]grapple[/code]. Disabling it lets go of both hooks.

## Emitted when a hook sticks; [param side] is a [enum Side], [param point] the anchor.
signal hook_attached(side: int, point: Vector3)
## Emitted when a hook lets go (button released, landed, or input switched off).
signal hook_released(side: int)
## Emitted when a hook is cast on [param side], whether or not it then sticks.
signal hook_fired(side: int)

enum Side { LEFT, RIGHT }

const SIDES: Array[int] = [Side.LEFT, Side.RIGHT]
const ACTIONS: Array[String] = ["grapple_left", "grapple_right"]
const LINE_NAMES: Array[String] = ["LeftLine", "RightLine"]
## Rig bones each line starts from (Quaternius mannequin).
const HAND_BONES: Array[StringName] = [&"hand_l", &"hand_r"]
## Hooks stick to world and phaseable geometry.
const DEFAULT_HIT_MASK := PhysicsLayers.WORLD_MASK | PhysicsLayers.PHASEABLE_MASK
## GameState id that unlocks the hooks.
const UNLOCK_ID := &"grapple"
const EDGE_SHADER := preload("res://scripts/abilities/grapple_line_edge.gdshader")

## Length (m) of the aim ray. Shooting has no reach limit, so this is far past any level.
@export var max_fire_range: float = 10000.0
## Height (m) of the rope's physics point above the skater's origin (the line is drawn from
## the hand bone).
@export var fire_height: float = 0.5
## What the hooks can stick to.
@export_flags_3d_physics var hit_mask: int = DEFAULT_HIT_MASK
## Seconds a hook recharges after it lets go before it can fire again.
@export_range(0.0, 3.0, 0.05) var cooldown: float = 1.6
## A hook lets go when the skater lands after at least this long (s) in the air.
@export var landing_air_time: float = 0.15

@export_group("Swing and reel")
## Speed lost per second while swinging on one hook (0..1 of the velocity, kept tiny).
@export var swing_damping: float = 0.01
## How fast (m/s²) the reel brings the speed towards the midpoint to its target.
@export var reel_acceleration: float = 22.0
## Steady hoist speed (m/s) towards the midpoint once the reel has ramped up.
@export var max_reel_speed: float = 11.0
## Seconds the reel takes to ramp from still to [member max_reel_speed].
@export var reel_ramp_time: float = 0.9
## Share of the sideways velocity bled off per second while reeling, so the pull goes where
## it points instead of orbiting the anchors.
@export var reel_side_damping: float = 2.5
## Within this distance (m) of the midpoint the pull eases off, so the skater arrives
## instead of buzzing round the anchors.
@export var reel_arrive_distance: float = 2.5

@export_group("Rope")
## How fast (m/s) a line pays out while its button is held on the ground.
@export var payout_speed: float = 2.5
## Longest line (m) for a hook that stuck closer than this; it stops paying out there.
@export var max_rope_length: float = 25.0
## Line (m) a hook that stuck further than [member max_rope_length] away may pay out beyond
## its attach length.
@export var max_rope_slack: float = 4.0
## Shortest line (m).
@export var min_rope_length: float = 1.5

@export_group("Line")
## Radius (m) of the drawn line close up.
@export var line_radius: float = 0.016
## The line is never drawn thinner than this many pixels, however far away.
@export var line_min_pixels: float = 1.6
## Colour of the drawn line and hook head.
@export var line_color: Color = Color(0.015, 0.015, 0.02)
## Colour of the faint edge drawn round the line so it reads on dark skies.
@export var line_edge_color: Color = Color(0.7, 0.72, 0.78, 0.5)
## Width (px) of that edge.
@export var line_edge_pixels: float = 1.0
## How much a slack line sags (1 = a hanging rope of that length).
@export var line_sag: float = 1.0
## Deepest sag (m).
@export var line_max_sag: float = 2.0
## Seconds the drawn line takes to whip out to a fresh anchor (physics sticks at once).
@export var hook_fly_time: float = 0.07
## Length and radius (m) of the hook head drawn at the anchor.
@export var hook_head_length: float = 0.26
@export var hook_head_radius: float = 0.07

## Direction the player is aiming (usually the camera's forward), set by the Skater.
var aim_forward: Vector3 = Vector3.FORWARD
## True while the crosshair points at something a hook would stick to.
var target_hookable: bool = false
## Distance (m) from the camera to what the crosshair points at, or INF when nothing.
var target_distance: float = INF
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
## Seconds until the left hook has recharged (0 when ready).
var left_recharge: float:
	get:
		return _recharge[Side.LEFT]
## Seconds until the right hook has recharged (0 when ready).
var right_recharge: float:
	get:
		return _recharge[Side.RIGHT]

var _ropes: Array[GrappleRope] = []
var _lines: Array[MeshInstance3D] = []
var _meshes: Array[ImmediateMesh] = []
var _was_held: Array[bool] = [false, false]
var _wants_fire: Array[bool] = [false, false]
var _recharge: Array[float] = [0.0, 0.0]
var _fly: Array[float] = [1.0, 1.0]
var _air_time: float = 0.0
var _reel_time: float = 0.0
var _skater: CharacterBody3D = null
var _rig: SkaterRig = null


func _init() -> void:
	enabled = false
	unlock_id = UNLOCK_ID
	for side: int in SIDES:
		var rope := GrappleRope.new()
		rope.lets_go_when_too_long = false
		rope.detached.connect(_on_rope_detached.bind(side))
		_ropes.append(rope)


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = line_color
	var edge := ShaderMaterial.new()
	edge.shader = EDGE_SHADER
	edge.set_shader_parameter("edge_color", line_edge_color)
	edge.set_shader_parameter("edge_pixels", line_edge_pixels)
	material.next_pass = edge
	for line_name in LINE_NAMES:
		var mesh := ImmediateMesh.new()
		var line := MeshInstance3D.new()
		line.name = line_name
		line.mesh = mesh
		line.material_override = material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.top_level = true
		line.visible = false
		add_child(line)
		_lines.append(line)
		_meshes.append(mesh)


func _process(delta: float) -> void:
	for side: int in SIDES:
		_fly[side] = minf(_fly[side] + delta / maxf(hook_fly_time, 0.001), 1.0)
	_draw_lines()


func physics_tick(skater: CharacterBody3D, delta: float) -> void:
	if skater != _skater:
		_skater = skater
		var host := skater as Skater
		_rig = host.rig if host != null else null
	for side: int in SIDES:
		_recharge[side] = maxf(_recharge[side] - delta, 0.0)
		_update_button(skater, side)
	_update_target(skater)
	var on_floor := skater.is_on_floor()
	var reeling := left_attached and right_attached
	if on_floor and _air_time >= landing_air_time and not reeling:
		for side: int in SIDES:
			release(side)
	_air_time = 0.0 if on_floor else _air_time + delta
	for rope in _ropes:
		_apply_rope_tuning(rope)
		rope.tick(delta, on_floor and not reeling)
	if reeling:
		_reel_time += delta
		_reel_in(skater, delta)
		return
	_reel_time = 0.0
	for rope in _ropes:
		if rope.attached:
			var swung := rope.swing_velocity(_hand(skater), skater.velocity, delta)
			skater.velocity = swung * maxf(1.0 - swing_damping * delta, 0.0)


func update_aim(view_forward: Vector3, _facing: Vector3) -> void:
	aim_forward = view_forward


func is_active() -> bool:
	return left_attached or right_attached


## The rope of the hook on [param side].
func rope(side: Side) -> GrappleRope:
	return _ropes[side]


## Line left before the hook on [param side] lets go, over what it had to spare (0..1).
func line_left_fraction(side: Side) -> float:
	return _ropes[side].line_left_fraction() if _ropes[side].attached else 1.0


## How far the hook on [param side] has recharged (0 just released, 1 ready).
func recharge_fraction(side: Side) -> float:
	if cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _recharge[side] / cooldown, 0.0, 1.0)


## Casts a hook to [param side] along [param direction] from the hand; true if it stuck.
func fire(skater: CharacterBody3D, side: Side, direction: Vector3) -> bool:
	var from := _hand(skater)
	return _fire_ray(skater, side, from, from + direction.normalized() * max_fire_range)


## Casts a hook to [param side] at the crosshair (see the class notes); true if it stuck.
func fire_at_crosshair(skater: CharacterBody3D, side: Side) -> bool:
	var ray := _crosshair_ray(skater)
	return _fire_ray(skater, side, ray[0], ray[1])


## Lets go of the hook on [param side], if it is stuck.
func release(side: Side) -> void:
	var rope_on_side := _ropes[side]
	if not rope_on_side.attached:
		return
	rope_on_side.release()
	_hook_gone(side)


## World direction a hook is fired along when there is no camera: straight along
## [member aim_forward], the same for both sides.
func aim_direction(_side: Side) -> Vector3:
	return _aim_forward()


func _on_disabled() -> void:
	for side: int in range(_ropes.size()):
		release(side)
	_was_held = [false, false]
	_wants_fire = [false, false]
	_reel_time = 0.0
	target_hookable = false


## [from, to] of the crosshair ray: from the current camera through the screen centre, or
## from the hand along [member aim_forward] without one.
func _crosshair_ray(skater: CharacterBody3D) -> Array[Vector3]:
	var camera := skater.get_viewport().get_camera_3d()
	var ray: Array[Vector3] = []
	if camera == null:
		var from := _hand(skater)
		ray.assign([from, from + _aim_forward() * max_fire_range])
	else:
		var origin := camera.global_position
		ray.assign([origin, origin - camera.global_basis.z * max_fire_range])
	return ray


## What the crosshair ray hits that a hook would stick to, or an empty Dictionary.
func _hook_hit(skater: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask, [skater.get_rid()])
	var hit := skater.get_world_3d().direct_space_state.intersect_ray(query)
	# The level's invisible walls are not something to hang from: aiming at open sky misses.
	if hit.is_empty() or hit["collider"] is InvisibleBarrier:
		return {}
	return hit


func _update_target(skater: CharacterBody3D) -> void:
	var ray := _crosshair_ray(skater)
	var hit := _hook_hit(skater, ray[0], ray[1])
	target_hookable = not hit.is_empty()
	target_distance = ray[0].distance_to(hit["position"] as Vector3) if target_hookable else INF


func _fire_ray(skater: CharacterBody3D, side: Side, from: Vector3, to: Vector3) -> bool:
	hook_fired.emit(side)
	var hit := _hook_hit(skater, from, to)
	if hit.is_empty():
		return false
	var rope_on_side := _ropes[side]
	_apply_rope_tuning(rope_on_side)
	var was_active := is_active()
	rope_on_side.attach(hit["position"] as Vector3, _hand(skater))
	_fly[side] = 0.0 if hook_fly_time > 0.0 else 1.0
	hook_attached.emit(side, rope_on_side.anchor)
	if not was_active:
		activated.emit()
	return true


## A fresh press asks for a hook; it fires once the hook has recharged, if still held.
func _update_button(skater: CharacterBody3D, side: Side) -> void:
	var held := input_enabled and Input.is_action_pressed(ACTIONS[side])
	if held and not _was_held[side]:
		_wants_fire[side] = true
	if not held:
		_wants_fire[side] = false
		release(side)
	elif _wants_fire[side] and not _ropes[side].attached and _recharge[side] <= 0.0:
		_wants_fire[side] = false
		fire_at_crosshair(skater, side)
	_was_held[side] = held


func _reel_in(skater: CharacterBody3D, delta: float) -> void:
	var hand := _hand(skater)
	var to_mid := (left_anchor + right_anchor) * 0.5 - hand
	var distance := to_mid.length()
	var velocity := skater.velocity
	if distance > 0.0:
		var pull := to_mid / distance
		# The target speed ramps in smoothly and eases off on arrival: a hoist, not a yank.
		var ramp := smoothstep(0.0, 1.0, _reel_time / maxf(reel_ramp_time, 0.001))
		var arrive := clampf(distance / maxf(reel_arrive_distance, 0.001), 0.0, 1.0)
		var target := max_reel_speed * ramp * arrive
		var along := velocity.dot(pull)
		var sideways := (velocity - pull * along) * maxf(1.0 - reel_side_damping * delta, 0.0)
		# Speed already heading in is kept (no braking a swing) until the anchors are near.
		if along < target or arrive < 1.0:
			along = move_toward(along, target, reel_acceleration * delta)
		velocity = sideways + pull * along
	for rope_on_side in _ropes:
		rope_on_side.wind_in(hand)
		velocity = rope_on_side.constrain_velocity(hand, velocity, delta)
	skater.velocity = velocity


func _apply_rope_tuning(rope_on_side: GrappleRope) -> void:
	rope_on_side.payout_speed = payout_speed
	rope_on_side.max_length = max_rope_length
	rope_on_side.max_slack = max_rope_slack
	rope_on_side.min_length = min_rope_length


func _aim_forward() -> Vector3:
	var forward := aim_forward.normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	return forward


func _hand(skater: CharacterBody3D) -> Vector3:
	return skater.global_position + Vector3.UP * fire_height


## Where the line on [param side] starts: the rig's hand bone, or the rope's physics point
## on a skater without a rig.
func _line_start(side: Side) -> Vector3:
	if _rig != null and _rig.pose != null:
		return _rig.pose.bone_global_position(HAND_BONES[side])
	return _hand(_skater)


func _draw_lines() -> void:
	if _skater == null:
		return
	var camera := get_viewport().get_camera_3d()
	for side: int in SIDES:
		var line := _lines[side]
		var rope_on_side := _ropes[side]
		line.visible = rope_on_side.attached
		if not line.visible:
			continue
		var start := _line_start(side)
		var reach := ease(_fly[side], 0.4)
		var end := start.lerp(rope_on_side.anchor, reach)
		line.global_transform = Transform3D(Basis.IDENTITY, start)
		var slack := rope_on_side.length - rope_on_side.distance_from(_hand(_skater))
		var mesh := GrappleLineMesh.new(_meshes[side], start, camera, line_radius, line_min_pixels)
		mesh.draw(end, _sag(start.distance_to(end), slack * reach), hook_head_length,
				hook_head_radius)


## How deep (m) a line spanning [param span] with [param slack] of extra rope sags.
func _sag(span: float, slack: float) -> float:
	if slack <= 0.0 or span <= 0.0:
		return 0.0
	# A shallow hanging rope of length span + slack sags by about sqrt(3 span slack / 8).
	return minf(sqrt(3.0 * span * slack / 8.0) * line_sag, line_max_sag)


func _hook_gone(side: Side) -> void:
	_lines[side].visible = false
	_recharge[side] = cooldown
	hook_released.emit(side)
	if not is_active():
		deactivated.emit()


func _on_rope_detached(side: Side) -> void:
	_hook_gone(side)
