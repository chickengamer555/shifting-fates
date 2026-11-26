class_name AudioBridge
extends Node
## Connects a level's gameplay to the [code]AudioDirector[/code]: the skater's motion drives
## the rolling, grind and wind loops, its abilities fire cues and the combo drives the
## combo-gain hit.
##
## A level calls [method bind] once its [Skater] and [ScoreKeeper] exist. Every physics frame
## the bridge forwards the skater's horizontal speed, whether its wheels are down and whether
## it is grinding, and while the wheels are down the [enum SurfaceTable.Surface] under them
## (found by a [SurfaceDetector]), so the rolling loop and the landing match the ground. A
## shift-phase activation plays the dash cue; a grapple cast plays the fire cue, a hook
## sticking the attach cue at the anchor and a hook letting go the release cue, and while both
## hooks pull the skater in the rope-reel loop runs; the rocket boost switches the rocket
## loop; the keeper's [signal ScoreKeeper.combo_changed] reaches
## [method AudioDirector.on_combo_changed]. Leaving the floor moving up at least
## [constant OLLIE_MIN_RISE] m/s plays the ollie pop (rolling off a ledge does not), touching
## down plays the landing for the surface landed on (except the first touch-down after
## [method bind], which is the skater settling at its spawn) and each flip trick or grab plays
## the trick whoosh. Combo changes before that first touch-down are not forwarded either: a
## skater dropping onto its spawn floor builds air time, but it is no trick, so it must not
## sound the combo-gain hit and its sub-bass layer. Unbound, it forwards nothing.

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
## Upward speed (m/s) on leaving the floor that counts as a jump: a plain ollie is 5.
const OLLIE_MIN_RISE := 2.5
## Landing loudness, in dB, when the landing was not clean (a softer, scrappier touch-down).
const UNCLEAN_LAND_DB := -4.0
## Loudness of each grapple cast's whip, in dB. Both hooks usually cast together, doubling it.
const GRAPPLE_FIRE_DB := -12.0

## Where the sound goes. Null at ready means the [code]AudioDirector[/code] autoload; tests
## inject a fresh instance.
var director: AUDIO_DIRECTOR = null
## Finds the ground's surface. Made at ready from the game's [SurfaceTable]; tests may swap it.
var detector: SurfaceDetector = null

var _skater: Skater = null
var _keeper: ScoreKeeper = null
var _was_on_floor: bool = true
## False until the bridge has seen the skater on the floor since binding.
var _settled: bool = false


func _ready() -> void:
	set_meta("verify_unit", "AudioBridge")
	if director == null:
		director = AudioDirector
	if detector == null:
		detector = SurfaceDetector.new()


func _physics_process(_delta: float) -> void:
	if _skater == null or director == null:
		return
	var grinding := _skater.grind_ability != null and _skater.grind_ability.grinding
	director.set_speed(_skater.speed)
	director.set_grounded(not _skater.is_airborne())
	director.set_grinding(grinding)
	var on_floor := _skater.is_on_floor()
	if on_floor:
		director.set_surface(detector.detect(_skater))
	var grapple := _skater.grapple_ability
	director.set_reeling(grapple != null and grapple.left_attached and grapple.right_attached)
	if _was_on_floor and not on_floor and _skater.velocity.y >= OLLIE_MIN_RISE:
		director.play_cue(SoundBank.OLLIE)
	_was_on_floor = on_floor
	_settled = _settled or on_floor


## Starts forwarding [param skater]'s motion and abilities and [param keeper]'s combo.
## Binding again lets go of the previous pair; either may be null.
func bind(skater: Skater, keeper: ScoreKeeper) -> void:
	_unbind()
	if director == null:
		director = AudioDirector
	if detector == null:
		detector = SurfaceDetector.new()
	_skater = skater
	_keeper = keeper
	if _skater != null:
		_was_on_floor = _skater.is_on_floor()
		_settled = _was_on_floor
		_skater.landed.connect(_on_skater_landed)
		_skater.trick_performed.connect(_on_skater_trick_performed)
		_skater.grab_started.connect(_on_skater_grab_started)
		_skater.shift_phase.activated.connect(_on_shift_phase_activated)
		_skater.grapple_ability.hook_fired.connect(_on_grapple_hook_fired)
		_skater.grapple_ability.hook_attached.connect(_on_grapple_hook_attached)
		_skater.grapple_ability.hook_released.connect(_on_grapple_hook_released)
		_skater.rocket_boost.activated.connect(_on_rocket_boost_activated)
		_skater.rocket_boost.deactivated.connect(_on_rocket_boost_deactivated)
	if _keeper != null:
		_keeper.combo_changed.connect(_on_keeper_combo_changed)


func _unbind() -> void:
	if _skater != null:
		_skater.landed.disconnect(_on_skater_landed)
		_skater.trick_performed.disconnect(_on_skater_trick_performed)
		_skater.grab_started.disconnect(_on_skater_grab_started)
		_skater.shift_phase.activated.disconnect(_on_shift_phase_activated)
		_skater.grapple_ability.hook_fired.disconnect(_on_grapple_hook_fired)
		_skater.grapple_ability.hook_attached.disconnect(_on_grapple_hook_attached)
		_skater.grapple_ability.hook_released.disconnect(_on_grapple_hook_released)
		_skater.rocket_boost.activated.disconnect(_on_rocket_boost_activated)
		_skater.rocket_boost.deactivated.disconnect(_on_rocket_boost_deactivated)
	if _keeper != null:
		_keeper.combo_changed.disconnect(_on_keeper_combo_changed)
	_skater = null
	_keeper = null
	if director != null:
		director.set_reeling(false)


func _on_skater_landed(clean: bool) -> void:
	if not _settled:
		return
	if _skater.is_on_floor():
		director.set_surface(detector.detect(_skater))
	director.play_landing(0.0 if clean else UNCLEAN_LAND_DB)


func _on_skater_trick_performed(_trick_id: StringName) -> void:
	director.play_cue(SoundBank.TRICK)


func _on_skater_grab_started(_grab_id: StringName) -> void:
	director.play_cue(SoundBank.TRICK)


func _on_shift_phase_activated() -> void:
	director.play_cue(SoundBank.DASH)


func _on_grapple_hook_fired(_side: int) -> void:
	director.play_cue(SoundBank.GRAPPLE_FIRE, null, GRAPPLE_FIRE_DB)


func _on_grapple_hook_attached(_side: int, point: Vector3) -> void:
	director.play_cue(SoundBank.GRAPPLE_ATTACH, point)


func _on_grapple_hook_released(_side: int) -> void:
	director.play_cue(SoundBank.GRAPPLE_RELEASE)


func _on_rocket_boost_activated() -> void:
	director.set_rocket(true)


func _on_rocket_boost_deactivated() -> void:
	director.set_rocket(false)


func _on_keeper_combo_changed(multiplier: float, _rank_name: String) -> void:
	if not _settled:
		return
	director.on_combo_changed(multiplier)
