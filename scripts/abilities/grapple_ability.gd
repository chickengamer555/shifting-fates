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
## Each hook's line is a [GrappleRope]. A hook ends only when its button is released (never
## on landing, never on its own, never for being long).
## [br]One hook stuck: the line reels in ([member reel_speed] m/s down to
## [member reel_shortest], easing off as the swing speeds up to [member reel_fade_speed];
## slack is taken up at once), so a hook fired ahead and up from
## the ground pulls the skater off it and up towards the anchor instead of dragging it along
## the floor, while the skater swings round the anchor like a real pendulum on the Skater's
## own gravity. The line is a hard constraint ([method GrappleRope.sling_velocity]): the
## body never goes past its length, the swing speed comes from energy conservation (no
## damping, no drag, no cap) with the reel's pull added on top, and a line snapping taut
## turns the fall along the swing instead of stopping it. Once per hook, passing the bottom
## of the arc adds a small arcade boost ([member swing_boost] of the speed plus
## [member swing_boost_add] m/s, while under [member swing_boost_limit]), so chained swings
## snowball. Letting go keeps every bit of the speed (a fling).
## [br]Both hooks stuck: an Attack on Titan zip. The skater accelerates hard
## ([member zip_acceleration] m/s², in over [member zip_ramp_time]) towards the midpoint of
## the two anchors, up to [member zip_max_speed] (faster than that is kept, never braked);
## sideways speed is turned into the pull ([member zip_steer]) rather than thrown away.
## Within [member zip_pass_radius] of the midpoint the pull stops and the skater flies on
## with all its momentum: no braking on arrival, no unhooking, no yank back (the lines pay
## out while the body flies away from the anchors faster than [member zip_payout_speed],
## and hold again once it slows).
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
## Emitted when a hook lets go (button released or input switched off).
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
@export var fire_height: float = 1.2
## What the hooks can stick to.
@export_flags_3d_physics var hit_mask: int = DEFAULT_HIT_MASK
## Seconds a hook recharges after it lets go before it can fire again.
@export_range(0.0, 3.0, 0.05) var cooldown: float = 2.0

@export_group("Swing")
## How fast (m/s) a lone hook's line reels in while its button is held.
@export var reel_speed: float = 12.0
## A lone hook reels its line in no shorter than this (m), leaving room to swing on.
@export var reel_shortest: float = 5.0
## The reel eases off as the swing gets going: at this swing speed (m/s, round the anchor)
## and above it pulls no more, so a fast swing keeps its line and turns its speed forward
## instead of climbing into the anchor.
@export var reel_fade_speed: float = 18.0
## Share of the speed added once per hook as the swing passes the bottom of its arc.
@export var swing_boost: float = 0.15
## Speed (m/s) added on top of [member swing_boost] at that moment.
@export var swing_boost_add: float = 2.0
## No bottom-of-the-arc boost at or above this speed (m/s); faster swings are kept as they are.
@export var swing_boost_limit: float = 60.0

@export_group("Zip")
## Acceleration (m/s²) towards the anchors' midpoint while both hooks are stuck.
@export var zip_acceleration: float = 48.0
## The zip pulls until the speed towards the midpoint reaches this (m/s); faster is kept.
@export var zip_max_speed: float = 60.0
## Seconds the zip's pull takes to come in fully (a snap, not a hoist).
@export var zip_ramp_time: float = 0.08
## Share of the sideways speed per second turned into the pull (speed kept, not lost).
@export var zip_steer: float = 4.0
## Within this distance (m) of the midpoint the pull stops and the skater flies through.
@export var zip_pass_radius: float = 2.5
## After passing the midpoint, the lines pay out while the body moves away from the anchors
## faster than this (m/s), so momentum is never yanked back.
@export var zip_payout_speed: float = 3.0

@export_group("Rope")
## Longest line (m) a [GrappleRope] would pay out to; the hooks never pay out (a lone hook
## reels in, a zip winds in), so this only bounds the rope's own rules.
@export var max_rope_length: float = 25.0
## Line (m) a hook that stuck further than [member max_rope_length] away may pay out beyond
## its attach length (rope rule only, as above).
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
var _zip_time: float = 0.0
var _zip_passed: bool = false
## Per hook: true once its bottom-of-the-arc boost has been given.
var _boosted: Array[bool] = [false, false]
## Per hook: true while the last swing step was heading down.
var _descending: Array[bool] = [false, false]
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
	var zipping := left_attached and right_attached
	for rope_on_side in _ropes:
		_apply_rope_tuning(rope_on_side)
		rope_on_side.tick(delta, false)
	if zipping:
		_zip_time += delta
		_zip(skater, delta)
		return
	_zip_time = 0.0
	_zip_passed = false
	for side: int in SIDES:
		if _ropes[side].attached:
			_swing(skater, side, on_floor, delta)


func update_aim(view_forward: Vector3, _facing: Vector3) -> void:
	aim_forward = view_forward


func is_active() -> bool:
	return left_attached or right_attached


## The rope of the hook on [param side].
func rope(side: Side) -> GrappleRope:
	return _ropes[side]


## Line the hook on [param side] still has to reel in (down to [member reel_shortest]),
## over what it had to reel in when it stuck (0..1; 1 while not attached).
func line_left_fraction(side: Side) -> float:
	var rope_on_side := _ropes[side]
	if not rope_on_side.attached:
		return 1.0
	var spare := rope_on_side.attach_length - reel_shortest
	if spare <= 0.0:
		return 0.0
	return clampf((rope_on_side.length - reel_shortest) / spare, 0.0, 1.0)


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
	_zip_time = 0.0
	_zip_passed = false
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
	_boosted[side] = false
	_descending[side] = false
	_zip_passed = false
	_zip_time = 0.0
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


## One hook: a pendulum on a hard line that reels in, keeping the swing's energy, plus one
## boost per hook at the bottom of the arc.
func _swing(skater: CharacterBody3D, side: int, on_floor: bool, delta: float) -> void:
	var rope_on_side := _ropes[side]
	var hand := _hand(skater)
	var shortest := maxf(reel_shortest, min_rope_length)
	if rope_on_side.length > shortest:
		# Reeling: slack is taken up and the line pulled in, down to the shortest.
		var outward := (hand - rope_on_side.anchor).normalized()
		var round_speed := (skater.velocity - outward * skater.velocity.dot(outward)).length()
		var fade := clampf(1.0 - round_speed / maxf(reel_fade_speed, 0.001), 0.0, 1.0)
		var taken_up := minf(rope_on_side.length, rope_on_side.distance_from(hand))
		rope_on_side.length = maxf(taken_up - reel_speed * fade * delta, shortest)
	# On the floor the Skater adds no gravity, so none is predicted.
	var gravity := Vector3.ZERO if on_floor else skater.get_gravity()
	var before := skater.velocity
	var velocity := rope_on_side.sling_velocity(hand, before, gravity, delta)
	var taut := not velocity.is_equal_approx(before)
	var descending := velocity.y < 0.0
	var below := hand.y < rope_on_side.anchor.y
	if taut and below and _descending[side] and not descending and not _boosted[side]:
		_boosted[side] = true
		var speed := velocity.length()
		if speed > 0.0 and speed < swing_boost_limit:
			var boosted := minf(speed * (1.0 + swing_boost) + swing_boost_add, swing_boost_limit)
			velocity *= boosted / speed
	_descending[side] = descending and not on_floor
	skater.velocity = velocity


## Both hooks: a fast pull at the anchors' midpoint, flying through it on momentum.
func _zip(skater: CharacterBody3D, delta: float) -> void:
	var hand := _hand(skater)
	var to_mid := (left_anchor + right_anchor) * 0.5 - hand
	var distance := to_mid.length()
	if distance <= zip_pass_radius:
		_zip_passed = true
	var velocity := skater.velocity
	if not _zip_passed and distance > 0.0:
		var pull := to_mid / distance
		var along := velocity.dot(pull)
		var sideways := velocity - pull * along
		# Sideways speed is steered into the pull, not thrown away.
		var kept := sideways * exp(-zip_steer * delta)
		if along > 0.0:
			along = sqrt(along * along + sideways.length_squared() - kept.length_squared())
		var ramp := clampf(_zip_time / maxf(zip_ramp_time, 0.001), 0.0, 1.0)
		if along < zip_max_speed:
			along = minf(along + zip_acceleration * ramp * delta, zip_max_speed)
		velocity = kept + pull * along
	var gravity := skater.get_gravity()
	for rope_on_side in _ropes:
		if _zip_passed:
			# Flying away on momentum: the lines pay out instead of yanking back.
			var outward := (hand - rope_on_side.anchor).normalized()
			if (velocity + gravity * delta).dot(outward) > zip_payout_speed:
				rope_on_side.length = maxf(rope_on_side.length,
						rope_on_side.distance_from(hand + velocity * delta))
		else:
			rope_on_side.wind_in(hand)
		var next := rope_on_side.constrain_velocity(hand, velocity + gravity * delta, delta)
		velocity = next - gravity * delta
	skater.velocity = velocity


func _apply_rope_tuning(rope_on_side: GrappleRope) -> void:
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
