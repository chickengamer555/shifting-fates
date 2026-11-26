class_name GodLightsLevel
extends LevelController
## Level 2: the gods show themselves as coloured lights and hand the player the grapple.
##
## At the start only the red god's light glows (the original god is the white one). Each god
## light comes up the first time that god speaks; when the blue god joins, the unknown gods'
## lights ([code]???[/code]) come up dimly with it. The [code]gods_flash[/code] dialogue event
## makes every light flash in turn for [member flash_seconds] while their text goes wild.
## The grapple itself is unlocked by [code]GameState[/code] from level 2.

const EVENT_GODS_FLASH := &"gods_flash"
## Light energy below this counts as off, and the god's orb is hidden.
const ORB_VISIBLE_ENERGY := 0.05
## The light on show during a flash burns this many times brighter than [member lit_energy].
const FLASH_BOOST := 2.0

## Energy of a god's light once it is up.
@export var lit_energy: float = 6.0
## The unknown gods only glow this fraction of [member lit_energy].
@export_range(0.0, 1.0) var unknown_fraction: float = 0.35
## How long the lights flash after [code]gods_flash[/code].
@export var flash_seconds: float = 4.0
## Seconds each flash lasts before the next light takes over.
@export var flash_step_seconds: float = 0.12

## True while the lights are flashing.
var flashing: bool = false

var _flash_left: float = 0.0
var _step_left: float = 0.0
var _flash_index: int = 0
## Target energy per light when not flashing.
var _rest_energy: Dictionary[OmniLight3D, float] = {}

@onready var _white_god: OmniLight3D = $GodLights/WhiteGod
@onready var _red_god: OmniLight3D = $GodLights/RedGod
@onready var _blue_god: OmniLight3D = $GodLights/BlueGod
@onready var _unknown_gods: Node3D = $GodLights/UnknownGods


func _ready() -> void:
	for light: OmniLight3D in _all_lights():
		_rest_energy[light] = 0.0
	_rest_energy[_red_god] = lit_energy
	_apply_rest_energy()
	super._ready()


func _process(delta: float) -> void:
	if not flashing:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		flashing = false
		_apply_rest_energy()
		return
	_step_left -= delta
	if _step_left <= 0.0:
		_step_left = flash_step_seconds
		_flash_next()


## Makes every god light flash in turn for [member flash_seconds].
func flash_gods() -> void:
	flashing = true
	_flash_left = flash_seconds
	_step_left = 0.0
	# Every god is known to be present once they flash together.
	for light: OmniLight3D in _all_lights():
		if _rest_energy[light] <= 0.0:
			_rest_energy[light] = lit_energy * unknown_fraction
	if _rest_energy[_white_god] < lit_energy:
		_rest_energy[_white_god] = lit_energy


func _handle_dialogue_line_started(line: DialogueLine) -> void:
	match line.speaker:
		DialogueSpeakers.GOD:
			_raise(_white_god, lit_energy)
		DialogueSpeakers.RED_GOD:
			_raise(_red_god, lit_energy)
		DialogueSpeakers.BLUE_GOD:
			_raise(_blue_god, lit_energy)
			for light: OmniLight3D in _unknown_lights():
				_raise(light, lit_energy * unknown_fraction)


func _handle_dialogue_event(event: StringName) -> void:
	if event == EVENT_GODS_FLASH:
		flash_gods()


func _raise(light: OmniLight3D, energy: float) -> void:
	_rest_energy[light] = maxf(_rest_energy[light], energy)
	if not flashing:
		_set_energy(light, _rest_energy[light])


func _flash_next() -> void:
	var lights := _all_lights()
	_flash_index = (_flash_index + 1) % lights.size()
	for index: int in lights.size():
		var bright := index == _flash_index
		_set_energy(lights[index], lit_energy * FLASH_BOOST if bright else 0.0)


func _apply_rest_energy() -> void:
	for light: OmniLight3D in _all_lights():
		_set_energy(light, _rest_energy[light])


func _all_lights() -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D] = [_white_god, _red_god, _blue_god]
	lights.append_array(_unknown_lights())
	return lights


func _unknown_lights() -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D] = []
	for child: Node in _unknown_gods.get_children():
		if child is OmniLight3D:
			lights.append(child as OmniLight3D)
	return lights


static func _set_energy(light: OmniLight3D, energy: float) -> void:
	light.light_energy = energy
	for child: Node in light.get_children():
		if child is Node3D:
			(child as Node3D).visible = energy > ORB_VISIBLE_ENERGY
