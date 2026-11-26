extends Node
## Developer preview of the in-game HUD: level art, the real skater and a [ScoreKeeper] bound
## to the [Hud]. On a timer it drops the skater from a height and adds flip tricks, so a
## combo builds beside the skater, banks and flashes; rendered without input.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const SKATER_SCENE := preload("res://scenes/player/skater.tscn")

@export var stage: PackedScene = null
@export var spawn: Vector3 = Vector3(45.0, 0.1, 60.0)
@export var goal_points: int = 3000
## Points already banked when the preview starts (fills the goal bar part way).
@export var banked_before: int = 1240
## Heights the skater is dropped from, one per drop, and seconds between drops.
@export var drop_heights: PackedFloat32Array = [26.0, 40.0, 30.0]
@export var seconds_between_drops: float = 4.5
## Trick points added while falling, every [member trick_interval] seconds.
@export var trick_points: int = 120
@export var trick_interval: float = 0.4
## The drop (0-based) that ends in a bail, [member bail_after] seconds after it starts.
@export var bail_drop: int = 2
@export var bail_after: float = 1.4
## Show the rocket fuel and grapple hooks as if unlocked.
@export var show_abilities: bool = true

var _skater: Skater = null
var _keeper: ScoreKeeper = null
var _drop: int = 0
var _until_drop: float = 0.2
var _until_trick: float = 0.0
var _until_bail: float = -1.0


func _ready() -> void:
	if stage != null:
		add_child(stage.instantiate())
	_skater = SKATER_SCENE.instantiate() as Skater
	_skater.position = spawn
	add_child(_skater)
	_skater.input_enabled = false
	_skater.camera.make_current()
	if show_abilities:
		_skater.rocket_boost.enabled = true
		_skater.rocket_boost.fuel = 0.7
		_skater.grapple_ability.enabled = true
	_keeper = ScoreKeeper.new()
	var goal := LevelGoal.new(goal_points)
	goal.add_points(banked_before)
	_keeper.set_goal(goal)
	_keeper.combo.total_score = banked_before
	add_child(_keeper)
	_keeper.bind(_skater)
	var hud := HUD_SCENE.instantiate() as Hud
	add_child(hud)
	hud.bind(_skater, _keeper)


func _physics_process(delta: float) -> void:
	_until_drop -= delta
	if _until_drop <= 0.0 and _drop < drop_heights.size():
		_skater.position = spawn + Vector3.UP * drop_heights[_drop]
		_skater.velocity = Vector3.ZERO
		if _drop == bail_drop:
			_until_bail = bail_after
		_drop += 1
		_until_drop = seconds_between_drops
	if _until_bail > 0.0:
		_until_bail -= delta
		if _until_bail <= 0.0:
			_keeper.combo.land(false)
	_until_trick -= delta
	if _until_trick <= 0.0 and _skater.is_airborne() and _keeper.combo.is_airborne():
		_keeper.combo.add_trick(trick_points)
		_until_trick = trick_interval
