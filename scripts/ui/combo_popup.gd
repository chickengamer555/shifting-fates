class_name ComboPopup
extends Control
## The combo read-out that floats beside the skater: multiplier, rank and pending points.
##
## The [Hud] places it each frame with [method place_beside] (the skater's head projected
## to the screen) and says when a combo is scoring with [method set_scoring]. It shows only
## while scoring; when the combo ends it flashes the banked points ([method flash_banked]) or
## [constant BAILED_TEXT] ([method flash_bailed]) and fades away. The read-out grows heavier
## and warmer as the multiplier rises.
## [br]Numbers are always drawn in [method FontLibrary.ui_font]; only the rank's letters may
## use [method FontLibrary.combo_font] (The Jacatra draws its "0" as a logo).

const BAILED_TEXT := "Bailed"
## Where the read-out sits relative to the projected anchor point (px): right and above.
const ANCHOR_OFFSET := Vector2(56.0, -72.0)
## The read-out is kept this far (px) inside the screen and below the top strip.
const SCREEN_MARGIN := 24.0
const TOP_CLEARANCE := 84.0
## How quickly the read-out follows the skater on screen (1/s); high, but it smooths jitter.
const FOLLOW_RATE := 24.0
## Multiplier at which the read-out reaches its largest and warmest.
const FULL_HEAT_MULTIPLIER := 4.0
const BASE_MULTIPLIER := 1.0
## Seconds to fade in when a combo starts and out when it ends without points.
const FADE_SECONDS := 0.18
## Inter weights: the multiplier goes from [constant WARM_WEIGHT] to [constant HEAVY_WEIGHT]
## as it heats up; flashes are heavy, pending points medium.
const WARM_WEIGHT := 650
const HEAVY_WEIGHT := 900
const MEDIUM_WEIGHT := 500
## Durations are clamped to at least this, so a zero setting never divides by zero.
const MIN_SECONDS := 0.001

## How the multiplier is written, e.g. "x1.5".
@export var multiplier_format: String = "x%.1f"
## How pending and banked points are written.
@export var points_format: String = "+%d"
## Extra scale at [constant FULL_HEAT_MULTIPLIER] (0.7 = 70 % bigger).
@export var heat_scale: float = 0.7
## Scale the read-out pops to when the multiplier changes, then settles back.
@export var pop_scale: float = 1.12
@export var pop_seconds: float = 0.22
## Seconds a banked / bailed flash stays before it has faded out.
@export var flash_seconds: float = 1.1
## How far (px) a flash drifts up while it fades.
@export var flash_rise: float = 22.0
@export var cool_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hot_color: Color = Color(1.0, 0.8, 0.42, 1.0)
@export var banked_color: Color = Color(1.0, 0.86, 0.5, 1.0)
@export var bailed_color: Color = Color(1.0, 0.48, 0.42, 1.0)
## Thin light line drawn down the read-out's left edge.
@export var accent_color: Color = Color(1.0, 0.92, 0.75, 0.55)
@export var accent_width: float = 2.0

## True while a combo is scoring (the read-out is up).
var scoring: bool = false
## True while a banked / bailed flash is on screen.
var flashing: bool:
	get:
		return _flash_left > 0.0
## The point the read-out was last placed beside (screen px), e.g. the skater's head.
var anchor: Vector2 = Vector2.ZERO
var _heat: float = 0.0
var _flash_left: float = 0.0
var _fade: Tween = null
var _pop: Tween = null
var _placed: bool = false
var _number_font: Font = null
var _bail_font: Font = null

@onready var _stack: Control = %ComboStack
@onready var _multiplier_label: Label = %MultiplierLabel
@onready var _rank_label: Label = %RankLabel
@onready var _pending_label: Label = %PendingLabel
@onready var _flash_label: Label = %FlashLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	_flash_label.visible = false
	_number_font = FontLibrary.ui_font(HEAVY_WEIGHT)
	_bail_font = FontLibrary.title_font(HEAVY_WEIGHT)
	_multiplier_label.add_theme_font_override("font", FontLibrary.ui_font(WARM_WEIGHT))
	_pending_label.add_theme_font_override("font", FontLibrary.ui_font(MEDIUM_WEIGHT))
	_set_rank_font(_rank_label.text)


func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	var t := 1.0 - _flash_left / maxf(flash_seconds, MIN_SECONDS)
	_flash_label.position.y = -flash_rise * t
	_flash_label.modulate.a = 1.0 - smoothstep(0.45, 1.0, t)
	if _flash_left <= 0.0:
		_flash_label.visible = false
		if not scoring:
			visible = false
			modulate.a = 0.0


func _draw() -> void:
	if not _stack.visible:
		return
	var top := _stack.position.y + 6.0
	var bottom := _stack.position.y + _stack.size.y - 4.0
	var faded := Color(accent_color, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(0.0, top), Vector2(0.0, bottom)]),
		PackedColorArray([accent_color, faded]), accent_width, true)


## Shows the combo's [param multiplier], [param rank] and [param pending] points.
func show_combo(multiplier: float, rank: String, pending: int) -> void:
	var text := multiplier_format % multiplier
	var changed := text != _multiplier_label.text
	_multiplier_label.text = text
	_pending_label.text = points_format % pending if pending > 0 else ""
	_heat = clampf((multiplier - BASE_MULTIPLIER) / (FULL_HEAT_MULTIPLIER - BASE_MULTIPLIER),
		0.0, 1.0)
	if rank != _rank_label.text:
		_rank_label.text = rank
		_set_rank_font(rank)
		var weight := roundi(lerpf(WARM_WEIGHT, HEAVY_WEIGHT, _heat))
		_multiplier_label.add_theme_font_override("font", FontLibrary.ui_font(weight))
	var tint := cool_color.lerp(hot_color, _heat)
	_multiplier_label.add_theme_color_override("font_color", tint)
	if changed and scoring:
		_punch()
	else:
		_stack.scale = Vector2.ONE * _rest_scale()


## Shows the read-out while [param active], fades it out otherwise (unless a flash is up).
func set_scoring(active: bool) -> void:
	if active == scoring:
		return
	scoring = active
	if active:
		_flash_left = 0.0
		_flash_label.visible = false
		_stack.visible = true
		visible = true
		_fade_to(1.0)
	elif _flash_left <= 0.0:
		_fade_to(0.0)


## Places the read-out beside [param point] (screen px), kept on screen.
func place_beside(point: Vector2, delta: float) -> void:
	anchor = point
	var screen := get_viewport_rect().size
	var target := point + ANCHOR_OFFSET
	target.x = clampf(target.x, SCREEN_MARGIN, screen.x - SCREEN_MARGIN - size.x * 1.6)
	target.y = clampf(target.y, TOP_CLEARANCE, screen.y - SCREEN_MARGIN - size.y)
	if not _placed or not visible:
		position = target
		_placed = true
	else:
		position = position.lerp(target, 1.0 - exp(-FOLLOW_RATE * delta))


## The combo ended clean: flashes [param points] and fades out.
func flash_banked(points: int) -> void:
	_flash(points_format % points, banked_color, _number_font)


## The combo ended in a bail: flashes [constant BAILED_TEXT] and fades out.
func flash_bailed() -> void:
	_flash(BAILED_TEXT, bailed_color, _bail_font)


func _flash(text: String, colour: Color, font: Font) -> void:
	scoring = false
	if _fade != null:
		_fade.kill()
	_stack.visible = false
	queue_redraw()
	visible = true
	modulate.a = 1.0
	_flash_label.text = text
	_flash_label.add_theme_color_override("font_color", colour)
	_flash_label.add_theme_font_override("font", font)
	_flash_label.position.y = 0.0
	_flash_label.modulate.a = 1.0
	_flash_label.visible = true
	_flash_left = flash_seconds


func _fade_to(alpha: float) -> void:
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, FADE_SECONDS)
	if alpha <= 0.0:
		_fade.tween_callback(_hide_unless_scoring)
	queue_redraw()


func _hide_unless_scoring() -> void:
	if not scoring and _flash_left <= 0.0:
		visible = false


func _rest_scale() -> float:
	return 1.0 + heat_scale * _heat


func _punch() -> void:
	if _pop != null:
		_pop.kill()
	_stack.pivot_offset = Vector2(0.0, _stack.size.y)
	_stack.scale = Vector2.ONE * _rest_scale() * pop_scale
	_pop = create_tween()
	_pop.tween_property(_stack, "scale", Vector2.ONE * _rest_scale(), pop_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Letters go in the combo font; a rank with digits ("Godly x3") stays in Cinzel.
func _set_rank_font(rank: String) -> void:
	var font := _bail_font if FontLibrary.has_digits(rank) else FontLibrary.combo_font()
	_rank_label.add_theme_font_override("font", font)
