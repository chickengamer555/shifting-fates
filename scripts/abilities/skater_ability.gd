class_name SkaterAbility
extends Node
## Base for a power the skater can use (grind, grapple, rocket boost, shift phase).
##
## Abilities are child nodes of the Skater. Every physics frame the Skater first calls
## [method update_aim] and then [method physics_tick] on each enabled ability in tree
## order, passing itself. An ability reads its own input actions and edits the body's
## velocity; the Skater keeps any horizontal velocity change as its new rolling speed and
## heading. While an ability reports [method is_controlling_movement], the Skater skips its
## own ground/air movement for that frame so the ability fully owns the motion (e.g. a dash).
## If it also [method places_body_directly], the Skater skips gravity,
## [code]move_and_slide()[/code] and its air state too: the ability has already put the body
## where it belongs (e.g. on a grind rail).
##
## Gated abilities name their [member unlock_id]; the Skater switches [member enabled] from
## GameState. Turning [member enabled] off mid-use calls [method _on_disabled], so the
## ability can drop whatever it was doing (no stuck hooks, sprays or grinds).

## Emitted when the ability starts doing something (hook fired, grind started, boost on).
signal activated
## Emitted when the ability stops (hook released, grind ended, boost off).
signal deactivated

## Value of [member unlock_id] for abilities that are always available.
const ALWAYS_UNLOCKED := &""

## Locked abilities ignore input. GameState unlocks grapple and rocket as the story goes.
@export var enabled: bool = true:
	set = set_enabled
## GameState ability id that gates this ability, or empty when it is always available.
@export var unlock_id: StringName = ALWAYS_UNLOCKED
## Off while a cutscene or menu owns the controls.
var input_enabled: bool = true


## Called by the Skater once per physics frame while [member enabled] is true.
func physics_tick(_skater: CharacterBody3D, _delta: float) -> void:
	pass


## Called by the Skater right before [method physics_tick] with where the player looks
## ([param view_forward], the camera's forward) and the board's flat [param facing].
func update_aim(_view_forward: Vector3, _facing: Vector3) -> void:
	pass


## True while this ability owns the skater's movement this frame.
func is_controlling_movement() -> bool:
	return false


## True when, while controlling the movement, the ability positions the body itself, so
## the host must not add gravity or call [code]move_and_slide()[/code].
func places_body_directly() -> bool:
	return false


## True while the ability is doing something (useful for HUD and tests).
func is_active() -> bool:
	return false


## Turns the ability on or off. Turning it off mid-use calls [method _on_disabled].
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not value:
		_on_disabled()


## Override to stop whatever the ability is doing when it gets disabled mid-use.
func _on_disabled() -> void:
	pass
