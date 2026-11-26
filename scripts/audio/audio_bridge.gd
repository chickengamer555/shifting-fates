class_name AudioBridge
extends Node
## Connects a level's gameplay to the [code]AudioDirector[/code]: the skater's motion drives
## the rolling, grind and wind loops, its abilities fire cues and the combo drives the
## combo-gain hit.
##
## A level calls [method bind] once its [Skater] and [ScoreKeeper] exist. Every physics frame
## the bridge forwards the skater's horizontal speed, whether its wheels are down and whether
## it is grinding. A shift-phase activation plays the dash cue, a grapple cast the fire cue
## and a hook sticking the attach cue at the anchor; the rocket boost switches the rocket
## loop; the keeper's [signal ScoreKeeper.combo_changed] reaches
## [method AudioDirector.on_combo_changed]. Unbound, it forwards nothing.

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")

## Where the sound goes. Null at ready means the [code]AudioDirector[/code] autoload; tests
## inject a fresh instance.
var director: AUDIO_DIRECTOR = null

var _skater: Skater = null
var _keeper: ScoreKeeper = null


func _ready() -> void:
	set_meta("verify_unit", "AudioBridge")
	if director == null:
		director = AudioDirector


func _physics_process(_delta: float) -> void:
	if _skater == null or director == null:
		return
	var grinding := _skater.grind_ability != null and _skater.grind_ability.grinding
	director.set_speed(_skater.speed)
	director.set_grounded(not _skater.is_airborne())
	director.set_grinding(grinding)


## Starts forwarding [param skater]'s motion and abilities and [param keeper]'s combo.
## Binding again lets go of the previous pair; either may be null.
func bind(skater: Skater, keeper: ScoreKeeper) -> void:
	_unbind()
	if director == null:
		director = AudioDirector
	_skater = skater
	_keeper = keeper
	if _skater != null:
		_skater.shift_phase.activated.connect(_on_shift_phase_activated)
		_skater.grapple_ability.hook_fired.connect(_on_grapple_hook_fired)
		_skater.grapple_ability.hook_attached.connect(_on_grapple_hook_attached)
		_skater.rocket_boost.activated.connect(_on_rocket_boost_activated)
		_skater.rocket_boost.deactivated.connect(_on_rocket_boost_deactivated)
	if _keeper != null:
		_keeper.combo_changed.connect(_on_keeper_combo_changed)


func _unbind() -> void:
	if _skater != null:
		_skater.shift_phase.activated.disconnect(_on_shift_phase_activated)
		_skater.grapple_ability.hook_fired.disconnect(_on_grapple_hook_fired)
		_skater.grapple_ability.hook_attached.disconnect(_on_grapple_hook_attached)
		_skater.rocket_boost.activated.disconnect(_on_rocket_boost_activated)
		_skater.rocket_boost.deactivated.disconnect(_on_rocket_boost_deactivated)
	if _keeper != null:
		_keeper.combo_changed.disconnect(_on_keeper_combo_changed)
	_skater = null
	_keeper = null


func _on_shift_phase_activated() -> void:
	director.play_cue(SoundBank.DASH)


func _on_grapple_hook_fired(_side: int) -> void:
	director.play_cue(SoundBank.GRAPPLE_FIRE)


func _on_grapple_hook_attached(_side: int, point: Vector3) -> void:
	director.play_cue(SoundBank.GRAPPLE_ATTACH, point)


func _on_rocket_boost_activated() -> void:
	director.set_rocket(true)


func _on_rocket_boost_deactivated() -> void:
	director.set_rocket(false)


func _on_keeper_combo_changed(multiplier: float, _rank_name: String) -> void:
	director.on_combo_changed(multiplier)
