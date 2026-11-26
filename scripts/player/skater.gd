class_name Skater
extends CharacterBody3D
## Momentum-based skateboarder: the player's body in every level.
##
## The board rolls along [member heading] and never slides sideways. Controls (see
## docs/CONTROLS.md):
## [br]- Shift ([code]push[/code]): a hard push, an instant speed kick up to
##   [member max_push_speed]. Holding it pushes again every [member push_cooldown].
## [br]- W: a gentle push that keeps accelerating up to [member cruise_speed].
## [br]- A / D: steer the heading. Turning gets slower the faster you roll.
## [br]- S / Z: brake. Coasting with no input slows you by [member rolling_friction].
## [br]- Space: tap for an ollie, hold to charge a spring jump, release to jump.
## [br]- In the air (see [TrickCatalog] for every name):
## [br]  Q + W/S/A/D flips (front flip, back flip, kickflip, heelflip; two keys at once combine,
##   W + A is a Front Kickflip). Either key may go down first: a direction pressed while Q
##   is held is used at once (after [member chord_time], so a second key can join it); a
##   Q press over held directions waits [member trick_choose_time] for a fresh one, then
##   uses the most recently pressed held direction (a W held for cruising or an A/D held for
##   steering never hijacks a fresh press). A trick asked for just before the take-off
##   counts too ([member trick_buffer_time]).
## [br]  Holding the keys repeats the trick: with Q and the trick's direction(s) still held,
##   the next one starts as soon as the last one ends, as long as there is air left to
##   finish it (a repeat never starts that would land mid-rotation; a fresh press always
##   does).
## [br]  E ([code]board_trick[/code]) with an optional direction spins the board flat under
##   the rider: Pop Shove-it, 360 Shove-it, Varial Kickflip, 360 Flip... Held, it repeats.
## [br]  Q + mouse left/right spins the rider and board; A/D alone turn the board and the
##   flight path together. The whole turn made in the air is scored on a clean landing as
##   a Frontside / Backside 180, 360, 540...
## [br]  Ctrl (front hand) / Alt (back hand) grab, with an optional direction for the grab
##   (Ctrl + W Nosegrab, Alt + S Tailgrab...). The direction keys pick the grab then and
##   don't steer.
##
## Landings are forgiving: the board always lines up with the direction of travel on
## touch-down (steering in the air never bails), and a trick only bails when its rotation
## is less than [member landing_turn_fraction] done (mid-flip or upside down); the rest of
## the turn finishes on the ground.
##
## The camera orbits with the mouse independently of the board and drifts back behind it
## while rolling. Mouse capture lives here so it works in any scene the skater is in: the
## mouse is captured only while the skater has the controls ([member input_enabled]).
##
## Trick and grab ids come from [TrickCatalog], the single source of truth for what a
## direction does and what it scores.
##
## Abilities are [SkaterAbility] children (grind, grapple, rocket boost, shift phase). Each
## physics frame the skater hands every enabled one the camera's forward and its heading
## ([method SkaterAbility.update_aim]) and ticks it. Then:
## [br]- If no ability controls the movement, the skater keeps any horizontal velocity an
##   ability added (boost, grapple pull) as its new rolling speed and heading, and runs its
##   own movement.
## [br]- If one [method SkaterAbility.is_controlling_movement] (a dash), the skater skips its
##   own movement and faces along the ability's velocity.
## [br]- If that ability also [method SkaterAbility.places_body_directly] (grinding), the
##   skater skips gravity, [method move_and_slide] and its air state as well: a rail is
##   neither ground nor air, so it never fires [signal took_off] or counts air time.
## [br]When an ability lets go, the skater adopts whatever velocity it left behind.
##
## Leaving the floor only counts as a take-off after [constant TAKEOFF_GRACE] seconds in
## the air, so a one-frame hop over a slope crest or kicker lip fires nothing.
##
## Gated abilities ([member SkaterAbility.unlock_id]) are switched on and off from GameState
## on ready and whenever the level changes ([method bind_progress]). A saved paint job
## ([Appearance]) is applied to the rig on ready.

## Left the ground (ollie, spring jump, rolling off a ledge or a kicker).
signal took_off
## Touched down. [param clean] is false when landing mid-trick (rotation under
## [member landing_turn_fraction] round).
signal landed(clean: bool)
## A flip or board trick started in the air ([TrickCatalog] id, e.g. kickflip, tre_flip).
signal trick_performed(trick_id: StringName)
## A spin was landed clean: [param spin_id] is a [TrickCatalog] spin (e.g. fs_360).
signal spin_landed(spin_id: StringName)
## A grab started in the air. [param grab_id] is a [TrickCatalog] grab (e.g. melon_grab).
signal grab_started(grab_id: StringName)
## A grab ended (key released or landed).
signal grab_ended(grab_id: StringName)

const GAME_STATE := preload("res://autoload/game_state.gd")
const NO_TRICK := TrickCatalog.NO_TRICK
const NO_GRAB := TrickCatalog.NO_TRICK
## Seconds off the floor before it counts as a take-off (ignores one-frame flickers).
const TAKEOFF_GRACE := 0.1
## The two trick keys: Q flips, E board tricks.
const TRICK_ACTIONS: Array[StringName] = [&"trick", &"board_trick"]
## How far down the repeat guard looks for the ground it will land on (m).
const GROUND_PROBE := 80.0
## Direction actions and the stick input each one stands for (see
## [method TrickCatalog.trick_for_input]: negative y is forward).
const DIRECTION_INPUTS: Dictionary[StringName, Vector2] = {
	&"move_forward": Vector2(0.0, -1.0),
	&"move_backward": Vector2(0.0, 1.0),
	&"move_left": Vector2(-1.0, 0.0),
	&"move_right": Vector2(1.0, 0.0),
}
## Below this horizontal speed a landing keeps the board's heading (no travel to align to).
const ALIGN_MIN_SPEED := 1.0
## Below this speed, adopting an ability's velocity keeps the current heading.
const ADOPT_MIN_SPEED := 0.1

@export_group("Pushing")
## Speed added by one hard push (m/s).
@export var push_impulse: float = 4.0
## Hard pushes stop adding speed at this speed (m/s). Dashes and ramps can go faster.
@export var max_push_speed: float = 12.0
## Seconds between hard pushes while Shift is held.
@export var push_cooldown: float = 0.45
## Gentle W push acceleration (m/s^2).
@export var cruise_acceleration: float = 3.0
## The gentle push stops accelerating at this speed (m/s).
@export var cruise_speed: float = 6.0

@export_group("Steering")
## Turn rate when standing still (rad/s).
@export var max_turn_rate: float = 3.0
## Turn rate at [member max_push_speed] and above (rad/s).
@export var min_turn_rate: float = 1.0
## How fast A / D turn the board in the air (rad/s). The flight path turns with it, so
## the board always lands pointing where it travels. The turn counts toward a spin.
@export var air_spin_rate: float = 3.2
## Q + mouse spin: radians of spin per pixel of sideways mouse motion.
@export var spin_mouse_sensitivity: float = 0.008
## Fastest the Q + mouse spin turns the rider (rad/s).
@export var max_spin_rate: float = 14.0
## How fast a spin left part way round (e.g. a 180 landed fakie) turns back to forward on
## the ground (rad/s), like a revert.
@export var revert_rate: float = 9.0

@export_group("Slowing")
## Deceleration while coasting (m/s^2).
@export var rolling_friction: float = 0.8
## Deceleration while braking (m/s^2).
@export var brake_deceleration: float = 12.0

@export_group("Jumping")
## Upward speed of a tapped ollie (m/s).
@export var ollie_velocity: float = 5.0
## Upward speed of a fully charged spring jump (m/s).
@export var spring_velocity: float = 9.0
## Seconds of holding Space to reach a full charge.
@export var charge_time: float = 0.6

@export_group("Air")
## Seconds a body flip takes; other tricks scale it ([method TrickCatalog.time_scale]).
## Gravity in the air is the world's full gravity (no float): a tapped ollie stays up
## about 1 s, room for one flip; more air (spring jump, kicker, grapple swing) fits more.
@export var trick_duration: float = 0.5
## A landing is clean once the trick's rotation ([method SkaterRig.trick_turn]) is at least
## this far round: 0.75 leaves the board under a quarter turn from upright, and the rest
## finishes on the ground. Less than that (mid-flip, upside down) is a bail.
@export_range(0.0, 1.0) var landing_turn_fraction: float = 0.75
## Seconds a Q / E tap with only already-held directions waits for a fresh direction press
## before doing the held direction's trick.
@export var trick_choose_time: float = 0.12
## Seconds a fresh direction waits for a second key to join it (two keys = a diagonal).
@export var chord_time: float = 0.06
## Seconds a Q + direction press is remembered, so a quick tap right after the jump (before
## the take-off is committed, see [constant TAKEOFF_GRACE]) still does the trick.
@export var trick_buffer_time: float = 0.25
## Fraction of speed kept after an unclean landing.
@export_range(0.0, 1.0) var bail_speed_factor: float = 0.4

## Board forward direction, flat and normalized. Use [method set_heading] to change it.
var heading: Vector3 = Vector3.FORWARD
## Horizontal speed (m/s).
var speed: float:
	get:
		return Vector2(velocity.x, velocity.z).length()
## Off while a cutscene, menu or the spectator owns the controls. Passed on to abilities.
var input_enabled: bool = true:
	set = set_input_enabled
## False after Esc, so regaining focus doesn't grab the mouse back.
var wants_mouse: bool = true
## Seconds in the current air phase (0 on the ground).
var air_time: float = 0.0
## Duration of the last completed air phase.
var last_air_time: float = 0.0
## Highest point above the take-off height in the current (or last) air phase (m).
var air_peak_height: float = 0.0
## Whether the last landing was clean.
var last_landing_clean: bool = true
## Trick playing right now, or empty.
var current_trick: StringName = NO_TRICK
## Signed turn made in the air so far (radians, + = frontside): A/D turning plus the
## Q + mouse spin. Scored as a spin on a clean landing.
var air_turn: float = 0.0
## The rider's spin about the vertical on top of the heading (radians), from Q + mouse.
var spin_yaw: float = 0.0
## Grab held right now, or empty.
var current_grab: StringName = NO_GRAB
## Jump charge 0..1 while Space is held on the ground.
var jump_charge: float = 0.0

var _forward_speed: float = 0.0
## Last A/D steer input on the ground (-1..1), for the rig's lean.
var _steer: float = 0.0
## True while the gentle W push is still accelerating (the rig keeps kicking).
var _cruising: bool = false
var _push_cooldown_left: float = 0.0
var _charging: bool = false
var _airborne: bool = false
## True while off the floor but not yet past [constant TAKEOFF_GRACE].
var _leaving_floor: bool = false
var _off_floor_time: float = 0.0
var _takeoff_height: float = 0.0
var _trick_elapsed: float = 0.0
## Physics time (s) each direction action was last pressed (for "most recent wins").
var _direction_pressed_at: Dictionary[StringName, float] = {}
var _clock: float = 0.0
## The trick key (Q or E) whose press is waiting [member _window_left] s for directions,
## or empty; the directions freshly pressed meanwhile.
var _window_action: StringName = &""
var _window_left: float = 0.0
var _window_dirs: Array[StringName] = []
## A trick asked for, waiting for the air for [member _trick_buffer_left] s.
var _buffered_trick: StringName = NO_TRICK
var _trick_buffer_left: float = 0.0
## The key and directions of the last trick asked for: held, they repeat it.
var _repeat_action: StringName = &""
var _repeat_dirs: Array[StringName] = []
## Sideways mouse motion to turn into spin on the next physics frame (radians).
var _spin_pending: float = 0.0
var _ability_had_control: bool = false
var _abilities: Array[SkaterAbility] = []
var _progress: GAME_STATE = null

@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var rig: SkaterRig = $Rig
@onready var camera_rig: SkaterCamera = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
## Hold C near a rail to grind it.
@onready var grind_ability: GrindAbility = $GrindAbility
## Mouse buttons fire the hooks (unlocked from level 2).
@onready var grapple_ability: GrappleAbility = $GrappleAbility
## Middle mouse boosts (unlocked from level 4).
@onready var rocket_boost: RocketBoostAbility = $RocketBoost
## X dashes and phases.
@onready var shift_phase: ShiftPhase = $ShiftPhase


func _ready() -> void:
	set_meta("verify_unit", "Skater")
	heading = _flat(-global_basis.z, Vector3.FORWARD)
	child_order_changed.connect(_refresh_abilities)
	grind_ability.bailed.connect(_on_grind_ability_bailed)
	_refresh_abilities()
	bind_progress(GameState)
	Appearance.apply_saved(rig)
	camera_rig.snap_behind(global_position, heading)
	# Deferred: the level may freeze the controls in its own _ready, right after this one.
	refresh_mouse.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		refresh_mouse()


func _unhandled_input(event: InputEvent) -> void:
	# Esc frees the mouse even while input is off, so it comes before the input check.
	if event.is_action_pressed("ui_cancel"):
		wants_mouse = false
		MouseCursor.release()
		return
	# While frozen the cursor belongs to whatever froze the skater (dialogue, paint, menus).
	if not input_enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.is_pressed() and not captured:
		wants_mouse = true
		MouseCursor.capture()
		return
	if not captured:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _airborne and Input.is_action_pressed("trick"):
		# Q + mouse in the air spins the rider; the camera keeps following behind.
		_spin_pending -= motion.relative.x * spin_mouse_sensitivity
		camera_rig.look_mouse(Vector2(0.0, motion.relative.y))
		return
	camera_rig.look_mouse(motion.relative)


func _physics_process(delta: float) -> void:
	var horizontal_before := _horizontal(velocity)
	_tick_trick(delta)
	var mover := _tick_abilities(delta)
	if mover == null:
		var nudged := not _horizontal(velocity).is_equal_approx(horizontal_before)
		if _ability_had_control or nudged:
			_adopt_velocity()
		_ability_had_control = false
		_move(delta)
	else:
		_ability_had_control = true
		# A jump being charged when an ability took over (e.g. snapping onto a rail on
		# the frame Space was let go) is dropped, so it can't fire later by surprise.
		_charging = false
		jump_charge = 0.0
		_face_travel()
	if mover != null and mover.places_body_directly():
		_leaving_floor = false
	else:
		move_and_slide()
		_update_air_state(delta)
		if is_on_floor() and is_on_wall():
			_forward_speed = minf(_forward_speed, maxf(velocity.dot(heading), 0.0))
	rotation.y = atan2(-heading.x, -heading.z)
	camera_rig.follow(global_position, heading, speed, delta)
	_update_rig()


## How far through the trick playing now (0..1); 0 when none is playing.
func trick_progress() -> float:
	if not _trick_playing():
		return 0.0
	return clampf(_trick_elapsed / trick_length(current_trick), 0.0, 1.0)


## Seconds the trick [param trick_id] takes ([member trick_duration] times its catalog
## time scale).
func trick_length(trick_id: StringName) -> float:
	return maxf(trick_duration * TrickCatalog.time_scale(trick_id), 0.01)


## Seconds until the board comes down on the ground below, falling under gravity from here
## (the take-off height if there is no ground under it); 0 on the ground.
func air_time_left() -> float:
	if not _airborne:
		return 0.0
	var g := maxf(get_gravity().length(), 0.01)
	var ground := _takeoff_height
	var from := global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * GROUND_PROBE,
		collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y
	var drop := maxf(global_position.y - ground, 0.0)
	return (velocity.y + sqrt(velocity.y * velocity.y + 2.0 * g * drop)) / g


## How far round the playing trick's rotation is (0..1, see [method SkaterRig.trick_turn]);
## 0 when none is playing.
func trick_turn() -> float:
	return SkaterRig.trick_turn(current_trick, trick_progress())


## True while the board is off the ground.
func is_airborne() -> bool:
	return _airborne


## Points the board along [param direction] (flattened). Rolling speed is kept.
func set_heading(direction: Vector3) -> void:
	heading = _flat(direction, heading)
	if not _airborne:
		_apply_ground_velocity()


## Sets the rolling speed along the heading (m/s), e.g. for spawns or boost pads.
func set_speed(value: float) -> void:
	_forward_speed = maxf(value, 0.0)
	_apply_ground_velocity()


## Turns the controls on or off for the skater and all its abilities. The mouse follows:
## captured while the skater has the controls (and [member wants_mouse]), free otherwise.
func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if not value:
		_charging = false
		jump_charge = 0.0
	for ability in _abilities:
		ability.input_enabled = value
	if is_node_ready():
		refresh_mouse()


## Captures the mouse when the skater has the controls and [member wants_mouse], frees it
## otherwise. Call it after something else (a menu, the paint creator) used the cursor.
func refresh_mouse() -> void:
	if input_enabled and wants_mouse:
		MouseCursor.capture()
	else:
		MouseCursor.release()


## Takes ability unlocks from [param source] (the GameState autoload by default) now and
## whenever its level changes.
func bind_progress(source: GAME_STATE) -> void:
	if _progress != null and _progress.level_changed.is_connected(_on_progress_level_changed):
		_progress.level_changed.disconnect(_on_progress_level_changed)
	_progress = source
	if _progress != null:
		_progress.level_changed.connect(_on_progress_level_changed)
	apply_unlocks()


## Enables each gated ability exactly when the bound progress has it unlocked.
func apply_unlocks() -> void:
	if _progress == null:
		return
	for ability in _abilities:
		if ability.unlock_id != SkaterAbility.ALWAYS_UNLOCKED:
			ability.enabled = _progress.is_ability_unlocked(ability.unlock_id)


## Paints the rig with [param appearance] (e.g. one fresh from the paint creator).
func apply_appearance(appearance: Appearance) -> void:
	if appearance != null:
		appearance.apply_to(rig)


## Makes the rig see-through (used by the shift phase).
func set_translucent(on: bool) -> void:
	rig.set_phased(on)


## Aims and ticks every enabled ability. Returns the one that owns the movement this
## frame (the last in tree order if several do), or null.
func _tick_abilities(delta: float) -> SkaterAbility:
	var mover: SkaterAbility = null
	var view_forward := -camera.global_basis.z
	for ability in _abilities:
		if not ability.enabled:
			continue
		ability.update_aim(view_forward, heading)
		ability.physics_tick(self, delta)
		if ability.is_controlling_movement():
			mover = ability
	return mover


func _move(delta: float) -> void:
	_push_cooldown_left = maxf(_push_cooldown_left - delta, 0.0)
	_read_trick_input(delta)
	if _airborne:
		velocity += get_gravity() * delta
		_air_controls(delta)
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_revert_spin(delta)
	_ground_controls(delta)
	_apply_ground_velocity()


func _ground_controls(delta: float) -> void:
	_steer = 0.0
	var gentle_push := false
	var braking := false
	if input_enabled:
		_steer = Input.get_axis("move_left", "move_right")
		gentle_push = Input.is_action_pressed("move_forward")
		braking = Input.is_action_pressed("brake") or Input.is_action_pressed("move_backward")
		if Input.is_action_pressed("push") and _push_cooldown_left <= 0.0:
			_hard_push()
		_jump_controls(delta)
	_cruising = gentle_push and not braking and _forward_speed < cruise_speed
	if braking:
		_forward_speed = move_toward(_forward_speed, 0.0, brake_deceleration * delta)
	elif gentle_push and _forward_speed < cruise_speed:
		_forward_speed = minf(_forward_speed + cruise_acceleration * delta, cruise_speed)
	else:
		_forward_speed = move_toward(_forward_speed, 0.0, rolling_friction * delta)
	var speed_ratio := clampf(_forward_speed / max_push_speed, 0.0, 1.0)
	var turn_rate := lerpf(max_turn_rate, min_turn_rate, speed_ratio)
	heading = heading.rotated(Vector3.UP, -_steer * turn_rate * delta)


func _hard_push() -> void:
	_push_cooldown_left = push_cooldown
	if _forward_speed < max_push_speed:
		_forward_speed = minf(_forward_speed + push_impulse, max_push_speed)
	rig.play_push()


## Space starts a charge on the ground; letting go jumps with a charge-weighted velocity.
func _jump_controls(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_charging = true
		jump_charge = 0.0
		return
	if not _charging:
		return
	if Input.is_action_pressed("jump"):
		jump_charge = minf(jump_charge + delta / charge_time, 1.0)
		return
	velocity.y = lerpf(ollie_velocity, spring_velocity, jump_charge)
	_charging = false
	jump_charge = 0.0


func _air_controls(delta: float) -> void:
	if not input_enabled:
		_set_grab(NO_GRAB)
		_spin_pending = 0.0
		return
	if not _trick_playing():
		if _buffered_trick != NO_TRICK:
			_start_trick(_buffered_trick)
		else:
			_repeat_held_trick()
	var grabbing := Input.is_action_pressed("grab_left") or Input.is_action_pressed(
		"grab_right")
	# A/D steer: the board and the flight path turn together. Not while Q or E is held (the
	# keys are making a trick then) nor while grabbing (they pick the grab).
	var trick_keys := Input.is_action_pressed("trick") or Input.is_action_pressed(
		"board_trick")
	if not trick_keys and not grabbing:
		var turn := -Input.get_axis("move_left", "move_right") * air_spin_rate * delta
		heading = heading.rotated(Vector3.UP, turn)
		var horizontal := _horizontal(velocity).rotated(Vector3.UP, turn)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		air_turn += turn
	# Q + mouse: the rider and board spin, the flight path stays.
	var limit := max_spin_rate * delta
	var spin := clampf(_spin_pending, -limit, limit)
	_spin_pending = 0.0
	spin_yaw += spin
	air_turn += spin
	_set_grab(_grab_from_input())


## Turns Q / E presses into a trick request, remembered for [member trick_buffer_time] in
## any state (ground, take-off, air) so the air controls can fire it once airborne:
## [br]- a direction pressed while Q (or E) is held asks at once, after [member chord_time]
##   for a second key to join it (W + A = a diagonal trick);
## [br]- a Q / E press waits [member trick_choose_time] for a fresh direction, then takes
##   the held directions (the latest one, plus a perpendicular one pressed with it). E with
##   no direction is the Pop Shove-it.
func _read_trick_input(delta: float) -> void:
	_clock += delta
	# The buffer waits while another trick is still turning in the air (queued tricks).
	if not (_airborne and _trick_playing()):
		_trick_buffer_left = maxf(_trick_buffer_left - delta, 0.0)
		if is_zero_approx(_trick_buffer_left):
			_buffered_trick = NO_TRICK
	if not input_enabled:
		_window_action = &""
		return
	var fresh: Array[StringName] = []
	for action: StringName in DIRECTION_INPUTS:
		if Input.is_action_just_pressed(action):
			_direction_pressed_at[action] = _clock
			fresh.append(action)
	for action in TRICK_ACTIONS:
		if Input.is_action_just_pressed(action):
			_open_window(action, trick_choose_time if fresh.is_empty() else chord_time, fresh)
			return
	if _window_action != &"":
		for action in fresh:
			if not _window_dirs.has(action):
				_window_dirs.append(action)
		if not fresh.is_empty():
			_window_left = minf(_window_left, chord_time)
		_window_left -= delta
		if _window_left <= 0.0:
			_close_window()
		return
	if fresh.is_empty():
		return
	for action in TRICK_ACTIONS:
		if Input.is_action_pressed(action):
			_open_window(action, chord_time, fresh)
			return


func _open_window(action: StringName, seconds: float, fresh: Array[StringName]) -> void:
	_window_action = action
	_window_left = seconds
	_window_dirs = fresh.duplicate()


## Picks the trick for the window's key and directions and remembers it.
func _close_window() -> void:
	var action := _window_action
	_window_action = &""
	var dirs := _window_dirs if not _window_dirs.is_empty() else _held_chord()
	var trick_id := _trick_for(action, dirs)
	if trick_id == NO_TRICK:
		return
	_repeat_action = action
	_repeat_dirs = dirs.duplicate()
	_buffered_trick = trick_id
	_trick_buffer_left = trick_buffer_time


## The trick [param action] (Q or E) does with [param dirs] held, or none.
static func _trick_for(action: StringName, dirs: Array[StringName]) -> StringName:
	var input := Vector2.ZERO
	for dir in dirs:
		input += DIRECTION_INPUTS[dir]
	if action == &"board_trick":
		return TrickCatalog.board_trick_for_input(input)
	return TrickCatalog.trick_for_input(input)


## The held directions a Q / E press over held keys means: the most recently pressed one,
## plus a held perpendicular one pressed within [member chord_time] of it.
func _held_chord() -> Array[StringName]:
	var latest := &""
	var latest_at := -INF
	for action: StringName in DIRECTION_INPUTS:
		var at: float = _direction_pressed_at.get(action, -INF)
		if Input.is_action_pressed(action) and at > latest_at:
			latest = action
			latest_at = at
	var chord: Array[StringName] = []
	if latest == &"":
		return chord
	chord.append(latest)
	for action: StringName in DIRECTION_INPUTS:
		var at: float = _direction_pressed_at.get(action, -INF)
		var across := absf(DIRECTION_INPUTS[action].dot(DIRECTION_INPUTS[latest])) < 0.5
		if across and Input.is_action_pressed(action) and latest_at - at <= chord_time:
			chord.append(action)
			break
	return chord


## Hold to repeat: with the last trick's key and directions still held, starts it again,
## but only if there is air left to finish it.
func _repeat_held_trick() -> void:
	if _repeat_action == &"" or not Input.is_action_pressed(_repeat_action):
		return
	if _window_action != &"":
		return
	for dir in _repeat_dirs:
		if not Input.is_action_pressed(dir):
			return
	var trick_id := _trick_for(_repeat_action, _repeat_dirs)
	if trick_id == NO_TRICK or air_time_left() < trick_length(trick_id):
		return
	_start_trick(trick_id)


## True while the trick playing will start again the moment it ends (its keys held, air
## left for another), so the rig can flow from one into the next.
func _repeat_coming() -> bool:
	if not _airborne or not _trick_playing() or not input_enabled:
		return false
	if _repeat_action == &"" or not Input.is_action_pressed(_repeat_action):
		return false
	for dir in _repeat_dirs:
		if not Input.is_action_pressed(dir):
			return false
	if _trick_for(_repeat_action, _repeat_dirs) != current_trick:
		return false
	var left := trick_length(current_trick) - _trick_elapsed
	return air_time_left() - left >= trick_length(current_trick)


## Runs the trick clock in the air and on the ground (a trick landed far enough through
## finishes its rotation after touch-down).
func _tick_trick(delta: float) -> void:
	if not _trick_playing():
		return
	_trick_elapsed += delta
	if _trick_elapsed >= trick_length(current_trick):
		current_trick = NO_TRICK


func _start_trick(trick_id: StringName) -> void:
	current_trick = trick_id
	_trick_elapsed = 0.0
	_buffered_trick = NO_TRICK
	_trick_buffer_left = 0.0
	trick_performed.emit(trick_id)


func _trick_playing() -> bool:
	return current_trick != NO_TRICK


## True when touching down now would land the trick: none playing, or turned far enough
## round that the board is nearly upright again.
func _trick_landable() -> bool:
	return not _trick_playing() or trick_turn() >= landing_turn_fraction


## The grab the held keys make: Ctrl (front hand) or Alt (back hand), with the direction
## held picking which one.
func _grab_from_input() -> StringName:
	var direction := Input.get_vector("move_left", "move_right", "move_forward",
		"move_backward")
	if Input.is_action_pressed("grab_left"):
		return TrickCatalog.grab_for(TrickCatalog.GrabSide.LEFT, direction)
	if Input.is_action_pressed("grab_right"):
		return TrickCatalog.grab_for(TrickCatalog.GrabSide.RIGHT, direction)
	return NO_GRAB


func _set_grab(side: StringName) -> void:
	if side == current_grab:
		return
	var previous := current_grab
	current_grab = side
	if previous != NO_GRAB:
		grab_ended.emit(previous)
	if side != NO_GRAB:
		grab_started.emit(side)


func _update_air_state(delta: float) -> void:
	var on_floor := is_on_floor()
	if _airborne:
		if on_floor:
			_land()
		else:
			air_time += delta
			air_peak_height = maxf(air_peak_height, global_position.y - _takeoff_height)
		return
	if on_floor:
		_leaving_floor = false
		return
	if not _leaving_floor:
		_leaving_floor = true
		_off_floor_time = 0.0
		_takeoff_height = global_position.y
	_off_floor_time += delta
	if _off_floor_time >= TAKEOFF_GRACE:
		_take_off()


## Commits the air phase that started [member _off_floor_time] seconds ago.
func _take_off() -> void:
	_airborne = true
	_leaving_floor = false
	_charging = false
	jump_charge = 0.0
	air_time = _off_floor_time
	air_peak_height = maxf(global_position.y - _takeoff_height, 0.0)
	air_turn = 0.0
	took_off.emit()


func _land() -> void:
	_airborne = false
	last_air_time = air_time
	air_time = 0.0
	var horizontal := _horizontal(velocity)
	var clean := _trick_landable()
	# Auto-align: the board lines up with the direction of travel, whatever it faced.
	if horizontal.length() >= ALIGN_MIN_SPEED:
		heading = horizontal.normalized()
	_forward_speed = horizontal.length()
	if not clean:
		_forward_speed *= bail_speed_factor
		current_trick = NO_TRICK
	_buffered_trick = NO_TRICK
	_trick_buffer_left = 0.0
	_set_grab(NO_GRAB)
	_window_action = &""
	# A spin left part way round turns back to forward on the ground (see _revert_spin).
	spin_yaw = wrapf(spin_yaw, -PI, PI)
	_spin_pending = 0.0
	var spin_id := TrickCatalog.spin_for_degrees(rad_to_deg(air_turn))
	air_turn = 0.0
	last_landing_clean = clean
	rig.play_landing(clean)
	_apply_ground_velocity()
	if clean and spin_id != NO_TRICK:
		spin_landed.emit(spin_id)
	landed.emit(clean)


## On the ground the rider's leftover spin turns back to face forward, easing out.
func _revert_spin(delta: float) -> void:
	if is_zero_approx(spin_yaw):
		return
	var step := revert_rate * delta * clampf(absf(spin_yaw) / 0.6 + 0.25, 0.25, 1.0)
	spin_yaw = move_toward(spin_yaw, 0.0, step)


## After an ability let go or pushed: roll on along whatever horizontal velocity it left.
func _adopt_velocity() -> void:
	var horizontal := _horizontal(velocity)
	if horizontal.length() > ADOPT_MIN_SPEED:
		heading = horizontal.normalized()
	_forward_speed = horizontal.length()


## While an ability drives: point the board where the body is going.
func _face_travel() -> void:
	var horizontal := _horizontal(velocity)
	if horizontal.length() > ADOPT_MIN_SPEED:
		heading = horizontal.normalized()


func _apply_ground_velocity() -> void:
	velocity.x = heading.x * _forward_speed
	velocity.z = heading.z * _forward_speed


func _update_rig() -> void:
	var lean := 0.0 if _airborne else _steer
	rig.set_lean(lean * clampf(_forward_speed / max_push_speed, 0.0, 1.0))
	rig.set_crouch(jump_charge if _charging else 0.0)
	rig.set_trick_chain(_repeat_coming())
	rig.set_trick(current_trick, trick_progress())
	rig.set_spin(spin_yaw)
	rig.set_airborne(_airborne)
	rig.set_cruising(_cruising and not _airborne)
	rig.set_grab(current_grab)
	rig.set_grind(grind_ability.grinding, grind_ability.balance)


func _refresh_abilities() -> void:
	_abilities.clear()
	for child in get_children():
		var ability := child as SkaterAbility
		if ability != null:
			ability.input_enabled = input_enabled
			_abilities.append(ability)
	apply_unlocks()


func _on_progress_level_changed(_level: int) -> void:
	apply_unlocks()


func _on_grind_ability_bailed() -> void:
	rig.play_landing(false)


static func _horizontal(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


## A flat, normalized copy of [param direction], or [param fallback] if it has no length.
static func _flat(direction: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx():
		return fallback
	return flat.normalized()
