extends Node
## Dev-only real-play bot: loads a real level scene the way the game does and plays it the
## way a person does, through real key, mouse button and mouse motion events
## ([method Input.parse_input_event]) only. Nothing on the skater is set directly.
##
## Run it through the harness (real rendering, real physics, invisible display):
## [codeblock]
## ./shoot.sh res://scenes/dev/play_bot.tscn <outdir> <frames> -- --scenario=<name> \
##     [--level=res://scenes/levels/level_1.tscn] [--launch=flat|ramp]
## [/codeblock]
## Scenarios: plain_ollie, ollie_turning, every flip and board trick by its id (kickflip,
## front_flip, front_kickflip, pop_shove_it, tre_flip... see [constant TRICK_KEYS]), every
## grab by its id (melon_grab, nosegrab, tailgrab... see [constant GRAB_KEYS]), spin, grind.
## [code]--launch=ramp[/code] takes off from the level's kicker.
## [br]Every skater, grind and score event is logged with the skater's state, to stdout and to
## [code]user://play_bot_<scenario>.log[/code]. The last line is
## [code]RESULT <scenario> PASS|FAIL <reasons>[/code].
## [br]Options: [code]--hold=w,a,d[/code] keys held through the run-up and jump (cruising,
## steering), [code]--order=q_first|dir_first[/code], [code]--trick-at=<s>[/code] after
## Space, [code]--jump-hold=<s>[/code] (spring jump), [code]--air-steer=a|d[/code],
## [code]--jumps=<n>[/code] in a row, [code]--approach=along|side|ground|far|over[/code] for
## the rail, [code]--counter=no[/code] (no balance input), [code]--hold-trick=yes[/code]
## (keep the trick keys held to the landing: hold-to-repeat), [code]--min-tricks=<n>[/code]
## (tricks the run must make), [code]--spin-input=mouse|keys[/code] (spin with Q + mouse or
## by holding A). For shots only: [code]--cam=side|front|game[/code] (a camera beside the
## rider) and [code]--slowmo=<time scale>[/code]. Scenario [code]look_up[/code]
## checks the camera can look up. Scenario [code]edge_grind[/code] grinds a sharp edge of the
## level art (no GrindRail): [code]--edge=cube[/code] ollies up beside the long cube beam and
## holds C onto its top edge, [code]--edge=ramp[/code] rolls up a ramp beside its side edge
## holding C and grinds up it to the lip. The matrix mounts the bot too (unit PlayBot),
## setting the same options as properties.
## [br]Levels get a fresh GameState with everything unlocked and a save path of the bot's
## own, so the player's save is never read into it nor written.

const GAME_STATE := preload("res://autoload/game_state.gd")
const DEFAULT_LEVEL := "res://scenes/levels/level_1.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const BOT_SAVE_PATH := "user://play_bot_save.cfg"
## Physical keys, as bound in project.godot.
const KEY_PUSH := KEY_SHIFT
const KEY_JUMP := KEY_SPACE
const KEY_TRICK := KEY_Q
const KEY_GRIND := KEY_C
const KEY_GRAB_LEFT := KEY_CTRL
const KEY_GRAB_RIGHT := KEY_ALT
## Steering stops correcting inside this angle (radians).
const STEER_DEADBAND := 0.06
## Seconds a scenario may take before it gives up.
const SCENARIO_TIMEOUT := 40.0
## Where each level's set pieces are (world space). Kicker approach runs start -> lip.
const SPOTS := {
	"res://scenes/levels/level_1.tscn": {
		"flat_start": Vector3(-2.0, 0.0, 50.0),
		"flat_run": Vector3(40.0, 0.0, 50.0),
		"kicker_start": Vector3(41.0, 0.0, 62.0),
		"kicker_lip": Vector3(41.0, 0.0, 86.0),
		"rail_start": Vector3(49.0, 0.0, 60.0),
		"rail_end": Vector3(49.0, 0.0, 90.0),
		# The long cube beam (art "Cube", top edges at y 3): a line 0.9 m beside its +x side
		# face, run towards its z 24 end. The jump spot is two thirds of the way along.
		"cube_start": Vector3(-77.75, 0.0, 100.68),
		"cube_jump": Vector3(-64.62, 0.0, 79.40),
		# Art "Ramp" (rises towards -z to its lip at z 63): 1.2 m inside its x -8.2 side edge.
		"ramp_start": Vector3(-6.97, 0.0, 104.0),
		"ramp_jump": Vector3(-6.97, 0.0, 86.0),
	},
	"res://scenes/main.tscn": {
		"flat_start": Vector3(0.0, 0.0, 10.0),
		"flat_run": Vector3(0.0, 0.0, 40.0),
		"kicker_start": Vector3(0.0, 0.0, 2.0),
		"kicker_lip": Vector3(0.0, 0.0, -22.0),
		"rail_start": Vector3(5.0, 0.0, 12.0),
		"rail_end": Vector3(5.0, 0.0, -18.0),
	},
}
const KEY_BOARD_TRICK := KEY_E
## Single-direction flips (Q + one key), played with the key order options.
const TRICK_KEYS := {
	"kickflip": KEY_A,
	"heelflip": KEY_D,
	"front_flip": KEY_W,
	"back_flip": KEY_S,
}
## Every other trick: the trick key and the direction keys pressed together.
const CHORD_TRICKS := {
	"front_kickflip": [KEY_Q, KEY_W, KEY_A],
	"front_heelflip": [KEY_Q, KEY_W, KEY_D],
	"back_kickflip": [KEY_Q, KEY_S, KEY_A],
	"back_heelflip": [KEY_Q, KEY_S, KEY_D],
	"pop_shove_it": [KEY_E],
	"fs_shove_it": [KEY_E, KEY_S],
	"shove_it_360": [KEY_E, KEY_W],
	"varial_kickflip": [KEY_E, KEY_A],
	"varial_heelflip": [KEY_E, KEY_D],
	"tre_flip": [KEY_E, KEY_W, KEY_A],
	"laser_flip": [KEY_E, KEY_W, KEY_D],
	"hardflip": [KEY_E, KEY_S, KEY_A],
	"inward_heelflip": [KEY_E, KEY_S, KEY_D],
}
## Grabs: the grab key, then an optional direction key held with it.
const GRAB_KEYS := {
	"melon_grab": [KEY_CTRL],
	"nosegrab": [KEY_CTRL, KEY_W],
	"method_grab": [KEY_CTRL, KEY_S],
	"mute_grab": [KEY_CTRL, KEY_A],
	"seatbelt_grab": [KEY_CTRL, KEY_D],
	"indy_grab": [KEY_ALT],
	"crail_grab": [KEY_ALT, KEY_W],
	"tailgrab": [KEY_ALT, KEY_S],
	"stalefish_grab": [KEY_ALT, KEY_A],
	"roast_beef_grab": [KEY_ALT, KEY_D],
}
## Mouse pixels per physics frame while spinning with Q + mouse.
const SPIN_MOUSE_STEP := 40.0

var scenario: String = "plain_ollie"
var level_path: String = DEFAULT_LEVEL
var launch: String = "flat"
## "place": the skater starts at the scenario's start spot (set once before any input, as a
## spawn does). "walk": it skates there from the level's own spawn.
var start_mode: String = "place"
## Keys a player keeps held through the run-up and the jump: "w" (cruising), "a" / "d"
## (steering). Comma separated.
var hold_keys: String = ""
## Trick key order: "q_first" (hold Q, tap the direction) or "dir_first" (hold the direction,
## tap Q).
var order: String = "q_first"
## Seconds after Space before the trick keys go down.
var trick_at: float = 0.12
## Seconds Space is held (longer = spring jump).
var jump_hold: float = 0.1
## "a" / "d": held from the jump to the landing (steering in the air).
var air_steer: String = ""
## Jumps in a row (each with the scenario's trick), for combo chaining.
var jumps: int = 1
## Grind run-up: "along" (from the rail's start), "side" (jump on from beside the rail's
## middle at an angle), "ground" (roll beside it on the ground holding C).
var approach: String = "along"
## Press A/D against the balance bar while grinding.
var counter_balance: bool = true
## Scenario edge_grind: which art edge, "cube" (the beam's top edge) or "ramp" (a side edge).
var edge: String = "cube"
## Seconds the edge grind is held before C is let go (rolls off clean).
var edge_hold: float = 3.0
## Keep the trick keys held until the landing (hold to repeat).
var hold_trick: bool = false
## Tricks the run must make (0: one per jump).
var min_tricks: int = 0
## Spin with "mouse" (Q + mouse) or "keys" (A held in the air).
var spin_input: String = "keys"
## Shots only: "side", "front" or "game" (the game's own camera).
var cam: String = "game"
## Shots only: engine time scale while the scenario runs (slow motion for frame grabs).
var slowmo: float = 1.0
## Spins landed (TrickCatalog spin ids) and the biggest one in degrees.
var spin_count: int:
	get:
		return _spins.size()
var best_spin_degrees: int = 0
## Average downward acceleration measured while airborne with no ability driving (m/s^2).
var air_gravity: float = 0.0
## Grabs started that were the scenario's own grab.
var grab_count: int:
	get:
		return _grabs.count(StringName(scenario))
## True when run as the main scene: the bot quits the game when its scenario ends.
var quit_when_done: bool = false
## Set when the scenario has been judged; [member problems] holds the reasons.
var finished: bool = false
var problems: PackedStringArray = []
## Read-outs for the matrix (PlayBot unit), valid once [member finished].
## How many reasons the judge found (0 = the run played as a player expects).
var problem_count: int:
	get:
		return problems.size()
## Times the scenario's own trick was performed.
var trick_count: int:
	get:
		return _tricks.count(StringName(scenario))
## Tricks performed that were not the one the keys asked for.
var wrong_trick_count: int:
	get:
		return _tricks.size() - trick_count
## Landings judged so far, and how many of them bailed.
var landing_count: int:
	get:
		return _landings.size()
var bail_count: int:
	get:
		return _landings.count(false)
## Grinds started.
var grind_count: int:
	get:
		return _count("grind_started")
## Grinds started on an edge of the level art (no GrindRail).
var edge_grind_count: int = 0
## Combos banked, how many of them clean, and their points in total.
var banked_count: int:
	get:
		return _banked.size()
var unclean_banked_count: int:
	get:
		return _banked_clean.count(false)
var banked_points: int:
	get:
		var total := 0
		for points in _banked:
			total += points
		return total
## Take-offs right after a grind ended that went up faster than the rail-end pop: a jump
## nobody pressed at that moment.
var surprise_hops: int = 0
## 3D render scale for the shots (llvmpipe renders slowly); physics is unaffected.
var render_scale: float = 0.35
## False until the controls are handed over: earlier events (the spawn drop) are not judged.
var _judging: bool = false
var level: Node = null
var skater: Skater = null
var score_keeper: ScoreKeeper = null
var progress: GAME_STATE = null

var _lines: PackedStringArray = []
var _held: Dictionary[Key, bool] = {}
var _time: float = 0.0
var _counts: Dictionary[String, int] = {}
var _landings: Array[bool] = []
var _tricks: Array[StringName] = []
var _spins: Array[StringName] = []
var _gravity_sum: float = 0.0
var _gravity_samples: int = 0
var _last_vy: float = NAN
var _shot_camera: Camera3D = null
var _grabs: Array[StringName] = []
var _banked: Array[int] = []
var _banked_clean: Array[bool] = []
var _grind_ends: Array[bool] = []
var _look_samples: Array[Dictionary] = []
var _grind_ended_at: float = -INF
var _jump_time: float = 0.0
## Skater state at the end of the previous physics frame (before this frame's landing).
var _before: Dictionary = {}


func _ready() -> void:
	set_meta("verify_unit", "PlayBot")
	# Run as the main scene (shoot.sh): options from the command line, quit when done.
	# Mounted by the matrix instead: options come from the fixture, the run never quits.
	quit_when_done = get_tree().current_scene == self
	if quit_when_done:
		_read_args()
		get_viewport().scaling_3d_scale = render_scale
	progress = GAME_STATE.new()
	progress.name = "PlayBotProgress"
	progress.save_path = BOT_SAVE_PATH
	progress.appearance_path = ""
	progress.unlock_all = true
	add_child(progress)
	var scene := load(level_path) as PackedScene
	if scene == null:
		_log("ERROR cannot load %s" % level_path)
		_finish(["no level"])
		return
	level = scene.instantiate()
	var controller := level as LevelController
	if controller != null:
		controller.game_state = progress
	add_child(level)
	skater = _find(level, func(n: Node) -> bool: return n is Skater) as Skater
	score_keeper = _find(level, func(n: Node) -> bool: return n is ScoreKeeper) as ScoreKeeper
	if skater == null:
		_log("ERROR no skater in %s" % level_path)
		_finish(["no skater"])
		return
	_connect_events()
	_log("START scenario=%s level=%s launch=%s spawn=%s heading=%s" % [scenario, level_path,
		launch, _v(skater.global_position), _v(skater.heading)])
	_run.call_deferred()


func _exit_tree() -> void:
	# Never leave a key held for whatever runs next (the matrix mounts units one by one).
	_release_all()


func _physics_process(delta: float) -> void:
	_time += delta
	if skater != null:
		_measure_gravity(delta)
		_before = _snapshot()
		if OS.get_environment("BOT_TRACE") != "":
			print("TRACE %.3f grind=%s vy=%.2f charging=%s floor=%s air=%s space=%s" % [_time,
				skater.grind_ability.grinding, skater.velocity.y, skater.get("_charging"),
				skater.is_on_floor(), skater.is_airborne(), Input.is_action_pressed("jump")])


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=")
		elif arg.begins_with("--launch="):
			launch = arg.trim_prefix("--launch=")
		elif arg.begins_with("--start="):
			start_mode = arg.trim_prefix("--start=")
		elif arg.begins_with("--render-scale="):
			render_scale = float(arg.trim_prefix("--render-scale="))
		elif arg.begins_with("--hold="):
			hold_keys = arg.trim_prefix("--hold=")
		elif arg.begins_with("--order="):
			order = arg.trim_prefix("--order=")
		elif arg.begins_with("--trick-at="):
			trick_at = float(arg.trim_prefix("--trick-at="))
		elif arg.begins_with("--jump-hold="):
			jump_hold = float(arg.trim_prefix("--jump-hold="))
		elif arg.begins_with("--air-steer="):
			air_steer = arg.trim_prefix("--air-steer=")
		elif arg.begins_with("--jumps="):
			jumps = int(arg.trim_prefix("--jumps="))
		elif arg.begins_with("--approach="):
			approach = arg.trim_prefix("--approach=")
		elif arg.begins_with("--counter="):
			counter_balance = arg.trim_prefix("--counter=") != "no"
		elif arg.begins_with("--edge="):
			edge = arg.trim_prefix("--edge=")
		elif arg.begins_with("--edge-hold="):
			edge_hold = float(arg.trim_prefix("--edge-hold="))
		elif arg.begins_with("--hold-trick="):
			hold_trick = arg.trim_prefix("--hold-trick=") == "yes"
		elif arg.begins_with("--min-tricks="):
			min_tricks = int(arg.trim_prefix("--min-tricks="))
		elif arg.begins_with("--spin-input="):
			spin_input = arg.trim_prefix("--spin-input=")
		elif arg.begins_with("--cam="):
			cam = arg.trim_prefix("--cam=")
		elif arg.begins_with("--slowmo="):
			slowmo = float(arg.trim_prefix("--slowmo="))


# --- input: real events only --------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	if bool(_held.get(code, false)) == pressed:
		return
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	# Modifier flags as a real keyboard reports them: the state of the other held keys.
	event.shift_pressed = bool(_held.get(KEY_SHIFT, false)) and code != KEY_SHIFT
	event.ctrl_pressed = bool(_held.get(KEY_CTRL, false)) and code != KEY_CTRL
	event.alt_pressed = bool(_held.get(KEY_ALT, false)) and code != KEY_ALT
	_held[code] = pressed
	Input.parse_input_event(event)


func _mouse_move(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	event.position = get_viewport().get_visible_rect().size * 0.5
	event.global_position = event.position
	Input.parse_input_event(event)


func _click() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = get_viewport().get_visible_rect().size * 0.5
		event.global_position = event.position
		Input.parse_input_event(event)


func _release_all() -> void:
	for code: Key in _held.keys():
		_key(code, false)


func _tap(code: Key, seconds: float = 0.08) -> void:
	_key(code, true)
	await _wait(seconds)
	_key(code, false)


func _wait(seconds: float) -> void:
	var end := _time + seconds
	while _time < end:
		await get_tree().physics_frame


func _until(condition: Callable, timeout: float) -> bool:
	var end := _time + timeout
	while _time < end:
		if bool(condition.call()):
			return true
		await get_tree().physics_frame
	return false


## Skates to [param target] with Shift pushes and A/D steering, like a player does.
## Holds speed near [param want_speed]. Returns true on arrival.
func _drive_to(target: Vector3, want_speed: float, radius: float = 2.0) -> bool:
	var end := _time + SCENARIO_TIMEOUT * 0.5
	while _time < end:
		var to := target - skater.global_position
		to.y = 0.0
		if to.length() < radius:
			_key(KEY_A, false)
			_key(KEY_D, false)
			return true
		_steer_toward(to.normalized())
		_key(KEY_PUSH, skater.speed < want_speed)
		await get_tree().physics_frame
	_key(KEY_A, false)
	_key(KEY_D, false)
	_key(KEY_PUSH, false)
	_log("WARN drive_to %s timed out at %s" % [_v(target), _v(skater.global_position)])
	return false


func _steer_toward(direction: Vector3) -> void:
	var angle := skater.heading.signed_angle_to(direction, Vector3.UP)
	_key(KEY_A, angle > STEER_DEADBAND)
	_key(KEY_D, angle < -STEER_DEADBAND)


## Waits for the level's opening dialogue to hand over the controls (Enter advances it).
func _wait_for_controls() -> void:
	var end := _time + SCENARIO_TIMEOUT
	while _time < end and not skater.input_enabled:
		await _tap(KEY_ENTER, 0.05)
		await _wait(0.3)


# --- scenarios ------------------------------------------------------------------------------

func _run() -> void:
	await _wait(0.5)
	await _wait_for_controls()
	_log("CONTROLS input_enabled=%s mouse_mode=%d" % [skater.input_enabled, Input.mouse_mode])
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_click()
		await _wait(0.1)
		_log("CLICK mouse_mode=%d" % Input.mouse_mode)
	var spots: Dictionary = SPOTS.get(level_path, {})
	if start_mode == "place":
		_place_at_start(spots)
		await _wait(0.4)
	_judging = true
	_add_shot_camera()
	if scenario == "grind":
		await _scenario_grind(spots)
	elif scenario == "look_up":
		await _scenario_look_up()
	elif scenario == "edge_grind":
		await _scenario_edge_grind(spots)
	else:
		await _approach_launch(spots)
		for i in jumps:
			await _scenario_air()
			if i < jumps - 1:
				# Straight back up, as a player chaining jumps does.
				await _wait(0.2)
	await _wait(1.2)
	_release_all()
	Engine.time_scale = 1.0
	_finish(_judge())


## Setup only (no input): stands the skater at the scenario's first spot facing the next,
## the way a level spawn does, so the run fits in the shot's time budget.
func _place_at_start(spots: Dictionary) -> void:
	var keys := ["flat_start", "flat_run"]
	if scenario == "grind":
		keys = ["rail_start", "rail_end"]
	elif scenario == "edge_grind":
		keys = [edge + "_start", edge + "_jump"]
	elif launch == "ramp":
		keys = ["kicker_start", "kicker_lip"]
	if not spots.has(keys[0]):
		return
	var from: Vector3 = spots[keys[0]]
	var to: Vector3 = spots[keys[1]]
	skater.global_position = from + Vector3.UP * 0.1
	skater.set_heading(to - from)
	skater.camera_rig.snap_behind(skater.global_position, skater.heading)
	_log("SETUP placed at %s heading %s" % [_v(from), _v(skater.heading)])


func _place(at: Vector3, facing: Vector3) -> void:
	skater.global_position = at + Vector3.UP * 0.1
	skater.set_heading(facing)
	skater.camera_rig.snap_behind(skater.global_position, skater.heading)
	_log("SETUP placed at %s heading %s" % [_v(at), _v(skater.heading)])


## Keys from [member hold_keys] ("w", "a", "d").
func _held_habit_keys() -> Array[Key]:
	var keys: Array[Key] = []
	for part: String in hold_keys.split(",", false):
		match part.strip_edges().to_lower():
			"w":
				keys.append(KEY_W)
			"a":
				keys.append(KEY_A)
			"d":
				keys.append(KEY_D)
			"s":
				keys.append(KEY_S)
	return keys


## Gets rolling towards a take-off: flat ground, or up the kicker.
func _approach_launch(spots: Dictionary) -> void:
	var habits := _held_habit_keys()
	if habits.has(KEY_W):
		_key(KEY_W, true)
	if launch == "ramp" and spots.has("kicker_start"):
		await _drive_to(spots["kicker_start"] as Vector3, 6.0, 3.0)
		await _drive_to(spots["kicker_lip"] as Vector3, 11.0, 2.5)
	else:
		if spots.has("flat_start"):
			await _drive_to(spots["flat_start"] as Vector3, 6.0, 3.0)
		# Line up and push hard on the flat for two seconds, like "push 2s, jump".
		var run_to: Vector3 = spots.get("flat_run",
			skater.global_position + skater.heading * 30.0)
		var end := _time + 2.0
		while _time < end:
			var to := run_to - skater.global_position
			to.y = 0.0
			_steer_toward(to.normalized())
			_key(KEY_PUSH, true)
			await get_tree().physics_frame
		_key(KEY_PUSH, false)
	if scenario != "ollie_turning":
		_key(KEY_A, false)
		_key(KEY_D, false)
	# Steering keys held into the jump, as players do.
	for code in habits:
		_key(code, true)
	_log("RUNUP done pos=%s speed=%.2f held=%s" % [_v(skater.global_position), skater.speed,
		_held_now()])


func _scenario_air() -> void:
	var turning := scenario == "ollie_turning"
	if turning:
		# Steering into the jump and orbiting the camera with the mouse, as players do.
		_key(KEY_D, true)
		for i in 10:
			_mouse_move(Vector2(25.0, -4.0))
			await get_tree().physics_frame
	var landings_before := _count("landed")
	_jump_time = _time
	# Shots only: slow motion from the jump to just after the landing.
	Engine.time_scale = slowmo
	if launch != "ramp" or skater.is_on_floor() or landings_before > 0:
		await _tap(KEY_JUMP, jump_hold)
	if air_steer == "a":
		_key(KEY_A, true)
	elif air_steer == "d":
		_key(KEY_D, true)
	if TRICK_KEYS.has(scenario):
		await _wait(maxf(trick_at - jump_hold, 0.0))
		var direction: Key = TRICK_KEYS[scenario]
		_log("TRICK KEYS order=%s dir=%s held=%s airborne=%s air_time=%.2f" % [order,
			OS.get_keycode_string(direction), _held_now(), skater.is_airborne(), skater.air_time])
		if hold_trick:
			# Q and the direction held down until the landing: the trick repeats.
			_key(KEY_TRICK, true)
			_key(direction, true)
			await _until(func() -> bool: return _count("landed") > landings_before, 6.0)
			_key(KEY_TRICK, false)
			if not _held_habit_keys().has(direction):
				_key(direction, false)
		elif order == "dir_first":
			# A direction held, then Q tapped a moment later.
			_key(direction, false)
			await get_tree().physics_frame
			_key(direction, true)
			await _wait(0.05)
			await _tap(KEY_TRICK, 0.1)
			await _wait(0.1)
			if not _held_habit_keys().has(direction) and air_steer != OS.get_keycode_string(
					direction).to_lower():
				_key(direction, false)
		else:
			# Q held, then a direction tapped a moment later.
			_key(KEY_TRICK, true)
			await _wait(0.05)
			var was_held := bool(_held.get(direction, false))
			_key(direction, false)
			await get_tree().physics_frame
			await _tap(direction, 0.15)
			if was_held:
				_key(direction, true)
			_key(KEY_TRICK, false)
	elif CHORD_TRICKS.has(scenario):
		await _wait(maxf(trick_at - jump_hold, 0.0))
		var keys: Array = CHORD_TRICKS[scenario]
		_log("TRICK KEYS %s hold=%s airborne=%s air_time=%.2f" % [_names(keys), hold_trick,
			skater.is_airborne(), skater.air_time])
		for code: Key in keys:
			_key(code, true)
		if hold_trick:
			await _until(func() -> bool: return _count("landed") > landings_before, 6.0)
		else:
			await _wait(0.15)
		for code: Key in keys:
			_key(code, false)
	elif GRAB_KEYS.has(scenario):
		await _wait(0.15)
		var keys: Array = GRAB_KEYS[scenario]
		_log("GRAB KEYS %s" % _names(keys))
		for code: Key in keys:
			_key(code, true)
		await _wait(0.45)
		for code: Key in keys:
			_key(code, false)
	elif scenario == "spin":
		await _wait(0.1)
		_log("SPIN input=%s mouse_mode=%d" % [spin_input, Input.mouse_mode])
		if spin_input == "mouse":
			_key(KEY_TRICK, true)
			while _count("landed") == landings_before and _time < _jump_time + 6.0:
				_mouse_move(Vector2(-SPIN_MOUSE_STEP, 0.0))
				await get_tree().physics_frame
			_key(KEY_TRICK, false)
		else:
			_key(KEY_A, true)
			await _until(func() -> bool: return _count("landed") > landings_before, 6.0)
			_key(KEY_A, false)
	elif turning:
		for i in 12:
			_mouse_move(Vector2(-20.0, 3.0))
			await get_tree().physics_frame
	await _until(func() -> bool: return _count("landed") > landings_before, 4.0)
	if not is_equal_approx(slowmo, 1.0):
		# Shots only: keep the landing in slow motion too.
		await _wait(0.3)
		Engine.time_scale = 1.0
	if jumps == 1:
		await _settle()
	if turning:
		_key(KEY_D, false)
	if air_steer != "":
		_key(KEY_A, false)
		_key(KEY_D, false)


## Pushes the mouse up as far as it goes, standing and rolling, and checks the camera
## stays above the floor and off the skater while looking up.
func _scenario_look_up() -> void:
	for i in 40:
		_mouse_move(Vector2(0.0, -30.0))
		await get_tree().physics_frame
	for rolling: bool in [false, true]:
		_key(KEY_PUSH, rolling)
		await _wait(0.8)
		var cam := skater.camera
		var pitch := skater.camera_rig.spring_arm.rotation.x
		var floor_y := skater.global_position.y
		var to_pivot := cam.global_position.distance_to(skater.camera_rig.global_position)
		var clearance := _crosshair_clearance(cam)
		_look_samples.append({"pitch": pitch, "cam_above_floor": cam.global_position.y - floor_y,
			"arm": to_pivot, "looks_up": -cam.global_basis.z.y, "clearance": clearance})
		_log("LOOK rolling=%s pitch=%.2f cam_above_floor=%.2f arm=%.2f view_up=%.2f "
			% [rolling, pitch, cam.global_position.y - floor_y, to_pivot,
			-cam.global_basis.z.y] + "crosshair_clearance=%.2f" % clearance)
	_key(KEY_PUSH, false)


## Closest the screen-centre ray passes to the rider's body (feet to head, 1.8 m), in m.
func _crosshair_clearance(cam: Camera3D) -> float:
	var forward := -cam.global_basis.z.normalized()
	var best := INF
	for i in 10:
		var point := skater.global_position + Vector3.UP * (0.2 + 0.18 * i)
		var along := maxf((point - cam.global_position).dot(forward), 0.0)
		best = minf(best, point.distance_to(cam.global_position + forward * along))
	return best


func _held_now() -> String:
	var names: PackedStringArray = []
	for code: Key in _held.keys():
		if bool(_held[code]):
			names.append(OS.get_keycode_string(code))
	return ",".join(names)


func _scenario_grind(spots: Dictionary) -> void:
	if not spots.has("rail_start"):
		_log("ERROR no rail known in %s" % level_path)
		return
	var rail := _nearest_rail(spots["rail_start"] as Vector3)
	if rail == null:
		_log("ERROR no GrindRail node in %s" % level_path)
		return
	_log("RAIL %s from %s to %s length=%.1f approach=%s" % [rail.name,
		_v(rail.position_at(0.0)), _v(rail.position_at(rail.length())), rail.length(),
		approach])
	var start := rail.position_at(0.0)
	var along := rail.tangent_at(0.0)
	var side := along.cross(Vector3.UP).normalized()
	var mid := rail.position_at(rail.length() * 0.5)
	mid.y = 0.0
	if approach == "over":
		# Setup only: stand 14 m out to the side of the rail's middle, facing it.
		_place(mid + side * 14.0, -side)
		await _wait(0.4)
	elif approach == "far":
		_place(Vector3(start.x, 0.0, start.z) + side * 2.2 - along * 10.0, along)
		await _wait(0.4)
	else:
		await _drive_to(spots["rail_start"] as Vector3, 6.0, 2.0)
	# Where the jump (or the C press, on the ground) happens, and which way to roll there.
	var jump_at := start - along * 1.5
	var aim_along := along
	if approach == "side":
		# Angle in at ~30 degrees towards the rail's first third, jumping 1.2 m beside it.
		jump_at = rail.position_at(rail.length() * 0.3) + side * 1.2
		aim_along = (along - side * 0.6).normalized()
	elif approach == "ground":
		jump_at = start + side * 0.8
	elif approach == "far":
		# Rolling parallel 2.2 m beside the rail (eyeballing a thin rail from behind).
		jump_at = rail.position_at(rail.length() * 0.4) + side * 2.2
	elif approach == "over":
		# Square on towards the rail's middle, jumping 1.6 m short of it to cross over it.
		jump_at = rail.position_at(rail.length() * 0.5) + side * 1.6
		aim_along = -side
	jump_at.y = 0.0
	var end := _time + 10.0
	var lined_up := false
	while _time < end:
		var to := jump_at - skater.global_position
		to.y = 0.0
		if to.dot(aim_along) <= 0.0:
			break
		var aim := (to + aim_along * 2.0).normalized()
		if approach == "side" and not lined_up and to.length() > 6.0:
			aim = to.normalized()
		else:
			lined_up = true
		_steer_toward(aim)
		_key(KEY_PUSH, skater.speed < 8.0)
		await get_tree().physics_frame
	_key(KEY_A, false)
	_key(KEY_D, false)
	_key(KEY_PUSH, false)
	_log("APPROACH pos=%s heading=%s speed=%.2f dist_to_rail=%.2f" % [
		_v(skater.global_position), _v(skater.heading), skater.speed,
		rail.distance_to(skater.global_position)])
	if approach not in ["ground", "far"]:
		await _tap(KEY_JUMP, jump_hold)
	_key(KEY_GRIND, true)
	var started := await _until(func() -> bool: return _count("grind_started") > 0, 2.5)
	if started:
		var grind := skater.grind_ability
		var until_end := _time + 8.0
		while _time < until_end and _count("grind_ended") == 0:
			if counter_balance:
				# Lean against the bar: A when it tips right, D when it tips left.
				_key(KEY_A, grind.balance > 0.1)
				_key(KEY_D, grind.balance < -0.1)
			await get_tree().physics_frame
		_key(KEY_A, false)
		_key(KEY_D, false)
	_key(KEY_GRIND, false)
	await _settle()


## Rolls along the line from the edge's start spot to its jump spot (pushing to about 8 m/s),
## then: "cube" ollies at the jump spot and holds C, "ramp" holds C from the jump spot on
## (already rolling up the ramp beside its side edge). Rides the edge, countering the
## balance with A/D, for [member edge_hold] seconds and lets go of C.
func _scenario_edge_grind(spots: Dictionary) -> void:
	if not spots.has(edge + "_start"):
		_log("ERROR no %s edge known in %s" % [edge, level_path])
		return
	await _finish_dialogue()
	var from: Vector3 = spots[edge + "_start"]
	var jump_at: Vector3 = spots[edge + "_jump"]
	var along := Vector3(jump_at.x - from.x, 0.0, jump_at.z - from.z).normalized()
	var end := _time + 12.0
	while _time < end:
		var to := jump_at - skater.global_position
		to.y = 0.0
		if to.dot(along) <= 0.0:
			break
		# Hold the line: aim a little ahead along it, back onto it if drifted off.
		var off_line := to - along * to.dot(along)
		_steer_toward((along * 4.0 + off_line).normalized())
		_key(KEY_PUSH, skater.speed < 8.0)
		await get_tree().physics_frame
	_key(KEY_A, false)
	_key(KEY_D, false)
	_key(KEY_PUSH, false)
	_log("APPROACH edge=%s pos=%s heading=%s speed=%.2f" % [edge, _v(skater.global_position),
		_v(skater.heading), skater.speed])
	if edge == "cube":
		await _tap(KEY_JUMP, jump_hold)
	_key(KEY_GRIND, true)
	var started := await _until(func() -> bool: return _count("grind_started") > 0, 2.5)
	if started:
		var grind := skater.grind_ability
		_log("EDGE %s from %s to %s length=%.1f loop=%s" % [grind.track.label(),
			_v(grind.track.position_at(0.0)), _v(grind.track.position_at(grind.track.length())),
			grind.track.length(), grind.track.is_loop()])
		var until_end := _time + edge_hold
		var next_sample := _time
		var riding_velocity := skater.velocity
		while _time < until_end and _count("grind_ended") == 0:
			riding_velocity = skater.velocity
			if counter_balance:
				# Lean against the needle: A when it tips right, D when it tips left.
				_key(KEY_A, grind.balance > 0.1)
				_key(KEY_D, grind.balance < -0.1)
			if _time >= next_sample:
				next_sample = _time + 0.5
				_log("RIDE pos=%s balance=%.2f on_edge=%s" % [_v(skater.global_position),
					grind.balance, grind.on_edge])
			await get_tree().physics_frame
		_key(KEY_A, false)
		_key(KEY_D, false)
		await _credit_edge_launch(riding_velocity.y + grind.end_pop_speed)
	_key(KEY_GRIND, false)
	await _settle()


## Leaving the top of an edge that climbs carries its climb: a take-off right after the
## grind going up no faster than [param allowed] (the edge's own climb plus the end pop) is
## the edge launching the rider, not a jump nobody pressed.
func _credit_edge_launch(allowed: float) -> void:
	var take_offs := _count("took_off")
	var end := _time + 0.3
	while _time < end and _count("took_off") == take_offs:
		await get_tree().physics_frame
	if _count("took_off") > take_offs and surprise_hops > 0 \
			and skater.velocity.y <= allowed + 0.05:
		surprise_hops -= 1
		_log("EDGE LAUNCH vel_y=%.2f within climb + pop %.2f" % [skater.velocity.y, allowed])


## Reads through the level's opening dialogue with Enter, as a player does, until the HUD
## (hidden while the dialogue plays) is back on screen.
func _finish_dialogue() -> void:
	var controller := level as LevelController
	if controller == null or controller.hud == null:
		return
	var end := _time + SCENARIO_TIMEOUT * 0.5
	while _time < end and not controller.hud.visible:
		await _tap(KEY_ENTER, 0.05)
		await _wait(0.15)
	_log("DIALOGUE done hud_visible=%s" % controller.hud.visible)


## Waits until the skater has been rolling on the floor for a moment (past any take-off
## grace), so a hop off the rail end is landed before judging.
func _settle() -> void:
	var grounded_for := 0.0
	var end := _time + 4.0
	while _time < end and grounded_for < 0.3:
		await get_tree().physics_frame
		grounded_for = grounded_for + 1.0 / 60.0 if skater.is_on_floor() else 0.0


func _nearest_rail(near: Vector3) -> GrindRail:
	var best: GrindRail = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(GrindRail.GROUP):
		var rail := node as GrindRail
		if rail == null:
			continue
		var distance := rail.distance_to(near)
		if distance < best_distance:
			best = rail
			best_distance = distance
	return best


# --- judging --------------------------------------------------------------------------------

func _judge() -> PackedStringArray:
	var found: PackedStringArray = []
	if scenario == "look_up":
		for sample in _look_samples:
			if float(sample["looks_up"]) < 0.7:
				found.append("camera can't look up (view up %.2f)" % float(sample["looks_up"]))
			if float(sample["cam_above_floor"]) < -0.01:
				found.append("camera under the floor")
			if float(sample["clearance"]) < 0.35:
				found.append("rider covers the crosshair (%.2f m)" % float(sample["clearance"]))
		return found
	if scenario == "edge_grind":
		if edge_grind_count == 0:
			found.append("no grind started on an edge of the art")
		elif _grind_ends.is_empty() or not _grind_ends[0]:
			found.append("edge grind did not end clean")
		if _banked.is_empty():
			found.append("edge grind scored nothing")
	elif scenario == "grind":
		if _count("grind_started") == 0:
			found.append("no grind started")
		elif _grind_ends.is_empty() or not _grind_ends[0]:
			found.append("grind did not end clean")
		if _banked.is_empty():
			found.append("grind scored nothing")
	else:
		if _count("took_off") == 0:
			found.append("never took off")
		var is_trick := TRICK_KEYS.has(scenario) or CHORD_TRICKS.has(scenario)
		var wanted := maxi(jumps, min_tricks)
		if is_trick and trick_count < wanted:
			found.append("trick %s not performed %d times (got %s)" % [scenario, wanted,
				_tricks])
		if GRAB_KEYS.has(scenario) and grab_count == 0:
			found.append("no %s (grabs %s)" % [scenario, _grabs])
		if scenario == "spin" and spin_count == 0:
			found.append("no spin landed")
		if (is_trick or GRAB_KEYS.has(scenario) or scenario == "spin") and _banked.is_empty():
			found.append("scored nothing")
	if _landings.is_empty():
		found.append("never landed")
	elif _landings.has(false):
		found.append("bailed: landings %s" % [_landings])
	if _banked_clean.has(false):
		found.append("combo failed")
	if surprise_hops > 0:
		found.append("%d jump(s) nobody pressed after the rail" % surprise_hops)
	return found


func _finish(found: PackedStringArray) -> void:
	problems = found
	finished = true
	var verdict := "PASS" if problems.is_empty() else "FAIL " + "; ".join(problems)
	_log("RESULT %s %s %s" % [scenario, launch, verdict])
	var file := FileAccess.open("user://play_bot_%s.log" % scenario, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	if quit_when_done:
		get_tree().quit.call_deferred()


# --- event log ------------------------------------------------------------------------------

func _connect_events() -> void:
	skater.took_off.connect(_on_skater_took_off)
	skater.landed.connect(_on_skater_landed)
	skater.trick_performed.connect(_on_skater_trick_performed)
	if skater.has_signal(&"spin_landed"):
		skater.connect(&"spin_landed", _on_skater_spin_landed)
	skater.grab_started.connect(_on_skater_grab_started)
	skater.grab_ended.connect(_on_skater_grab_ended)
	skater.grind_ability.grind_started.connect(_on_grind_started)
	skater.grind_ability.grind_ended.connect(_on_grind_ended)
	skater.grind_ability.bailed.connect(_on_grind_bailed)
	if score_keeper != null:
		score_keeper.combo_banked.connect(_on_combo_banked)


func _snapshot() -> Dictionary:
	var horizontal := Vector3(skater.velocity.x, 0.0, skater.velocity.z)
	var angle := 0.0
	if horizontal.length() > 0.01:
		angle = rad_to_deg(skater.heading.angle_to(horizontal))
	return {
		"pos": _v(skater.global_position),
		"heading_vs_velocity_deg": snappedf(angle, 0.1),
		"speed": snappedf(skater.speed, 0.01),
		"trick": skater.current_trick,
		"trick_progress": snappedf(skater.trick_progress(), 0.01),
		"board_up": _v(skater.rig.board.global_basis.y.normalized()),
		"anim": skater.rig.anim_state,
		"on_floor": skater.is_on_floor(),
		"floor_normal": _v(skater.get_floor_normal()),
		"airborne": skater.is_airborne(),
	}


func _count(event_name: String) -> int:
	return int(_counts.get(event_name, 0))


func _event(event_name: String, detail: String) -> void:
	if not _judging:
		_log("PRE %s %s" % [event_name, detail])
		return
	_counts[event_name] = _count(event_name) + 1
	_log("EVENT %s %s" % [event_name, detail])


func _log(line: String) -> void:
	var stamped := "[play_bot %6.2fs f%d] %s" % [_time, Engine.get_frames_drawn(), line]
	_lines.append(stamped)
	print(stamped)


func _on_skater_took_off() -> void:
	var since_grind := _time - _grind_ended_at
	if _judging and since_grind < 0.3 and skater.velocity.y > skater.grind_ability.end_pop_speed:
		surprise_hops += 1
	_event("took_off", "pos=%s speed=%.2f vel_y=%.2f" % [_v(skater.global_position),
		skater.speed, skater.velocity.y])


func _on_skater_landed(clean: bool) -> void:
	if _judging:
		_landings.append(clean)
	_event("landed", "clean=%s air=%.2fs now=%s before=%s" % [clean, skater.last_air_time,
		_snapshot(), _before])


func _on_skater_trick_performed(trick_id: StringName) -> void:
	if _judging:
		_tricks.append(trick_id)
	_event("trick_performed", "%s air_time=%.2f" % [trick_id, skater.air_time])


func _on_skater_spin_landed(spin_id: StringName) -> void:
	if _judging:
		_spins.append(spin_id)
		var degrees := int(String(spin_id).get_slice("_", 1))
		best_spin_degrees = maxi(best_spin_degrees, degrees)
	_event("spin_landed", String(spin_id))


func _on_skater_grab_started(grab_id: StringName) -> void:
	_grabs.append(grab_id)
	_event("grab_started", String(grab_id))


func _on_skater_grab_ended(grab_id: StringName) -> void:
	_event("grab_ended", String(grab_id))


func _on_grind_started(rail: GrindRail) -> void:
	var what := String(rail.name) if rail != null else skater.grind_ability.track.label()
	if rail == null and _judging:
		edge_grind_count += 1
	_event("grind_started", "%s at %s" % [what, _v(skater.global_position)])


func _on_grind_ended(clean: bool) -> void:
	_grind_ended_at = _time
	if _judging:
		_grind_ends.append(clean)
	_event("grind_ended", "clean=%s at %s" % [clean, _v(skater.global_position)])


func _on_grind_bailed() -> void:
	_event("grind_bailed", "balance bar tipped")


func _on_combo_banked(points: int, clean: bool) -> void:
	if _judging:
		_banked.append(points)
		_banked_clean.append(clean)
	_event("combo_banked", "points=%d clean=%s score=%d" % [points, clean, score_keeper.score])


## Downward acceleration while airborne on the skater's own movement: the change in
## vertical speed per second between two airborne frames with no ability driving.
func _measure_gravity(delta: float) -> void:
	var free_fall := _judging and skater.is_airborne() and not skater.is_on_floor()
	for ability: Node in [skater.grapple_ability, skater.rocket_boost, skater.shift_phase,
			skater.grind_ability]:
		var driving := ability as SkaterAbility
		if driving != null and driving.enabled and driving.is_controlling_movement():
			free_fall = false
	if free_fall and not is_nan(_last_vy) and delta > 0.0:
		_gravity_sum += (_last_vy - skater.velocity.y) / delta
		_gravity_samples += 1
		air_gravity = _gravity_sum / _gravity_samples
	_last_vy = skater.velocity.y if free_fall else NAN


## Shots only: a camera beside or in front of the rider, so tricks read side-on.
func _add_shot_camera() -> void:
	if cam == "game" or not quit_when_done:
		return
	_shot_camera = Camera3D.new()
	_shot_camera.fov = 50.0
	add_child(_shot_camera)
	_shot_camera.current = true
	_place_shot_camera()


func _process(_delta: float) -> void:
	if _shot_camera != null and skater != null:
		_place_shot_camera()


func _place_shot_camera() -> void:
	var side := skater.heading.cross(Vector3.UP).normalized()
	var offset := side * 3.6 + Vector3.UP * 0.9
	if cam == "front":
		offset = skater.heading * 3.6 + side * 1.2 + Vector3.UP * 0.9
	elif cam == "back":
		offset = -skater.heading * 3.6 + Vector3.UP * 1.3
	var focus := skater.global_position + Vector3.UP * 0.9
	_shot_camera.global_position = focus + offset
	_shot_camera.look_at(focus)


static func _names(keys: Array) -> String:
	var names: PackedStringArray = []
	for code: Key in keys:
		names.append(OS.get_keycode_string(code))
	return "+".join(names)


static func _find(node: Node, matches: Callable) -> Node:
	for child: Node in node.get_children():
		if bool(matches.call(child)):
			return child
		var found := _find(child, matches)
		if found != null:
			return found
	return null


static func _v(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
