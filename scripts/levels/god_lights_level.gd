class_name GodLightsLevel
extends LevelController
## Level 2: the gods talk through the one god light and hand the player the grapple.
##
## The [DialogueBox]'s single god light at the top of the screen takes the colour of whichever
## god speaks (red, then blue, then the original white god), and one [OmniLight3D] in the world
## (GodLights/GodLight) mirrors it, so the level is tinted by the same light. The
## [code]gods_flash[/code] event (the blue god's "I concur") sends that line berserk through
## [method DialogueBox.set_frenzy]: the light strobes through the gods' colours, the world light
## with it, and the words glitch, until the next line. The white god's next line
## ("It appears they've granted you a gift") carries [code]gods_gift[/code], which hands over
## the grapple through [method GameState.grant_ability]; until then it is locked on this level,
## even in the test hub.

const EVENT_GODS_FLASH := &"gods_flash"
const EVENT_GODS_GIFT := &"gods_gift"
## Ability the gods hand over.
const GIFT := &"grapple"
## The world light burns at most this many times [member lit_energy] at a strobe's peak.
const FLASH_BOOST := 3.0

## Energy of the world light while the on-screen light shines calmly.
@export var lit_energy: float = 6.0

## True while the gods' flash is on.
var flashing: bool:
	get:
		return dialogue_box != null and dialogue_box.frenzy

@onready var _light: OmniLight3D = $GodLights/GodLight


func _ready() -> void:
	_light.light_energy = 0.0
	super._ready()
	_mirror_light()


func _process(_delta: float) -> void:
	_mirror_light()


## Sends the line on screen into the gods' violent flash (until the next line).
func flash_gods() -> void:
	if dialogue_box != null:
		dialogue_box.set_frenzy(true)


func _handle_dialogue_event(event: StringName) -> void:
	match event:
		EVENT_GODS_FLASH:
			flash_gods()
		EVENT_GODS_GIFT:
			_give_gift()


## Hands the player the gods' gift and switches it on for the skater at once.
func _give_gift() -> void:
	if game_state == null:
		return
	game_state.grant_ability(GIFT)
	if skater != null:
		skater.apply_unlocks()


## The world light takes the on-screen light's colour, and its brightness relative to a calm
## light; without a dialogue box it just shines white.
func _mirror_light() -> void:
	var orb := dialogue_box.god_light() if dialogue_box != null else null
	if orb == null:
		_light.light_color = DialogueSpeakers.tint(DialogueSpeakers.GOD)
		_light.light_energy = lit_energy
		return
	_light.light_color = orb.tint
	var level := maxf(orb.intensity, 0.0) / GodOrb.CALM_LEVEL
	_light.light_energy = clampf(lit_energy * level, 0.0, lit_energy * FLASH_BOOST)
