class_name DialogueSpeakers
extends RefCounted
## The speaker ids a [DialogueLine] may use, and how each one is shown on screen.
##
## Ids are [StringName]s so authored [code].tres[/code] files stay readable. Add a speaker by
## adding a constant, listing it in [constant ALL] and giving it a display name.

const PLAYER := &"player"
## The white light god who guides the player.
const GOD := &"god"
const RED_GOD := &"red_god"
const BLUE_GOD := &"blue_god"
## A god whose name the player does not know yet; shown as "???".
const UNKNOWN_GOD := &"unknown_god"
const DOCTOR := &"doctor"
## Scene-setting text with no speaker name.
const NARRATION := &"narration"

const ALL: Array[StringName] = [PLAYER, GOD, RED_GOD, BLUE_GOD, UNKNOWN_GOD, DOCTOR, NARRATION]
const GODS: Array[StringName] = [GOD, RED_GOD, BLUE_GOD, UNKNOWN_GOD]

const DISPLAY_NAMES: Dictionary[StringName, String] = {
	PLAYER: "You",
	GOD: "God",
	RED_GOD: "Red God",
	BLUE_GOD: "Blue God",
	UNKNOWN_GOD: "???",
	DOCTOR: "Doctor",
	NARRATION: "",
}

## Colour of the one god light while each god speaks. The unknown gods share a violet; the
## extra colours only show in the gods' flash, as the other gods (???) flicker through.
const TINTS: Dictionary[StringName, Color] = {
	GOD: Color(1.0, 0.98, 0.92),
	RED_GOD: Color(1.0, 0.4, 0.32),
	BLUE_GOD: Color(0.42, 0.66, 1.0),
	UNKNOWN_GOD: Color(0.72, 0.68, 0.92),
}
## Every colour the light flickers through during the gods' flash.
const FLASH_TINTS: Array[Color] = [
	Color(1.0, 0.98, 0.92), Color(1.0, 0.4, 0.32), Color(0.42, 0.66, 1.0),
	Color(0.72, 0.45, 1.0), Color(0.35, 1.0, 0.55), Color(1.0, 0.7, 0.2),
]


## True when [param speaker] is one of the known ids in [constant ALL].
static func is_valid(speaker: StringName) -> bool:
	return ALL.has(speaker)


## True for every god, including the unknown one: they share the gold style and font flashing.
static func is_god(speaker: StringName) -> bool:
	return GODS.has(speaker)


## The name shown above the line. Empty for narration; an unknown id is shown as-is.
static func display_name(speaker: StringName) -> String:
	return DISPLAY_NAMES.get(speaker, String(speaker))


## The god light's colour while [param speaker] talks (the white god's for anyone else).
static func tint(speaker: StringName) -> Color:
	return TINTS.get(speaker, TINTS[GOD])
