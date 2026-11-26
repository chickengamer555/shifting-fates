class_name UiSounds
extends RefCounted
## Menu sounds for any UI, without restyling it: one call wires every button under a node.
##
## [codeblock]
## func _ready() -> void:
##     UiSounds.wire(self)                    # every BaseButton below this menu
##     UiSounds.wire_back(%BackButton)        # a "back" button plays the back cue instead
## UiSounds.play_hover()                      # or fire a cue by hand
## [/codeblock]
## A wired button plays [constant SoundBank.UI_HOVER] when the mouse enters it or it takes
## keyboard/pad focus, and [constant SoundBank.UI_CLICK] (or [constant SoundBank.UI_BACK]) when
## pressed. Sounds go through the [code]AudioDirector[/code] pool, so a click still finishes
## after the menu that played it is freed. Wiring the same button twice does nothing. Pass a
## [param director] to use a fresh AudioDirector (tests); null means the autoload.

const AUDIO_DIRECTOR := preload("res://autoload/audio_director.gd")
## Meta key set on a wired button so it is never wired twice.
const WIRED_META := &"ui_sounds_wired"


## Wires every [BaseButton] at or under [param root]. Returns how many were newly wired.
static func wire(root: Node, director: AUDIO_DIRECTOR = null) -> int:
	var count := 0
	if root is BaseButton:
		count += 1 if wire_button(root as BaseButton, SoundBank.UI_CLICK, director) else 0
	for child: Node in root.get_children():
		count += wire(child, director)
	return count


## Wires [param button] to play the back cue when pressed (and hover as usual). Call it before
## [method wire] on its menu, or on a button already wired, to switch it to the back cue.
static func wire_back(button: BaseButton, director: AUDIO_DIRECTOR = null) -> bool:
	unwire(button)
	return wire_button(button, SoundBank.UI_BACK, director)


## Wires one button: hover on mouse-enter and focus, [param press_cue] on press. False when it
## was already wired.
static func wire_button(button: BaseButton, press_cue: StringName = SoundBank.UI_CLICK,
		director: AUDIO_DIRECTOR = null) -> bool:
	if button == null or button.has_meta(WIRED_META):
		return false
	var target := _director(director)
	if target == null:
		return false
	var hover := target.play_cue.bind(SoundBank.UI_HOVER)
	var press := target.play_cue.bind(press_cue)
	button.mouse_entered.connect(hover)
	button.focus_entered.connect(hover)
	button.pressed.connect(press)
	button.set_meta(WIRED_META, [hover, press])
	return true


## Removes the sounds [method wire_button] added to [param button].
static func unwire(button: BaseButton) -> void:
	if button == null or not button.has_meta(WIRED_META):
		return
	var calls: Array = button.get_meta(WIRED_META)
	var hover: Callable = calls[0]
	var press: Callable = calls[1]
	if button.mouse_entered.is_connected(hover):
		button.mouse_entered.disconnect(hover)
	if button.focus_entered.is_connected(hover):
		button.focus_entered.disconnect(hover)
	if button.pressed.is_connected(press):
		button.pressed.disconnect(press)
	button.remove_meta(WIRED_META)


static func play_hover(director: AUDIO_DIRECTOR = null) -> void:
	_play(SoundBank.UI_HOVER, director)


static func play_click(director: AUDIO_DIRECTOR = null) -> void:
	_play(SoundBank.UI_CLICK, director)


static func play_back(director: AUDIO_DIRECTOR = null) -> void:
	_play(SoundBank.UI_BACK, director)


static func _play(cue: StringName, director: AUDIO_DIRECTOR) -> void:
	var target := _director(director)
	if target != null:
		target.play_cue(cue)


## The given director, else the AudioDirector autoload (null outside a running tree).
static func _director(director: AUDIO_DIRECTOR) -> AUDIO_DIRECTOR:
	if director != null:
		return director
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(^"AudioDirector") as AUDIO_DIRECTOR
