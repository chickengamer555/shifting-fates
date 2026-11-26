extends Node3D
## Test level. Tab swaps between walking and the spectator camera.
## Mouse capture lives in the player, so it works in any scene the player is in.

var spectating: bool = false

@onready var player: Player = %Player
@onready var spectator: SpectatorCamera = %SpectatorCamera


func _ready() -> void:
	set_meta("verify_unit", "Main")
	spectator.set_active(false)
	player.camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_spectator"):
		set_spectating(not spectating)


## Spectating starts from the player's eyes and hands the view back on exit.
func set_spectating(value: bool) -> void:
	spectating = value
	player.input_enabled = not value
	if value:
		spectator.global_transform = player.camera.global_transform
		spectator.set_active(true)
	else:
		spectator.set_active(false)
		player.camera.current = true

