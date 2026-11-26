extends Node3D
## Skate test level: the whole loop in one place (kicker, ledges, two grind rails, tall
## towers to grapple, a phaseable wall, scoring and the HUD). In debug builds Tab swaps
## between skating and the spectator camera. Mouse capture lives in the skater, so it works
## in any scene the skater is in.
##
## The test level has its own progress at [member playground_level] so every ability can be
## tried; the story levels take unlocks from the GameState autoload.

const GAME_STATE_SCRIPT := preload("res://autoload/game_state.gd")

## Level whose unlocks the test level uses (4 unlocks grapple and rocket).
@export var playground_level: int = 4

var spectating: bool = false

var _progress: GAME_STATE_SCRIPT = GAME_STATE_SCRIPT.new()

@onready var skater: Skater = %Skater
@onready var spectator: SpectatorCamera = %SpectatorCamera
@onready var score_keeper: ScoreKeeper = %ScoreKeeper
@onready var hud: Hud = %Hud


func _ready() -> void:
	set_meta("verify_unit", "Main")
	_progress.name = "PlaygroundProgress"
	add_child(_progress)
	while _progress.current_level < playground_level:
		_progress.advance_level()
	skater.bind_progress(_progress)
	score_keeper.bind(skater)
	hud.bind(skater, score_keeper)
	spectator.set_active(false)
	skater.camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("toggle_spectator"):
		set_spectating(not spectating)


## Spectating starts from the skater's camera and hands the view back on exit.
func set_spectating(value: bool) -> void:
	spectating = value
	skater.input_enabled = not value
	if value:
		spectator.global_transform = skater.camera.global_transform
		spectator.set_active(true)
	else:
		spectator.set_active(false)
		skater.camera.current = true
