extends Node
## Dev-only grapple play bot: plays the grapple hooks the way a person does, through real
## mouse button events (and real mouse motion to aim, whenever the mouse is captured) via
## [method Input.parse_input_event] only. Nothing on the grapple is set directly.
##
## Run it through the harness (real rendering, real physics, invisible display):
## [codeblock]
## ./shoot.sh res://scenes/dev/grapple_bot.tscn <outdir> <frames> -- --scenario=zip|chain
## [/codeblock]
## Scenarios:
## [br]- [code]zip[/code]: the real test level (res://scenes/main.tscn, its own progress
##   unlocks the grapple). The skater stands 38 m in front of the two towers; the bot aims at
##   the left tower and clicks and holds the left button, then aims at the right tower and
##   holds the right button too: an Attack on Titan zip through the gap between them. It
##   lets go of both [member zip_hold] seconds after the second hook sticks.
## [br]- [code]lift[/code]: the same level and spot; the bot aims high up the left tower
##   and holds only the left button for [member lift_hold] seconds: the lone hook reels the
##   skater off the ground and up towards the anchor.
## [br]- [code]chain[/code]: Spider-Man slings under a long high canopy (a course the bot
##   builds round the real skater.tscn: a floor, a 30 m high start deck and a canopy whose
##   underside is 60 m up). The bot holds Shift and W to roll off the deck; each time it is
##   falling it aims [member aim_up_degrees] up ahead at the canopy, holds a button
##   (left, right, left...), lets go on the upswing once the line is
##   [member release_degrees] past straight down, and does [member swings] swings in a row.
## [br]Read-outs for the matrix (unit GrappleFeel) are valid once [member finished]. Every
## hook event is logged to stdout with the skater's speed; the last line is
## [code]RESULT <scenario> DONE[/code].
## [br]Aiming: with the mouse captured (a real window, e.g. shoot.sh) the bot moves the
## mouse; headless there is no capture, so it hands the same pixel motion to the camera rig's
## own mouse handler ([method SkaterCamera.look_mouse]).

const GAME_STATE := preload("res://autoload/game_state.gd")
const SKATER_SCENE := preload("res://scenes/player/skater.tscn")
const MAIN_SCENE := "res://scenes/main.tscn"
const BOT_SAVE_PATH := "user://grapple_bot_save.cfg"
## Zip: where the skater stands and the tower faces it aims at (main.tscn: towers at x +-10,
## z -30, 2 m wide, 20 m tall).
const ZIP_START := Vector3(0.0, 0.0, 8.0)
const LEFT_TOWER_SPOT := Vector3(-9.6, 13.0, -29.0)
const RIGHT_TOWER_SPOT := Vector3(9.6, 13.0, -29.0)
const LIFT_SPOT := Vector3(-9.6, 17.0, -29.0)
## Chain course: the deck the skater rolls off and the canopy it swings under.
const DECK_TOP := 30.0
const DECK_SIZE := Vector3(20.0, 30.0, 24.0)
const DECK_CENTRE := Vector3(0.0, 15.0, 12.0)
const CHAIN_START := Vector3(0.0, 30.0, 20.0)
const CANOPY_UNDERSIDE := 60.0
const CANOPY_SIZE := Vector3(80.0, 2.0, 1200.0)
const CANOPY_CENTRE := Vector3(0.0, 61.0, -590.0)
const FLOOR_SIZE := Vector3(400.0, 1.0, 1600.0)
const FLOOR_CENTRE := Vector3(0.0, -0.5, -560.0)
## Frames after the closest pass at which the zip's kept speed is read.
const AFTER_PASS_FRAMES := 20
## Aiming: radians of error that count as on target, and frames it may take.
const AIM_TOLERANCE := 0.01
const AIM_FRAMES := 12
const SCENARIO_TIMEOUT := 30.0
const BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]

var scenario: String = "zip"
## False: the bot never clicks (the lie-catcher run).
var fire: bool = true
## Zip: seconds both buttons stay held after the second hook sticks.
var zip_hold: float = 2.0
## Lift: seconds the lone left hook is held.
var lift_hold: float = 1.2
## Chain: swings in a row, aim pitch above level, and release angle past straight down.
var swings: int = 3
var aim_up_degrees: float = 50.0
var release_degrees: float = 25.0
## Chain: seconds of falling after a release (or rolling off) before the next hook.
var fall_before_hook: float = 0.25
## 3D render scale for shots (llvmpipe renders slowly); physics is unaffected.
var render_scale: float = 0.35
var quit_when_done: bool = false
var finished: bool = false
var level: Node = null
var skater: Skater = null
var grapple: GrappleAbility = null
var progress: GAME_STATE = null

## Zip read-outs: seconds from both hooks stuck to 30 m/s (-1 if never), the fastest speed,
## the closest pass to the anchors' midpoint, the speed there and the share of it kept
## [constant AFTER_PASS_FRAMES] frames later, and the share of the speed kept 10 frames after
## both buttons were let go.
var zip_time_to_30: float = -1.0
var zip_peak_speed: float = 0.0
var pass_distance: float = INF
var pass_speed: float = 0.0
var after_pass_ratio: float = 0.0
var release_keep_ratio: float = 0.0
## Lift read-outs: height gained and metres closer to the anchor 1 s after the hook stuck,
## and physics frames on the floor after the skater first left it while the button was held.
var lift_rise: float = 0.0
var lift_closer: float = 0.0
var lift_floor_frames: int = 0
## Hooks that let go while their button was still held (the game unhooking on its own).
var unasked_releases: int = 0
## Chain read-outs: per swing, the speed when the hook stuck, the fastest speed during the
## swing and the speed when the bot let go.
var hook_speeds: PackedFloat32Array = []
var swing_peaks: PackedFloat32Array = []
var release_speeds: PackedFloat32Array = []
var swing_count: int:
	get:
		return release_speeds.size()
## How many swings ended faster than the one before (2 for three swings rising).
var rising_swings: int:
	get:
		var rises := 0
		for i in range(1, release_speeds.size()):
			if release_speeds[i] > release_speeds[i - 1] and swing_peaks[i] > swing_peaks[i - 1]:
				rises += 1
		return rises
## Last release speed over the speed the skater had when it rolled off the deck.
var chain_gain: float = 0.0

var _time: float = 0.0
var _held: Array[bool] = [false, false]
var _both_since: float = -1.0
var _since_pass: int = -1
var _launch_speed: float = 0.0


func _ready() -> void:
	set_meta("verify_unit", "GrappleFeel")
	quit_when_done = get_tree().current_scene == self
	if quit_when_done:
		_read_args()
		get_viewport().scaling_3d_scale = render_scale
	# Built once the matrix has set the fixture's props (they land after _ready).
	_start.call_deferred()


func _start() -> void:
	if scenario == "chain":
		_build_course()
	else:
		var scene := load(MAIN_SCENE) as PackedScene
		level = scene.instantiate()
		add_child(level)
		skater = _find_skater(level)
	grapple = skater.grapple_ability
	grapple.hook_attached.connect(_on_grapple_hook_attached)
	grapple.hook_released.connect(_on_grapple_hook_released)
	_log("START scenario=%s grapple_enabled=%s" % [scenario, grapple.enabled])
	_run()


func _exit_tree() -> void:
	for side: int in BUTTONS.size():
		_button(side, false)


func _physics_process(delta: float) -> void:
	_time += delta
	if skater == null:
		return
	var speed := skater.velocity.length()
	if grapple.left_attached and grapple.right_attached:
		_track_zip(speed)
	elif _since_pass >= 0:
		_since_pass += 1
	if _since_pass == AFTER_PASS_FRAMES and pass_speed > 0.0:
		after_pass_ratio = speed / pass_speed


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--swings="):
			swings = int(arg.trim_prefix("--swings="))
		elif arg.begins_with("--aim-up="):
			aim_up_degrees = float(arg.trim_prefix("--aim-up="))
		elif arg.begins_with("--release="):
			release_degrees = float(arg.trim_prefix("--release="))
		elif arg.begins_with("--render-scale="):
			render_scale = float(arg.trim_prefix("--render-scale="))


# --- input: real events only --------------------------------------------------------------

func _button(side: int, pressed: bool) -> void:
	if _held[side] == pressed:
		return
	_held[side] = pressed
	var event := InputEventMouseButton.new()
	event.button_index = BUTTONS[side]
	event.pressed = pressed
	event.button_mask = 0
	for other: int in BUTTONS.size():
		if _held[other]:
			event.button_mask |= 1 << (BUTTONS[other] - 1)
	event.position = get_viewport().get_visible_rect().size * 0.5
	event.global_position = event.position
	Input.parse_input_event(event)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


## Turns the view until the crosshair looks at [param target], as a player moving the mouse.
func _aim_at(target: Vector3) -> void:
	var rig := skater.camera_rig
	var sensitivity := rig.mouse_sensitivity * rig.sensitivity_scale
	for i in AIM_FRAMES:
		var cam := skater.camera
		var want := (target - cam.global_position).normalized()
		var have := -cam.global_basis.z.normalized()
		var yaw_error := wrapf(atan2(-want.x, -want.z) - atan2(-have.x, -have.z), -PI, PI)
		var pitch_error := asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(have.y, -1.0, 1.0))
		if absf(yaw_error) < AIM_TOLERANCE and absf(pitch_error) < AIM_TOLERANCE:
			return
		var relative := Vector2(-yaw_error, -pitch_error) / maxf(sensitivity, 0.00001)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := InputEventMouseMotion.new()
			motion.relative = relative
			motion.screen_relative = relative
			motion.position = get_viewport().get_visible_rect().size * 0.5
			motion.global_position = motion.position
			Input.parse_input_event(motion)
		else:
			rig.look_mouse(relative)
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	var end := _time + seconds
	while _time < end:
		await get_tree().physics_frame


# --- scenarios ------------------------------------------------------------------------------

func _run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _wait(0.5)
	if scenario == "chain":
		await _scenario_chain()
	elif scenario == "lift":
		await _scenario_lift()
	else:
		await _scenario_zip()
	for side: int in BUTTONS.size():
		_button(side, false)
	_finish()


func _scenario_zip() -> void:
	_place(ZIP_START, Vector3.FORWARD)
	await _wait(0.4)
	await _aim_at(LEFT_TOWER_SPOT)
	if fire:
		_button(0, true)
	await _wait(0.05)
	await _aim_at(RIGHT_TOWER_SPOT)
	if fire:
		_button(1, true)
	for i in 4:
		await get_tree().physics_frame
	_log("ZIP right held=%s hookable=%s at %.1f m, cam forward %s" % [
		Input.is_action_pressed("grapple_right"), grapple.target_hookable,
		grapple.target_distance, -skater.camera.global_basis.z])
	var end := _time + SCENARIO_TIMEOUT
	while _time < end and _both_since < 0.0 and fire:
		await get_tree().physics_frame
	await _wait(zip_hold)
	var speed := skater.velocity.length()
	_button(0, false)
	_button(1, false)
	await _wait(10.0 / Engine.physics_ticks_per_second)
	if speed > 0.0:
		release_keep_ratio = skater.velocity.length() / speed
	_log("ZIP let go at %.1f m/s, %.1f m/s 10 frames later" % [speed, skater.velocity.length()])
	await _wait(1.5)


func _scenario_lift() -> void:
	_place(ZIP_START, Vector3.FORWARD)
	await _wait(0.4)
	await _aim_at(LIFT_SPOT)
	if fire:
		_button(0, true)
	for i in 4:
		await get_tree().physics_frame
	if not grapple.left_attached:
		_log("LIFT the hook missed")
		return
	var start_y := skater.global_position.y
	var start_distance := grapple.rope(0).distance_from(_hand_point())
	var left_floor := false
	var end := _time + lift_hold
	while _time < end:
		var on_floor := skater.is_on_floor()
		left_floor = left_floor or not on_floor
		if left_floor and on_floor:
			lift_floor_frames += 1
		if _time <= end - lift_hold + 1.0:
			lift_rise = maxf(lift_rise, skater.global_position.y - start_y)
			lift_closer = start_distance - grapple.rope(0).distance_from(_hand_point())
		await get_tree().physics_frame
	_log("LIFT rose %.1f m, %.1f m closer in 1 s, %d frames on the floor, speed %.1f" % [
		lift_rise, lift_closer, lift_floor_frames, skater.velocity.length()])
	_button(0, false)
	await _wait(1.0)


func _hand_point() -> Vector3:
	return skater.global_position + Vector3.UP * grapple.fire_height


func _scenario_chain() -> void:
	_place(CHAIN_START, Vector3.FORWARD)
	await _wait(0.4)
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	var end := _time + SCENARIO_TIMEOUT
	while _time < end and not skater.is_airborne():
		await get_tree().physics_frame
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	_launch_speed = skater.velocity.length()
	_log("CHAIN rolled off the deck at %.1f m/s" % _launch_speed)
	for swing: int in swings:
		await _fall_for(fall_before_hook)
		var side := swing % 2
		await _aim_at(_canopy_spot_ahead())
		if not fire:
			continue
		_button(side, true)
		for i in 4:
			await get_tree().physics_frame
		if not grapple.rope(side).attached:
			_log("CHAIN swing %d: the hook missed" % swing)
			_button(side, false)
			continue
		hook_speeds.append(skater.velocity.length())
		var peak := 0.0
		while _time < end and not _past_release_point(side):
			peak = maxf(peak, skater.velocity.length())
			await get_tree().physics_frame
		swing_peaks.append(peak)
		release_speeds.append(skater.velocity.length())
		_button(side, false)
		_log("CHAIN swing %d: hooked at %.1f, peak %.1f, let go at %.1f m/s (y %.1f)" % [swing,
			hook_speeds[-1], peak, release_speeds[-1], skater.global_position.y])
	if not release_speeds.is_empty() and _launch_speed > 0.0:
		chain_gain = release_speeds[-1] / _launch_speed
	await _wait(1.0)


## Waits until the skater has been falling (moving down) for [param seconds].
func _fall_for(seconds: float) -> void:
	var falling := 0.0
	var end := _time + SCENARIO_TIMEOUT
	while _time < end and falling < seconds:
		falling = falling + get_physics_process_delta_time() if skater.velocity.y < 0.0 else 0.0
		await get_tree().physics_frame


## A point on the canopy [member aim_up_degrees] above level straight ahead of the travel.
func _canopy_spot_ahead() -> Vector3:
	var hand := skater.global_position + Vector3.UP * grapple.fire_height
	var ahead := Vector3(skater.velocity.x, 0.0, skater.velocity.z).normalized()
	if ahead.is_zero_approx():
		ahead = Vector3.FORWARD
	var rise := CANOPY_UNDERSIDE - hand.y
	return hand + ahead * rise / tan(deg_to_rad(aim_up_degrees)) + Vector3.UP * rise


## True on the upswing once the line on [param side] is [member release_degrees] past
## straight down (or the swing has stopped climbing).
func _past_release_point(side: int) -> bool:
	var rope := grapple.rope(side)
	if not rope.attached:
		return true
	var offset := skater.global_position + Vector3.UP * grapple.fire_height - rope.anchor
	var travel := Vector3(skater.velocity.x, 0.0, skater.velocity.z)
	var forward := Vector3(offset.x, 0.0, offset.z).dot(travel.normalized())
	var angle := rad_to_deg(atan2(forward, -offset.y))
	return angle >= release_degrees and skater.velocity.y > 0.0


func _place(at: Vector3, facing: Vector3) -> void:
	skater.global_position = at + Vector3.UP * 0.1
	skater.set_heading(facing)
	skater.camera_rig.snap_behind(skater.global_position, skater.heading)


func _track_zip(speed: float) -> void:
	if _both_since < 0.0:
		_both_since = _time
	zip_peak_speed = maxf(zip_peak_speed, speed)
	if zip_time_to_30 < 0.0 and speed >= 30.0:
		zip_time_to_30 = _time - _both_since
	var hand := skater.global_position + Vector3.UP * grapple.fire_height
	var distance := hand.distance_to((grapple.left_anchor + grapple.right_anchor) * 0.5)
	if distance < pass_distance:
		pass_distance = distance
		pass_speed = speed
		_since_pass = 0
		after_pass_ratio = 0.0
	elif _since_pass >= 0:
		_since_pass += 1


func _build_course() -> void:
	progress = GAME_STATE.new()
	progress.name = "GrappleBotProgress"
	progress.save_path = BOT_SAVE_PATH
	progress.appearance_path = ""
	progress.unlock_all = true
	add_child(progress)
	level = Node3D.new()
	level.name = "Course"
	add_child(level)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	level.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.68, 0.85)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	level.add_child(environment)
	_add_box("Floor", FLOOR_CENTRE, FLOOR_SIZE, Color(0.3, 0.32, 0.3))
	_add_box("Deck", DECK_CENTRE, DECK_SIZE, Color(0.55, 0.45, 0.35))
	_add_box("Canopy", CANOPY_CENTRE, CANOPY_SIZE, Color(0.4, 0.4, 0.48))
	# Pillars along the way so the speed reads in shots.
	for i in 40:
		var z := -20.0 - 30.0 * i
		for x: float in [-30.0, 30.0]:
			_add_box("Post", Vector3(x, 30.0, z), Vector3(2.0, 60.0, 2.0),
				Color(0.75, 0.3, 0.25) if i % 2 == 0 else Color(0.9, 0.85, 0.8))
	skater = SKATER_SCENE.instantiate() as Skater
	level.add_child(skater)
	skater.bind_progress(progress)


func _add_box(box_name: String, centre: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	level.add_child(body, true)


func _finish() -> void:
	finished = true
	_log("RESULT %s DONE zip_time_to_30=%.2f zip_peak=%.1f pass=%.2f m at %.1f m/s kept %.2f "
		% [scenario, zip_time_to_30, zip_peak_speed, pass_distance, pass_speed,
		after_pass_ratio] + "release_keep=%.2f unasked=%d hooks=%s peaks=%s releases=%s gain=%.2f"
		% [release_keep_ratio, unasked_releases, hook_speeds, swing_peaks, release_speeds,
		chain_gain])
	if quit_when_done:
		get_tree().quit()


func _on_grapple_hook_attached(side: int, point: Vector3) -> void:
	_log("HOOK %d stuck at %s, speed %.1f" % [side, point, skater.velocity.length()])


func _on_grapple_hook_released(side: int) -> void:
	if _held[side]:
		unasked_releases += 1
	_log("HOOK %d let go, speed %.1f" % [side, skater.velocity.length()])


func _log(line: String) -> void:
	print("[grapple_bot %.2f] %s" % [_time, line])


static func _find_skater(node: Node) -> Skater:
	if node is Skater:
		return node as Skater
	for child in node.get_children():
		var found := _find_skater(child)
		if found != null:
			return found
	return null
