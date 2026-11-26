extends Node
## Run-wide progress: which level the player is on and which god-given abilities are unlocked.
##
## Level 1 is the tutorial. The gods grant abilities on the schedule in
## [constant ABILITY_UNLOCK_LEVELS]; each is announced once by [signal ability_unlocked]
## when [method advance_level] reaches its level. Progress is saved with [method save_game]
## and restored with [method load_game]; nothing loads automatically, the boot flow decides.

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
## Points needed to open the portal, by level (index 0 is level 1). Levels past the end
## reuse the last goal.
const LEVEL_POINT_GOALS: Array[int] = [1000, 3000, 6000, 10000, 15000]
## Default save file.
const DEFAULT_SAVE_PATH := "user://save.cfg"
## ConfigFile section and keys used by the save file.
const SAVE_SECTION := "progress"
const SAVE_KEY_LEVEL := "level"

## Level the player is on, starting at [constant FIRST_LEVEL].
var current_level: int = FIRST_LEVEL
## Where [method save_game] and [method load_game] read and write. Tests point it elsewhere.
var save_path: String = DEFAULT_SAVE_PATH
## Where the painted look ([Appearance]) is saved. Empty: never saved (tests, dev tools).
var appearance_path: String = Appearance.DEFAULT_PATH
## Dev switch (the test hub): every god-given ability is unlocked whatever the level.
var unlock_all: bool = false


## True if [param id] is unlocked on the current level (or [member unlock_all] is on).
## Unknown ids are never unlocked.
func is_ability_unlocked(id: StringName) -> bool:
	if not ABILITY_UNLOCK_LEVELS.has(id):
		return false
	if unlock_all:
		return true
	return current_level >= int(ABILITY_UNLOCK_LEVELS[id])


## Moves to the next level and announces any ability unlocked on it.
func advance_level() -> void:
	current_level += 1
	level_changed.emit(current_level)
	for id: StringName in ABILITY_UNLOCK_LEVELS:
		if int(ABILITY_UNLOCK_LEVELS[id]) == current_level:
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
	level_changed.emit(current_level)


## Writes progress to [member save_path]. Returns the ConfigFile error code.
func save_game() -> Error:
	var config := ConfigFile.new()
	config.set_value(SAVE_SECTION, SAVE_KEY_LEVEL, current_level)
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
	level_changed.emit(current_level)
	return OK
