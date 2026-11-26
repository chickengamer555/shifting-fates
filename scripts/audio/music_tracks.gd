class_name MusicTracks
extends RefCounted
## The game's music tracks and which one plays where. Static only.
##
## Each track has an id (saved in settings), a display title and a file under
## [code]res://composing/[/code]. [method plan] decides what a screen wants:
## [br]- the intro (the upper echelon) plays [constant INTRO_TRACK];
## [br]- the main menu and the opening (hospital) are silent;
## [br]- every other screen (the levels) shuffles: a random track, never the one just heard.
## [br]A track picked in the music player ([MusicPlayerMenu]; [constant AUTO] means none) plays
## on every screen that has music, looping. The choice is saved in [code]Settings[/code].

## No track picked: intro track on the intro, shuffle elsewhere.
const AUTO := &""
const UPPER_ECHELON := &"upper_echelon"
const ETERNAL_SYNTH := &"eternal_synth"
const FOREVER_GLORY := &"forever_glory"
const GODS_TORMENT := &"gods_torment"
const INTRO_TRACK := UPPER_ECHELON
## Every track id, in music player order.
const IDS: Array[StringName] = [UPPER_ECHELON, ETERNAL_SYNTH, FOREVER_GLORY, GODS_TORMENT]
const TITLES: Dictionary[StringName, String] = {
	UPPER_ECHELON: "The Upper Echelon",
	ETERNAL_SYNTH: "Eternal Synth",
	FOREVER_GLORY: "Forever Glory",
	GODS_TORMENT: "Gods Torment",
}
const PATHS: Dictionary[StringName, String] = {
	UPPER_ECHELON: "res://composing/The Upper Echelon.wav",
	ETERNAL_SYNTH: "res://composing/Eternal synth.wav",
	FOREVER_GLORY: "res://composing/Forever Glory.wav",
	GODS_TORMENT: "res://composing/Gods Torment.wav",
}
## Label for [constant AUTO] in the music player.
const AUTO_TITLE := "Auto (intro theme, then shuffle)"

## Screen ids, matching [GameFlow]'s [code]SCREEN_*[/code] constants.
const SCREEN_MENU := &"menu"
const SCREEN_OPENING := &"opening"
const SCREEN_INTRO := &"intro"

enum Mode { SILENT, FIXED, SHUFFLE }


## Whether [param id] names a track.
static func is_track(id: StringName) -> bool:
	return IDS.has(id)


## Display title of [param id]; [constant AUTO_TITLE] for [constant AUTO] or an unknown id.
static func title(id: StringName) -> String:
	return TITLES.get(id, AUTO_TITLE)


## What [param screen_id] wants with the settings choice [param chosen]:
## [code]{"mode": Mode, "track": StringName}[/code] ([code]track[/code] only for FIXED).
static func plan(screen_id: StringName, chosen: StringName) -> Dictionary:
	if screen_id == SCREEN_OPENING or screen_id == SCREEN_MENU:
		return {"mode": Mode.SILENT, "track": AUTO}
	if is_track(chosen):
		return {"mode": Mode.FIXED, "track": chosen}
	if screen_id == SCREEN_INTRO:
		return {"mode": Mode.FIXED, "track": INTRO_TRACK}
	return {"mode": Mode.SHUFFLE, "track": AUTO}


## The track after [param track] in [constant IDS], wrapping round; the first for AUTO.
static func next_in_list(track: StringName) -> StringName:
	return IDS[(IDS.find(track) + 1) % IDS.size()]


## A random track for shuffle, never [param previous] (when there is another to pick).
static func shuffle_pick(previous: StringName, rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = IDS.duplicate()
	if pool.size() > 1:
		pool.erase(previous)
	return pool[rng.randi_range(0, pool.size() - 1)]


## The stream for [param id], or null for an unknown id or a missing file.
static func load_stream(id: StringName) -> AudioStream:
	var path: String = PATHS.get(id, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream
