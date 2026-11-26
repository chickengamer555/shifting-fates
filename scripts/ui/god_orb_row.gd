class_name GodOrbRow
extends Control
## The gods on screen: ONE ball of light ([GodOrb]) at the top centre that stands for every god.
##
## Each god speaks through the same light, which glides to that god's colour
## ([method DialogueSpeakers.tint]); the first time the light comes up it snaps to the colour
## instead. [method set_frenzy] makes it flash violently: random colours from
## [constant DialogueSpeakers.FLASH_TINTS], strobing brightness and size, until it is calmed
## again and glides back to the god who was last heard. The orb's centre sits on this
## control's origin.

## How fast the light glides to a new god's colour (per second; ~0.5 s to settle).
@export var tint_rate: float = 7.0
## Seconds between strobes while in a frenzy, picked at random between these.
@export var frenzy_step_min: float = 0.04
@export var frenzy_step_max: float = 0.11
## Brightness added on a strobe, picked at random up to this.
@export var frenzy_flare: float = 2.4
## Size swing of a strobe (fraction of the light's size).
@export_range(0.0, 1.0) var frenzy_scale_swing: float = 0.45

## The god whose voice the light carries now; empty when no god speaks.
var speaking_speaker: StringName = &""
## The god whose colour the light is gliding to (the last god heard).
var colour_speaker: StringName = DialogueSpeakers.GOD
## True while the light flashes violently.
var frenzy: bool = false

var _step_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place()


func _process(delta: float) -> void:
	_place()
	var orb := light()
	if orb == null:
		return
	if frenzy:
		_step_left -= delta
		if _step_left <= 0.0:
			_step_left = _rng.randf_range(frenzy_step_min, frenzy_step_max)
			_strobe(orb)
		return
	var weight := 1.0 - exp(-tint_rate * delta)
	orb.tint = orb.tint.lerp(DialogueSpeakers.tint(colour_speaker), weight)


## The one god light; null if the row has none.
func light() -> GodOrb:
	for child: Node in get_children():
		if child is GodOrb:
			return child as GodOrb
	return null


## The light, for any god (empty for anyone else or when there is no light).
func orbs_for(speaker: StringName) -> Array[GodOrb]:
	var found: Array[GodOrb] = []
	var orb := light()
	if orb != null and DialogueSpeakers.is_god(speaker):
		found.append(orb)
	return found


## True when [param speaker] is a god, i.e. speaks through the light.
func has_speaker(speaker: StringName) -> bool:
	return not orbs_for(speaker).is_empty()


## Fades the light to [param amount] (0 gone, 1 fully there); any god's presence is the light's.
func set_presence(speaker: StringName, amount: float) -> void:
	for orb: GodOrb in orbs_for(speaker):
		orb.presence = clampf(amount, 0.0, 1.0)


## Brings the light up for [param speaker] at full presence. A light that was not showing
## takes the god's colour at once instead of gliding into it.
func ensure_present(speaker: StringName) -> void:
	for orb: GodOrb in orbs_for(speaker):
		if orb.intensity <= 0.0 and orb.presence <= 0.0:
			orb.tint = DialogueSpeakers.tint(speaker)
		orb.presence = maxf(orb.presence, 1.0)
		colour_speaker = speaker


## Makes the light talk for [param speaker] and glide to its colour; empty (or a non-god)
## quiets it and leaves the colour where it is.
func set_speaking(speaker: StringName) -> void:
	speaking_speaker = speaker if has_speaker(speaker) else &""
	if speaking_speaker != &"":
		colour_speaker = speaking_speaker
	var orb := light()
	if orb != null:
		orb.speaking = speaking_speaker != &""


## A brief brightening of the light while it talks, e.g. as a word appears.
func pulse_speaking() -> void:
	for orb: GodOrb in orbs_for(speaking_speaker):
		orb.pulse()


## Extra brightness for the light (0 = none). Ignored for non-gods.
func set_flare(speaker: StringName, amount: float) -> void:
	for orb: GodOrb in orbs_for(speaker):
		orb.flare = amount


## Starts or stops the violent flash. Stopping puts the flare and size back and lets the
## colour glide home to [member colour_speaker].
func set_frenzy(on: bool) -> void:
	if frenzy == on:
		return
	frenzy = on
	_step_left = 0.0
	var orb := light()
	if orb == null or on:
		return
	orb.flare = 0.0
	orb.scale = Vector2.ONE


## Global centre of the light (the row's origin when there is none).
func slot_center(_speaker: StringName) -> Vector2:
	var orb := light()
	if orb == null:
		return global_position
	return global_position + orb.size.y * 0.5 * Vector2.DOWN


func _place() -> void:
	var orb := light()
	if orb != null:
		orb.position = Vector2(-orb.size.x * 0.5, 0.0)


func _strobe(orb: GodOrb) -> void:
	var tints := DialogueSpeakers.FLASH_TINTS
	var next := tints[_rng.randi_range(0, tints.size() - 1)]
	if next.is_equal_approx(orb.tint):
		next = tints[(tints.find(next) + 1) % tints.size()]
	orb.tint = next
	# Mostly blinding, now and then nearly dark, so it reads as a strobe, not a glow.
	orb.flare = frenzy_flare * _rng.randf() if _rng.randf() > 0.2 else -0.4
	orb.scale = Vector2.ONE * (1.0 + _rng.randf_range(-0.5, 1.0) * frenzy_scale_swing)
