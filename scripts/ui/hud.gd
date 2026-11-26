class_name Hud
extends CanvasLayer
## In-game overlay: combo multiplier and rank, score and goal progress, the grind balance
## meter, rocket fuel and grapple hook lights.
##
## Hand it what to show with [method bind]; it never searches the tree. Score, goal and
## combo come from the [ScoreKeeper]'s signals; ability state (grind balance, fuel, hooks)
## is read each frame from the bound [Skater]'s abilities. The grind meter only shows while
## grinding, the fuel bar only while the rocket is unlocked, the hook lights only while the
## grapple is. The combo text pops bigger whenever it changes. Put The Jacatra (or any
## display font) in [member display_font].

## Font for the combo multiplier and rank (null keeps the theme font).
@export var display_font: Font = null:
	set = set_display_font
## How the multiplier is written, e.g. "x1.5".
@export var multiplier_format: String = "x%.1f"
## How the goal is written: points so far, then the goal.
@export var goal_format: String = "%d / %d"
## Scale the combo text pops to when it changes.
@export var pop_scale: float = 1.3
## Seconds the pop takes to settle back.
@export var pop_time: float = 0.25
## Colour of a hook light while that hook is stuck.
@export var hook_on_color: Color = Color(0.85, 0.9, 1.0, 1.0)
## Colour of a hook light while that hook is free.
@export var hook_off_color: Color = Color(0.3, 0.3, 0.35, 0.6)

var _skater: Skater = null
var _keeper: ScoreKeeper = null
var _pop: Tween = null

@onready var _combo_box: Control = %ComboBox
@onready var _multiplier_label: Label = %MultiplierLabel
@onready var _rank_label: Label = %RankLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _goal_bar: ProgressBar = %GoalBar
@onready var _goal_label: Label = %GoalLabel
@onready var _grind_meter: GrindMeter = %GrindMeter
@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _grapple_hooks: Control = %GrappleHooks
@onready var _left_hook: ColorRect = %LeftHook
@onready var _right_hook: ColorRect = %RightHook


func _ready() -> void:
	set_meta("verify_unit", "Hud")
	_apply_font()
	_show_abilities()


func _process(_delta: float) -> void:
	_show_abilities()


## Shows [param skater]'s abilities and [param keeper]'s score from now on. Either may be
## null to show nothing for it.
func bind(skater: Skater, keeper: ScoreKeeper) -> void:
	if _keeper != null:
		_keeper.score_changed.disconnect(_on_keeper_score_changed)
		_keeper.combo_changed.disconnect(_on_keeper_combo_changed)
	_skater = skater
	_keeper = keeper
	if _keeper != null:
		_keeper.score_changed.connect(_on_keeper_score_changed)
		_keeper.combo_changed.connect(_on_keeper_combo_changed)
		_show_score(_keeper.score)
		_show_combo(_keeper.multiplier, _keeper.rank_name)
	_show_abilities()


## Sets the combo font (see [member display_font]).
func set_display_font(font: Font) -> void:
	display_font = font
	if is_node_ready():
		_apply_font()


func _apply_font() -> void:
	for label: Label in [_multiplier_label, _rank_label]:
		if display_font != null:
			label.add_theme_font_override("font", display_font)
		else:
			label.remove_theme_font_override("font")


func _show_combo(multiplier: float, rank_name: String) -> void:
	_multiplier_label.text = multiplier_format % multiplier
	_rank_label.text = rank_name
	_punch()


func _show_score(score: int) -> void:
	_score_label.text = str(score)
	var goal := _keeper.goal if _keeper != null else null
	if goal == null:
		_goal_bar.value = 0.0
		_goal_label.text = ""
		return
	_goal_bar.value = goal.progress()
	_goal_label.text = goal_format % [goal.points, goal.threshold]


func _show_abilities() -> void:
	var grind := _skater.grind_ability if _skater != null else null
	var rocket := _skater.rocket_boost if _skater != null else null
	var grapple := _skater.grapple_ability if _skater != null else null
	_grind_meter.visible = grind != null and grind.grinding
	if _grind_meter.visible:
		_grind_meter.balance = grind.balance
	_fuel_bar.visible = rocket != null and rocket.enabled
	if _fuel_bar.visible:
		_fuel_bar.value = rocket.fuel
	_grapple_hooks.visible = grapple != null and grapple.enabled
	if _grapple_hooks.visible:
		_left_hook.color = hook_on_color if grapple.left_attached else hook_off_color
		_right_hook.color = hook_on_color if grapple.right_attached else hook_off_color


## A quick scale pop on the combo text.
func _punch() -> void:
	if _pop != null:
		_pop.kill()
	_combo_box.pivot_offset = _combo_box.size * 0.5
	_combo_box.scale = Vector2.ONE * pop_scale
	_pop = create_tween()
	_pop.tween_property(_combo_box, "scale", Vector2.ONE, pop_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_keeper_score_changed(score: int) -> void:
	_show_score(score)


func _on_keeper_combo_changed(multiplier: float, rank_name: String) -> void:
	_show_combo(multiplier, rank_name)
