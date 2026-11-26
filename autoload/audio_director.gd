extends Node
## Plays the game's sound: skating loops, speed-based wind, combo hits, one-shots and voices.
##
## Every sound comes from a [SoundBank] (by default [constant BANK_PATH]); an empty slot is
## silent (no player starts) unless the bank has [member SoundBank.use_placeholders] on.
## One-shots go through a fixed [CuePlayerPool] on the SFX bus, music through two
## crossfading players on the Music bus. Gameplay code calls in each frame or on
## events and never holds a player:
## [codeblock]
## AudioDirector.set_speed(velocity.length())   # rolling loop + wind
## AudioDirector.set_grounded(is_on_floor())
## AudioDirector.set_surface(SurfaceTable.Surface.WOOD)  # crossfades the rolling loop
## AudioDirector.play_landing()                  # the landing for the current surface
## AudioDirector.play_cue(SoundBank.DASH)
## AudioDirector.play_cue(SoundBank.GRAPPLE_ATTACH, hook_point)  # positional
## AudioDirector.on_combo_changed(tracker.multiplier)
## AudioDirector.start_voice(&"god")             # call per line; the voice holds its middle
## [/codeblock]
## Unknown cues and speakers are a warning and are counted in [member rejected_requests].

## A one-shot cue started.
signal cue_played(cue: StringName)

const BANK_PATH := "res://scenes/audio/sound_bank.tres"
const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")
const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"
## Level used for a silent loop, in dB.
const SILENT_DB := AudioLevels.SILENT_DB
const POOL_SIZE := 8
## Speeds (m/s) at or under this are standing still: physics jitter never starts the rolling.
const ROLL_MIN_SPEED := 0.1
## Speed (m/s) where the rolling loop reaches full volume and top pitch.
const ROLL_FULL_SPEED := 12.0
const ROLL_MIN_PITCH := 0.9
const ROLL_MAX_PITCH := 1.3
## Grind loop level at a standstill and at [constant ROLL_FULL_SPEED].
const GRIND_MIN_LEVEL := 0.5
const GRIND_MIN_PITCH := 0.9
const GRIND_MAX_PITCH := 1.2
const HEART_LEVEL := 1.0
const ROCKET_LEVEL := 1.0
## Seconds the rolling loop takes to crossfade to a new surface's loop.
const SURFACE_FADE_SECONDS := 0.25
## Level of the rope-reel loop while both hooks pull.
const REEL_LEVEL := 0.8
## Node names for each voice speaker.
const VOICE_NODE_NAMES: Dictionary[StringName, String] = {
	SoundBank.SPEAKER_GOD: "God",
	SoundBank.SPEAKER_DOCTOR: "Doctor",
}

## Where every sound comes from. Set before the node enters the tree to swap banks.
@export var bank: SoundBank

## 0 to 1 level of the rolling loop, from speed.
var rolling_level: float = 0.0
## 0 to 1 level of the grind loop; 0 when not grinding.
var grind_level: float = 0.0
## 0 to 1 multiplier on hospital and wind ambience; lowered by [method duck_ambience].
var ambience_level: float = 1.0:
	set(value):
		ambience_level = clampf(value, 0.0, 1.0)
		_apply_ambience()
var speed: float = 0.0
var grounded: bool = true
var grinding: bool = false
## The [enum SurfaceTable.Surface] under the wheels (see [method set_surface]).
var surface: SurfaceTable.Surface = SurfaceTable.Surface.CONCRETE
## The cue the rolling loop ([code]Loops/Rolling[/code]) plays: the surface's own, or
## [constant SoundBank.ROLLING] when that slot is empty.
var rolling_cue: StringName = SoundBank.ROLLING
## 0 to 1 progress of a surface crossfade; 1 when none is running.
var surface_blend: float = 1.0
## Surface changes heard so far (each one starts a crossfade).
var surface_changes: int = 0
## True while the grapple is reeling the skater in.
var reeling: bool = false
var rocket_active: bool = false
var heart_monitor_active: bool = false
## Last combo multiplier given to [method on_combo_changed].
var combo_multiplier: float = ComboAudioMapping.BASE_MULTIPLIER
## Pitch the last combo-gain hit played at.
var combo_pitch: float = ComboAudioMapping.NEUTRAL_PITCH
## Combo-gain hits played so far.
var combo_gains: int = 0
## The last one-shot cue started.
var last_cue: StringName = &""
## Requests for an unknown cue or speaker, which were ignored with a warning.
var rejected_requests: int = 0
## True while a music track is playing or fading in.
var music_playing: bool = false

var _pool: CuePlayerPool
var _wind: WindAmbience
var _rolling: AudioStreamPlayer
## The previous surface's loop, fading out under [member _rolling] during a crossfade.
var _rolling_out: AudioStreamPlayer
var _reel: AudioStreamPlayer
var _grind: AudioStreamPlayer
var _rocket: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _voices: Dictionary[StringName, SustainedVoice] = {}
var _music_players: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _ambience_tween: Tween
## The one running fade per music player or voice: a new fade replaces it.
var _fades: Dictionary[Node, Tween] = {}


func _ready() -> void:
	set_meta("verify_unit", "AudioDirector")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SETTINGS_SCRIPT.ensure_buses()
	if bank == null:
		bank = _load_default_bank()
	_pool = CuePlayerPool.new()
	_pool.name = "Pool"
	_pool.flat_size = POOL_SIZE
	_pool.spatial_size = POOL_SIZE
	_pool.bus = BUS_SFX
	add_child(_pool)
	_build_loops()
	_wind = WindAmbience.new()
	_wind.name = "Wind"
	_wind.bank = bank
	_wind.bus = BUS_SFX
	add_child(_wind)
	_build_voices()
	_build_music()


func _process(delta: float) -> void:
	if surface_blend < 1.0:
		surface_blend = move_toward(surface_blend, 1.0, delta / SURFACE_FADE_SECONDS)
		_apply_skating()


## Plays the one-shot [param cue] from the bank. Pass a [Vector3] as [param at_position] for a
## positional sound. Returns false for an unknown cue (with a warning) or an empty slot
## (silently: an empty slot is meant to be quiet).
func play_cue(cue: StringName, at_position: Variant = null, volume_db: float = 0.0,
		pitch: float = 1.0) -> bool:
	if not SoundBank.is_cue(cue):
		_reject("unknown sound cue '%s'" % cue)
		return false
	var stream: AudioStream = bank.get_stream(cue) if bank != null else null
	if stream == null:
		return false
	if at_position is Vector3:
		_pool.play_at(stream, at_position, volume_db, pitch)
	else:
		_pool.play_flat(stream, volume_db, pitch)
	last_cue = cue
	cue_played.emit(cue)
	return true


## The skater's speed in m/s: drives the rolling and grind loops and the wind. Call every frame.
func set_speed(new_speed: float) -> void:
	speed = maxf(new_speed, 0.0) if is_finite(new_speed) else 0.0
	_wind.set_speed(speed)
	_apply_skating()


## Whether the wheels are on the ground. Rolling is silent in the air.
func set_grounded(on_ground: bool) -> void:
	grounded = on_ground
	_apply_skating()


## Whether the skater is grinding a rail: swaps the rolling loop for the grind loop.
func set_grinding(on: bool) -> void:
	grinding = on
	_apply_skating()


## The surface under the wheels changed: the rolling loop crossfades to that surface's loop
## over [constant SURFACE_FADE_SECONDS] (an empty surface slot keeps the concrete loop).
func set_surface(new_surface: SurfaceTable.Surface) -> void:
	if new_surface == surface:
		return
	surface = new_surface
	surface_changes += 1
	var cue := _surface_rolling_cue()
	if cue == rolling_cue:
		return
	var was_playing := _rolling.playing
	if was_playing:
		_rolling_out.stream = _rolling.stream
		_rolling_out.pitch_scale = _rolling.pitch_scale
		_rolling_out.play(_rolling.get_playback_position())
		surface_blend = 0.0
	rolling_cue = cue
	_rolling.stream = bank.get_stream(cue) if bank != null else null
	if was_playing:
		_rolling.play()
	_apply_skating()


## Plays the landing for the current [member surface] ([constant SoundBank.LAND] when its slot
## is empty). Returns false if nothing played.
func play_landing(volume_db: float = 0.0) -> bool:
	var cue := SoundBank.land_cue(surface)
	if bank == null or bank.get_stream(cue) == null:
		cue = SoundBank.LAND
	return play_cue(cue, null, volume_db)


## Starts or stops the rope-reel loop (both grapple hooks pulling the skater in).
func set_reeling(on: bool) -> void:
	reeling = on
	_set_loop(_reel, SoundBank.GRAPPLE_REEL, REEL_LEVEL if on else 0.0)


## Starts or stops the rocket boost loop.
func set_rocket(on: bool) -> void:
	rocket_active = on
	_set_loop(_rocket, SoundBank.ROCKET, ROCKET_LEVEL if on else 0.0)


## Starts or stops the hospital heart monitor (scaled by [member ambience_level]).
func set_heart_monitor(on: bool) -> void:
	heart_monitor_active = on
	_apply_ambience()


## The combo multiplier changed. A rise plays the combo-gain hit, pitched lower and with more
## sub-bass the higher it goes (see [ComboAudioMapping]); a fall or reset is silent.
func on_combo_changed(multiplier: float) -> void:
	var rose := multiplier > combo_multiplier
	combo_multiplier = multiplier
	if not rose:
		return
	combo_pitch = ComboAudioMapping.pitch_scale(multiplier)
	combo_gains += 1
	play_cue(SoundBank.COMBO_GAIN, null, 0.0, combo_pitch)
	var sub_db := ComboAudioMapping.sub_layer_db(multiplier)
	if sub_db > ComboAudioMapping.SILENT_DB:
		play_cue(SoundBank.COMBO_SUB, null, sub_db)


## Lowers hospital and wind ambience by [param amount] (0 = full, 1 = silent) over
## [param fade_time] seconds. [code]duck_ambience(0.0)[/code] restores it.
func duck_ambience(amount: float, fade_time: float = 0.0) -> void:
	var target := 1.0 - clampf(amount, 0.0, 1.0)
	if _ambience_tween != null:
		_ambience_tween.kill()
	if fade_time <= 0.0 or not is_inside_tree():
		ambience_level = target
		return
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(self, "ambience_level", target, fade_time)


## Starts [param speaker] talking. Calling it again for each line keeps the voice in its loop
## rather than restarting it. Returns false for an unknown speaker (with a warning) or one
## whose loop slot is empty (silently: nothing plays).
func start_voice(speaker: StringName) -> bool:
	var voice := voice_player(speaker)
	if voice == null:
		_reject("no voice for speaker '%s'" % speaker)
		return false
	return voice.start()


## Ends [param speaker]'s voice with its outro; an empty id ends every voice.
## Cuts every one-shot cue still ringing in the pool (loops and voices are untouched).
func stop_one_shots() -> void:
	if _pool != null:
		_pool.stop_all()


func stop_voice(speaker: StringName = &"") -> void:
	for id: StringName in _voices:
		if speaker == &"" or speaker == id:
			_voices[id].stop_talking()


## Sets [param speaker]'s voice loudness (0 to 1), over [param fade_time] seconds if given.
## The doctor fades out as the light grows and God starts to talk.
func set_voice_level(speaker: StringName, level: float, fade_time: float = 0.0) -> void:
	var voice := voice_player(speaker)
	if voice == null:
		_reject("no voice for speaker '%s'" % speaker)
		return
	var target := clampf(level, 0.0, 1.0)
	_kill_fade(voice)
	if fade_time <= 0.0 or not is_inside_tree():
		voice.level = target
		return
	_fades[voice] = create_tween()
	_fades[voice].tween_property(voice, "level", target, fade_time)


## The player for [param speaker]'s voice, with its segments loaded; null for an unknown one.
func voice_player(speaker: StringName) -> SustainedVoice:
	var voice: SustainedVoice = _voices.get(speaker)
	if voice != null and voice.loop_segment == null:
		voice.intro = bank.get_stream(SoundBank.voice_cue(speaker, SoundBank.SEGMENT_INTRO))
		voice.loop_segment = bank.get_stream(SoundBank.voice_cue(speaker, SoundBank.SEGMENT_LOOP))
		voice.outro = bank.get_stream(SoundBank.voice_cue(speaker, SoundBank.SEGMENT_OUTRO))
	return voice


## Plays [param stream] on the Music bus, crossfading from the current track over
## [param fade_time] seconds.
func play_music(stream: AudioStream, fade_time: float = 0.0) -> void:
	if stream == null:
		stop_music(fade_time)
		return
	var outgoing := _music_players[_music_index]
	_music_index = (_music_index + 1) % _music_players.size()
	var incoming := _music_players[_music_index]
	incoming.stream = stream
	incoming.play()
	music_playing = true
	_fade(incoming, SILENT_DB, 0.0, fade_time)
	if outgoing.playing:
		_fade(outgoing, outgoing.volume_db, SILENT_DB, fade_time, true)


## Silences every gameplay loop (rolling, grind, reel, rocket, heart monitor), ends the voices with
## their outros and restores the ambience level. Music is left playing. The game flow calls
## this on every screen swap so nothing from one screen plays on into the next.
func stop_all() -> void:
	speed = 0.0
	grounded = true
	grinding = false
	if _wind == null:
		return  # Not ready yet: nothing has been built, so nothing can be playing.
	_wind.set_speed(0.0)
	surface_blend = 1.0
	_apply_skating()
	set_rocket(false)
	set_reeling(false)
	set_heart_monitor(false)
	stop_voice()
	duck_ambience(0.0)


## Fades the current track out over [param fade_time] seconds.
func stop_music(fade_time: float = 0.0) -> void:
	music_playing = false
	for player: AudioStreamPlayer in _music_players:
		if player.playing:
			_fade(player, player.volume_db, SILENT_DB, fade_time, true)


func _load_default_bank() -> SoundBank:
	if ResourceLoader.exists(BANK_PATH):
		var loaded := load(BANK_PATH) as SoundBank
		if loaded != null:
			return loaded
	return SoundBank.new()


func _build_loops() -> void:
	var loops := Node.new()
	loops.name = "Loops"
	add_child(loops)
	_rolling = _make_player(loops, "Rolling", BUS_SFX)
	_rolling_out = _make_player(loops, "RollingOut", BUS_SFX)
	_reel = _make_player(loops, "GrappleReel", BUS_SFX)
	_grind = _make_player(loops, "Grind", BUS_SFX)
	_rocket = _make_player(loops, "Rocket", BUS_SFX)
	_heart = _make_player(loops, "HeartMonitor", BUS_SFX)


func _build_voices() -> void:
	var holder := Node.new()
	holder.name = "Voices"
	add_child(holder)
	for speaker: StringName in SoundBank.VOICE_SPEAKERS:
		var voice := SustainedVoice.new()
		voice.name = VOICE_NODE_NAMES.get(speaker, String(speaker))
		voice.bus = BUS_SFX
		holder.add_child(voice)
		_voices[speaker] = voice


func _build_music() -> void:
	var holder := Node.new()
	holder.name = "Music"
	add_child(holder)
	for node_name: String in ["MusicA", "MusicB"]:
		_music_players.append(_make_player(holder, node_name, BUS_MUSIC))


static func _make_player(parent: Node, node_name: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus
	player.volume_db = SILENT_DB
	parent.add_child(player)
	return player


func _apply_skating() -> void:
	var amount := clampf(speed / ROLL_FULL_SPEED, 0.0, 1.0)
	var rolling := grounded and not grinding and speed > ROLL_MIN_SPEED
	rolling_level = amount if rolling else 0.0
	grind_level = lerpf(GRIND_MIN_LEVEL, 1.0, amount) if grinding else 0.0
	_set_loop(_rolling, rolling_cue, rolling_level * surface_blend)
	_rolling.pitch_scale = lerpf(ROLL_MIN_PITCH, ROLL_MAX_PITCH, amount)
	_apply_rolling_out()
	_set_loop(_grind, SoundBank.GRIND, grind_level)
	_grind.pitch_scale = lerpf(GRIND_MIN_PITCH, GRIND_MAX_PITCH, amount)


## The fading-out loop of a surface crossfade: the rest of the level, then stopped.
func _apply_rolling_out() -> void:
	var level := rolling_level * (1.0 - surface_blend)
	if level <= 0.0 or _rolling_out.stream == null:
		_rolling_out.volume_db = SILENT_DB
		if _rolling_out.playing:
			_rolling_out.stop()
		return
	_rolling_out.volume_db = maxf(linear_to_db(level), SILENT_DB)
	_rolling_out.pitch_scale = _rolling.pitch_scale


func _surface_rolling_cue() -> StringName:
	var cue := SoundBank.rolling_cue(surface)
	if bank == null or bank.get_stream(cue) == null:
		return SoundBank.ROLLING
	return cue


func _apply_ambience() -> void:
	if _wind != null:
		_wind.level = ambience_level
	if _heart != null:
		_set_loop(_heart, SoundBank.HEART_MONITOR,
			HEART_LEVEL * ambience_level if heart_monitor_active else 0.0)


## Plays [param player] at [param level] (0 to 1), loading [param cue] on first use; level 0
## or an empty slot stops it.
func _set_loop(player: AudioStreamPlayer, cue: StringName, level: float) -> void:
	if player.stream == null and level > 0.0:
		player.stream = bank.get_stream(cue)
	if level <= 0.0 or player.stream == null:
		player.volume_db = SILENT_DB
		if player.playing:
			player.stop()
		return
	player.volume_db = maxf(linear_to_db(level), SILENT_DB)
	if not player.playing:
		player.play()


## Fades [param player] between two levels, replacing any fade already running on it, so a
## stale fade-out can never stop a track that has since started fading back in.
func _fade(player: AudioStreamPlayer, from_db: float, to_db: float, fade_time: float,
		stop_after: bool = false) -> void:
	_kill_fade(player)
	if fade_time <= 0.0 or not is_inside_tree():
		player.volume_db = to_db
		if stop_after:
			player.stop()
		return
	player.volume_db = from_db
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, fade_time)
	if stop_after:
		tween.tween_callback(player.stop)
	_fades[player] = tween


func _kill_fade(target: Node) -> void:
	var running: Tween = _fades.get(target)
	if running != null:
		running.kill()
	_fades.erase(target)


func _reject(reason: String) -> void:
	rejected_requests += 1
	push_warning("AudioDirector: %s" % reason)
