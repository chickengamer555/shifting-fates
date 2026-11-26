extends Node
## Developer preview of the story flow: boots [code]scenes/game.tscn[/code], starts a new game
## and presses the real advance action on a timer, so the opening, the hand-over to the intro
## and the intro (lines, painting, title cross, free skate) can be watched or rendered without
## anyone at the keys. Each second it prints the screen and the line on show to the log.
## [br]It runs on a GameState of its own that never saves the painted look, and presses
## Done on the paint creator after [member seconds_painting].
## [br]The press goes through [method Input.parse_input_event], the same path as a key, so
## anything that swallows input in the real game swallows it here too.
## [br]User args: [code]--intro[/code] mounts the intro alone (no menu, no opening);
## [code]--mouse[/code] presses with a left click; [code]--hold-intro[/code] waits
## [constant INTRO_HOLD_SECONDS] on the intro's first line.

const GAME_SCENE := preload("res://scenes/game.tscn")
const INTRO_SCENE := preload("res://scenes/levels/intro.tscn")
const GAME_STATE := preload("res://autoload/game_state.gd")
const SAVE_PATH := "user://flow_preview_save.cfg"
const ADVANCE_ACTION := &"ui_accept"
const INTRO_HOLD_SECONDS := 8.0
const BOX_PATH := ^"UI/DialogueBox"
const TEXT_PATH := ^"Panel/Content/TextLabel"
const PAINT_PATH := ^"PaintCreator"

## Seconds between two presses of the advance action.
@export var seconds_per_press: float = 0.6
## Seconds before the first press (lets the opening light come up).
@export var first_press_delay: float = 1.0
## Press with a left click at the middle of the screen instead of the action.
@export var press_with_mouse: bool = false
## Seconds the paint creator stays open before the preview presses Done.
@export var seconds_painting: float = 1.5

var _game: GameFlow = null
var _intro: IntroLevel = null
var _press_left: float = 0.0
var _report_left: float = 0.0
var _elapsed: float = 0.0
var _intro_hold: float = 0.0
var _painting_left: float = 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	press_with_mouse = press_with_mouse or args.has("--mouse")
	if args.has("--hold-intro"):
		_intro_hold = INTRO_HOLD_SECONDS
	var state: GAME_STATE = GAME_STATE.new()
	state.name = "PreviewGameState"
	state.save_path = SAVE_PATH
	state.appearance_path = ""
	add_child(state)
	if args.has("--intro"):
		_intro = INTRO_SCENE.instantiate() as IntroLevel
		_intro.game_state = state
		add_child(_intro)
	else:
		_game = GAME_SCENE.instantiate() as GameFlow
		_game.game_state = state
		add_child(_game)
		_game.start_new_game()
	_press_left = first_press_delay


func _process(delta: float) -> void:
	_elapsed += delta
	_press_left -= delta
	if _screen() is IntroLevel and _intro_hold > 0.0:
		_intro_hold -= delta
		_press_left = seconds_per_press
	if _press_left <= 0.0:
		_press_left = seconds_per_press
		_press(true)
		_press(false)
	_finish_paint(delta)
	_report_left -= delta
	if _report_left <= 0.0:
		_report_left = 1.0
		_report()


## The screen on show: the intro alone, or the game flow's current screen.
func _screen() -> Node:
	return _intro if _intro != null else _game.current_screen


func _finish_paint(delta: float) -> void:
	var screen := _screen()
	var creator := screen.get_node_or_null(PAINT_PATH) as PaintCreator if screen != null else null
	if creator == null:
		_painting_left = seconds_painting
		return
	_painting_left -= delta
	if _painting_left <= 0.0:
		creator.finish()


func _press(pressed: bool) -> void:
	if press_with_mouse:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = get_viewport().get_visible_rect().size * 0.5
		click.global_position = click.position
		Input.parse_input_event(click)
		return
	var event := InputEventAction.new()
	event.action = ADVANCE_ACTION
	event.pressed = pressed
	Input.parse_input_event(event)


func _report() -> void:
	var screen := _screen()
	var box := screen.get_node_or_null(BOX_PATH) as DialogueBox if screen != null else null
	var text := ""
	if box != null and box.is_playing():
		text = (box.get_node(TEXT_PATH) as DialogueText).text.left(40)
	var painting := screen != null and screen.has_node(PAINT_PATH)
	print("[flow %5.1fs] screen=%s playing=%s painting=%s line='%s'" % [
		_elapsed, screen.name if screen != null else "-", box != null and box.is_playing(),
		painting, text])
