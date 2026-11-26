class_name Hud
extends CanvasLayer
## In-game overlay: one thin strip across the top (score, goal progress, unlocked abilities),
## the combo read-out beside the skater and the grind balance meter.
##
## Hand it what to show with [method bind]; it never searches the tree. Score, goal and
## combo come from the [ScoreKeeper]'s signals; ability state (grind balance, fuel, hooks)
## is read each frame from the bound [Skater]'s abilities.
## [br]- The %TopStrip shows the score, the goal bar with "points / goal", and the rocket
##   fuel and grapple hooks only once those abilities are unlocked.
## [br]- The %ComboPopup ([ComboPopup]) floats beside the skater (its head projected through
##   the active camera) only while a combo is scoring: the multiplier has risen or points are
##   pending. It then flashes the banked points or "Bailed" and fades.
## [br]- The %GrindMeter shows only while grinding.
## [br]- The %Crosshair marks the screen centre, where the hooks fire, once the grapple is
##   unlocked.
## [br]Numbers are always drawn in [method FontLibrary.ui_font]; captions in
## [method FontLibrary.title_font]; only the rank's letters use the combo font.

## Inter weights for the score and the small numbers.
const SCORE_WEIGHT := 600
const SMALL_WEIGHT := 500
## Cinzel weight and letter spacing (px) for the strip's small captions.
const CAPTION_WEIGHT := 700
const CAPTION_SPACING := 2
## Where the combo read-out goes when there is no camera to project through.
const FALLBACK_ANCHOR := Vector2(0.58, 0.55)
const BASE_MULTIPLIER := 1.0

## How the goal is written: points so far, then the goal.
@export var goal_format: String = "%d / %d"
## Height above the skater's origin (m) the combo read-out is placed beside.
@export var head_height: float = 1.7
## Colour of a hook light while that hook is stuck.
@export var hook_on_color: Color = Color(1.0, 0.93, 0.78, 1.0)
## Colour of a hook light while that hook is free.
@export var hook_off_color: Color = Color(1.0, 1.0, 1.0, 0.22)

var _skater: Skater = null
var _keeper: ScoreKeeper = null

@onready var _top_strip: Control = %TopStrip
@onready var _combo_popup: ComboPopup = %ComboPopup
@onready var _score_label: Label = %ScoreLabel
@onready var _goal_bar: ProgressBar = %GoalBar
@onready var _goal_label: Label = %GoalLabel
@onready var _grind_meter: GrindMeter = %GrindMeter
@onready var _fuel: Control = %Fuel
@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _grapple_hooks: Control = %GrappleHooks
@onready var _left_hook: ColorRect = %LeftHook
@onready var _right_hook: ColorRect = %RightHook
@onready var _crosshair: Control = %Crosshair


func _ready() -> void:
	set_meta("verify_unit", "Hud")
	_apply_fonts()
	_show_abilities()


func _process(delta: float) -> void:
	_show_abilities()
	_follow_combo(delta)


## Shows [param skater]'s abilities and [param keeper]'s score from now on. Either may be
## null to show nothing for it.
func bind(skater: Skater, keeper: ScoreKeeper) -> void:
	if _keeper != null:
		_keeper.score_changed.disconnect(_on_keeper_score_changed)
		_keeper.combo_changed.disconnect(_on_keeper_combo_changed)
		_keeper.combo_banked.disconnect(_on_keeper_combo_banked)
		_keeper.combo.combo_failed.disconnect(_on_combo_failed)
	_skater = skater
	_keeper = keeper
	if _keeper != null:
		_keeper.score_changed.connect(_on_keeper_score_changed)
		_keeper.combo_changed.connect(_on_keeper_combo_changed)
		_keeper.combo_banked.connect(_on_keeper_combo_banked)
		_keeper.combo.combo_failed.connect(_on_combo_failed)
		_show_score(_keeper.score)
		_show_combo()
	_show_abilities()


## True while a combo is earning something: the multiplier has risen or points are pending.
func is_combo_scoring() -> bool:
	if _keeper == null or not _keeper.combo.is_airborne():
		return false
	return _keeper.multiplier > BASE_MULTIPLIER or _keeper.combo.pending_points > 0


func _apply_fonts() -> void:
	_score_label.add_theme_font_override("font", FontLibrary.ui_font(SCORE_WEIGHT))
	var small := FontLibrary.ui_font(SMALL_WEIGHT)
	_goal_label.add_theme_font_override("font", small)
	var caption := FontLibrary.title_font(CAPTION_WEIGHT)
	if caption is FontVariation:
		(caption as FontVariation).spacing_glyph = CAPTION_SPACING
	for label: Node in _top_strip.find_children("*Caption", "Label"):
		(label as Label).add_theme_font_override("font", caption)


func _show_combo() -> void:
	if _keeper == null:
		return
	_combo_popup.show_combo(_keeper.multiplier, _keeper.rank_name, _keeper.combo.pending_points)


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
	_fuel.visible = rocket != null and rocket.enabled
	_fuel_bar.visible = _fuel.visible
	if _fuel.visible:
		_fuel_bar.value = rocket.fuel
	_grapple_hooks.visible = grapple != null and grapple.enabled
	_crosshair.visible = _grapple_hooks.visible
	if _grapple_hooks.visible:
		_left_hook.color = hook_on_color if grapple.left_attached else hook_off_color
		_right_hook.color = hook_on_color if grapple.right_attached else hook_off_color


## Keeps the combo read-out up only while scoring, beside the skater's head on screen.
func _follow_combo(delta: float) -> void:
	var scoring := is_combo_scoring()
	if scoring:
		_show_combo()
	_combo_popup.set_scoring(scoring)
	if _skater == null or not _combo_popup.visible:
		return
	var head := _skater.global_position + Vector3.UP * head_height
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		camera = _skater.camera
	var point := get_viewport().get_visible_rect().size * FALLBACK_ANCHOR
	if camera != null and not camera.is_position_behind(head):
		point = camera.unproject_position(head)
	_combo_popup.place_beside(point, delta)


func _on_keeper_score_changed(score: int) -> void:
	_show_score(score)


func _on_keeper_combo_changed(_multiplier: float, _rank_name: String) -> void:
	_show_combo()


func _on_keeper_combo_banked(points: int, clean: bool) -> void:
	if clean:
		_combo_popup.flash_banked(points)


func _on_combo_failed() -> void:
	if _combo_popup.scoring or _combo_popup.visible:
		_combo_popup.flash_bailed()
