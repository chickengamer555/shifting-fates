class_name ScreenFade
extends CanvasLayer
## Full-screen colour fade that hides screen swaps (adapted from the library's fade-overlay).
##
## [method cover] fills the screen with a colour, [method reveal] clears it again. Both are
## awaitable and return true if the fade reached its end, false if another fade took over.
## A duration of 0 (or less) applies the fade at once without waiting a frame. Input under the
## shade is blocked while it is covering. Runs while the tree is paused.

## A fade stopped. [param completed] is false if another fade replaced it.
signal fade_ended(completed: bool)

## Above every other canvas layer.
const TOP_LAYER := 128

var _shade: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	layer = TOP_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.color = Color(Color.BLACK, 0.0)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)


## Covers the screen in [param color] over [param seconds]. Awaitable.
func cover(color: Color, seconds: float) -> bool:
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.color = Color(color, _shade.color.a)
	return await _fade_to(1.0, seconds)


## Clears the screen over [param seconds]. Awaitable.
func reveal(seconds: float) -> bool:
	var completed: bool = await _fade_to(0.0, seconds)
	if completed:
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return completed


## True while the shade is at least partly over the screen.
func is_covering() -> bool:
	return _shade.color.a > 0.0


func _fade_to(alpha: float, seconds: float) -> bool:
	_interrupt_running_fade()
	if seconds <= 0.0:
		_shade.color.a = alpha
		return true
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(_shade, "color:a", alpha, seconds)
	_tween.finished.connect(_on_tween_finished)
	return await fade_ended


## A killed tween never emits finished, so whoever awaited it is released by hand.
func _interrupt_running_fade() -> void:
	if _tween == null:
		return
	_tween.kill()
	_tween = null
	fade_ended.emit(false)


func _on_tween_finished() -> void:
	_tween = null
	fade_ended.emit(true)
