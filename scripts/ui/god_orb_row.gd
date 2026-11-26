class_name GodOrbRow
extends Control
## The gods present in a conversation: a row of [GodOrb]s at the top centre of the screen.
##
## Every child [GodOrb] stands for one [member GodOrb.speaker]; several orbs may share one
## (the unknown gods). Only present orbs take a place in the row, and the row stays centred
## on this control's origin as gods arrive, sliding the others aside. Callers say who is
## present, who speaks and when a word lands; the orbs do the rest.

## Horizontal distance between neighbouring orbs (px).
@export var spacing: float = 130.0
## How fast orbs slide to their place (fraction of the distance per second, roughly).
@export var slide_rate: float = 5.0

## The speaker whose orbs are talking; empty when no god speaks.
var speaking_speaker: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(true)


func _process(delta: float) -> void:
	_place(false, delta)


## The orbs standing for [param speaker] (empty when it has none).
func orbs_for(speaker: StringName) -> Array[GodOrb]:
	var found: Array[GodOrb] = []
	for orb: GodOrb in _orbs():
		if orb.speaker == speaker:
			found.append(orb)
	return found


## True when [param speaker] has at least one orb in this row.
func has_speaker(speaker: StringName) -> bool:
	return not orbs_for(speaker).is_empty()


## Fades [param speaker]'s orbs to [param amount] (0 gone, 1 fully there).
func set_presence(speaker: StringName, amount: float) -> void:
	for orb: GodOrb in orbs_for(speaker):
		orb.presence = clampf(amount, 0.0, 1.0)


## Brings [param speaker] in at full presence if it was not already at least that present.
func ensure_present(speaker: StringName) -> void:
	for orb: GodOrb in orbs_for(speaker):
		orb.presence = maxf(orb.presence, 1.0)


## Makes [param speaker]'s orbs talk and quiets every other orb; empty quiets all.
func set_speaking(speaker: StringName) -> void:
	speaking_speaker = speaker if has_speaker(speaker) else &""
	for orb: GodOrb in _orbs():
		orb.speaking = orb.speaker == speaking_speaker and speaker != &""


## A brief brightening of the talking orbs, e.g. as a word appears.
func pulse_speaking() -> void:
	for orb: GodOrb in orbs_for(speaking_speaker):
		orb.pulse()


## Extra brightness for [param speaker]'s orbs (0 = none), e.g. during a flash.
func set_flare(speaker: StringName, amount: float) -> void:
	for orb: GodOrb in orbs_for(speaker):
		orb.flare = amount


## Global position of the centre of [param speaker]'s first orb slot; the row centre when the
## speaker has no orb.
func slot_center(speaker: StringName) -> Vector2:
	var orbs := orbs_for(speaker)
	if orbs.is_empty():
		return global_position
	var orb := orbs[0]
	return global_position + _target_x(orb) * Vector2.RIGHT + orb.size.y * 0.5 * Vector2.DOWN


func _orbs() -> Array[GodOrb]:
	var orbs: Array[GodOrb] = []
	for child: Node in get_children():
		if child is GodOrb:
			orbs.append(child as GodOrb)
	return orbs


func _present() -> Array[GodOrb]:
	var present: Array[GodOrb] = []
	for orb: GodOrb in _orbs():
		if orb.presence > 0.0:
			present.append(orb)
	return present


## Centre x of [param orb] in the row, relative to this control's origin.
func _target_x(orb: GodOrb) -> float:
	var present := _present()
	var index := present.find(orb)
	if index < 0:
		return orb.position.x + orb.size.x * 0.5
	return (float(index) - float(present.size() - 1) * 0.5) * spacing


func _place(snap: bool, delta: float = 0.0) -> void:
	var weight := 1.0 if snap else clampf(slide_rate * delta, 0.0, 1.0)
	for orb: GodOrb in _orbs():
		var target := Vector2(_target_x(orb) - orb.size.x * 0.5, 0.0)
		var arriving := orb.intensity <= 0.0
		orb.position = target if snap or arriving else orb.position.lerp(target, weight)
