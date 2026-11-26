extends Node
## Run-wide progress: which level the player is on and which god-given abilities are unlocked.
##
## Level 1 is the tutorial. The gods grant abilities on the schedule in
## [constant ABILITY_UNLOCK_LEVELS]. An ability in [constant GIFTED_ABILITIES] is handed over
## in a story moment on its level: there it stays locked until [method grant_ability] (the
## gods' gift event), and every later level has it anyway. Each ability is announced once by
## [signal ability_unlocked] when it becomes available (on [method advance_level] or
## [method grant_ability]). Progress, gifts included, is saved with [method save_game] and
## restored with [method load_game]; nothing loads automatically, the boot flow decides.
## [br]Skills in [constant STORY_SKILLS] (the tricks) are not abilities of their own but are
## given the same way: nobody has them until the gods give them on their level
## ([method grant_ability], at the end of the tutorial's dialogue for the tricks), and every
## later level has them anyway, the test hub included. Being given one is not announced on
## arrival in a level, only by [method grant_ability].

## [param id] became available on the level just entered.
signal ability_unlocked(id: StringName)
## The current level changed to [param level] (advanced, loaded or reset).
signal level_changed(level: int)

## The first level (the tutorial).
const FIRST_LEVEL := 1
## Level from which each god-given ability is unlocked. Abilities not listed never unlock
## here (always-on moves such as grinding are not gated by GameState).
const ABILITY_UNLOCK_LEVELS := {
	&"grapple": 2,
	&"rocket": 4,
}
## Abilities the gods hand over in a story moment on their unlock level (not at its start).
const GIFTED_ABILITIES: Array[StringName] = [&"grapple"]
## The tricks (flips, board tricks, grabs, spins): given at the end of the tutorial's dialogue.
const TRICKS := &"tricks"
## Skills the gods give in a story moment on a level (id -> level), and every later level
## has anyway. Not in [constant ABILITY_UNLOCK_LEVELS]: no level start announces them.
const STORY_SKILLS := {
	TRICKS: 1,
}
## Points needed to open the portal, by level (index 0 is level 1). Levels past the end
## reuse the last goal.
const LEVEL_POINT_GOALS: Array[int] = [1000, 3000, 6000, 10000, 15000]
## Default save file.
const DEFAULT_SAVE_PATH := "user://save.cfg"
## ConfigFile section and keys used by the save file.
const SAVE_SECTION := "progress"
const SAVE_KEY_LEVEL := "level"
const SAVE_KEY_GIFTS := "gifts"

## Level the player is on, starting at [constant FIRST_LEVEL].
var current_level: int = FIRST_LEVEL
## Where [method save_game] and [method load_game] read and write. Tests point it elsewhere.
var save_path: String = DEFAULT_SAVE_PATH
## Where the painted look ([Appearance]) is saved. Empty: never saved (tests, dev tools).
var appearance_path: String = Appearance.DEFAULT_PATH
## Dev switch (the test hub): every god-given ability is unlocked whatever the level, except
## a gifted one on its own level, which still waits for its gift so the moment can be seen.
var unlock_all: bool = false
## Gifted abilities already handed over (see [method grant_ability]).
var granted_abilities: Array[StringName] = []


## True if [param id] is unlocked on the current level (or [member unlock_all] is on).
## A story skill is unlocked once given or past its level, [member unlock_all] or not.
## Unknown ids are never unlocked.
func is_ability_unlocked(id: StringName) -> bool:
	if STORY_SKILLS.has(id):
		return granted_abilities.has(id) or current_level > int(STORY_SKILLS[id])
	if not ABILITY_UNLOCK_LEVELS.has(id):
		return false
	if granted_abilities.has(id):
		return true
	var level := int(ABILITY_UNLOCK_LEVELS[id])
	var awaiting_gift := GIFTED_ABILITIES.has(id) and current_level == level
	if unlock_all:
		return not awaiting_gift
	return current_level >= level and not awaiting_gift


## Hands over the gifted ability [param id] (the gods' gift on its level) and announces it.
## It stays unlocked from then on and is saved with the progress.
func grant_ability(id: StringName) -> void:
	if not _known(id) or granted_abilities.has(id):
		return
	var had := is_ability_unlocked(id)
	granted_abilities.append(id)
	if not had:
		ability_unlocked.emit(id)


## Moves to the next level and announces any ability that became available on it.
func advance_level() -> void:
	var before := _unlocked_ids()
	current_level += 1
	level_changed.emit(current_level)
	for id: StringName in _unlocked_ids():
		if not before.has(id):
			ability_unlocked.emit(id)


## Points needed on [param level] to open its portal.
func point_goal(level: int) -> int:
	var index := clampi(level - FIRST_LEVEL, 0, LEVEL_POINT_GOALS.size() - 1)
	return LEVEL_POINT_GOALS[index]


## A fresh goal tracker for the current level.
func create_level_goal() -> LevelGoal:
	return LevelGoal.new(point_goal(current_level))


## Back to a new game (level 1). Does not touch the save file.
func reset_progress() -> void:
	current_level = FIRST_LEVEL
	granted_abilities.clear()
	level_changed.emit(current_level)


## Writes progress to [member save_path]. Returns the ConfigFile error code.
func save_game() -> Error:
	var config := ConfigFile.new()
	config.set_value(SAVE_SECTION, SAVE_KEY_LEVEL, current_level)
	config.set_value(SAVE_SECTION, SAVE_KEY_GIFTS, PackedStringArray(granted_abilities))
	return config.save(save_path)


## Reads progress from [member save_path]. A missing or unreadable file keeps the current
## progress and returns its error code; abilities are not re-announced on load.
func load_game() -> Error:
	if not FileAccess.file_exists(save_path):
		return ERR_FILE_NOT_FOUND
	var config := ConfigFile.new()
	var err := config.load(save_path)
	if err != OK:
		return err
	var level := int(config.get_value(SAVE_SECTION, SAVE_KEY_LEVEL, FIRST_LEVEL))
	current_level = maxi(level, FIRST_LEVEL)
	granted_abilities.clear()
	var gifts: Variant = config.get_value(SAVE_SECTION, SAVE_KEY_GIFTS, PackedStringArray())
	if gifts is PackedStringArray:
		for id: String in gifts as PackedStringArray:
			if _known(StringName(id)):
				granted_abilities.append(StringName(id))
	level_changed.emit(current_level)
	return OK


## True for an id the gods can give: an ability or a story skill.
static func _known(id: StringName) -> bool:
	return ABILITY_UNLOCK_LEVELS.has(id) or STORY_SKILLS.has(id)


func _unlocked_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in ABILITY_UNLOCK_LEVELS:
		if is_ability_unlocked(id):
			ids.append(id)
	return ids
