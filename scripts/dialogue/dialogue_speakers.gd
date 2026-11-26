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


## True when [param speaker] is one of the known ids in [constant ALL].
static func is_valid(speaker: StringName) -> bool:
	return ALL.has(speaker)


## True for every god, including the unknown one: they share the gold style and font flashing.
static func is_god(speaker: StringName) -> bool:
	return GODS.has(speaker)


## The name shown above the line. Empty for narration; an unknown id is shown as-is.
static func display_name(speaker: StringName) -> String:
	return DISPLAY_NAMES.get(speaker, String(speaker))
