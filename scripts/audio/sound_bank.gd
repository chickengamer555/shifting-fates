class_name SoundBank
extends Resource
## Every sound the game plays, as one named slot per cue. Drop a real file into a slot to use it.
##
## An empty slot plays a placeholder built by [ProceduralSounds] (see [method placeholder]),
## made once on first use and kept. Cue ids are the slot property names, so
## [code]get_stream(SoundBank.DASH)[/code] reads [member dash]. Loop slots should hold
## streams with looping turned on in their import settings. Voices come in three segments per
## speaker (intro, loop, outro), named [code]<speaker>_voice_<segment>[/code]; see
## [method voice_cue]. A missing intro or outro is skipped.

const DASH := &"dash"
const GRAPPLE_FIRE := &"grapple_fire"
const GRAPPLE_ATTACH := &"grapple_attach"
const COMBO_GAIN := &"combo_gain"
const COMBO_SUB := &"combo_sub"
const ROLLING := &"rolling"
const GRIND := &"grind"
const ROCKET := &"rocket"
const WIND_LOW := &"wind_low"
const WIND_MID := &"wind_mid"
const WIND_HIGH := &"wind_high"
const HEART_MONITOR := &"heart_monitor"
const GOD_VOICE_INTRO := &"god_voice_intro"
const GOD_VOICE_LOOP := &"god_voice_loop"
const GOD_VOICE_OUTRO := &"god_voice_outro"
const DOCTOR_VOICE_INTRO := &"doctor_voice_intro"
const DOCTOR_VOICE_LOOP := &"doctor_voice_loop"
const DOCTOR_VOICE_OUTRO := &"doctor_voice_outro"

## Speakers that have voice slots. Ids match [DialogueSpeakers].
const SPEAKER_GOD := &"god"
const SPEAKER_DOCTOR := &"doctor"
const VOICE_SPEAKERS: Array[StringName] = [SPEAKER_GOD, SPEAKER_DOCTOR]
const SEGMENT_INTRO := &"intro"
const SEGMENT_LOOP := &"loop"
const SEGMENT_OUTRO := &"outro"

## Short sounds fired with [method AudioDirector.play_cue].
const ONE_SHOTS: Array[StringName] = [DASH, GRAPPLE_FIRE, GRAPPLE_ATTACH, COMBO_GAIN, COMBO_SUB]
## Wind layers, quietest (slowest) first.
const WIND_LAYERS: Array[StringName] = [WIND_LOW, WIND_MID, WIND_HIGH]
const ALL_CUES: Array[StringName] = [
	DASH, GRAPPLE_FIRE, GRAPPLE_ATTACH, COMBO_GAIN, COMBO_SUB,
	ROLLING, GRIND, ROCKET, WIND_LOW, WIND_MID, WIND_HIGH, HEART_MONITOR,
	GOD_VOICE_INTRO, GOD_VOICE_LOOP, GOD_VOICE_OUTRO,
	DOCTOR_VOICE_INTRO, DOCTOR_VOICE_LOOP, DOCTOR_VOICE_OUTRO,
]

# Placeholder recipe numbers. Seeds only need to differ per sound and never change.
const WIND_SECONDS := 3.0
const WIND_SMOOTHING: Array[float] = [0.995, 0.98, 0.9]
const WIND_WOBBLE_HZ: Array[float] = [0.35, 0.6, 1.2]
const WIND_WOBBLE_DEPTH := 0.5
const WIND_SEED := 101
const ROLL_SECONDS := 1.5
const ROLL_SMOOTHING := 0.95
const ROLL_CLACK_HZ := 6.0
const ROLL_CLACK_DEPTH := 0.3
const ROLL_SEED := 202
const GRIND_SECONDS := 1.0
const GRIND_SMOOTHING := 0.3
const GRIND_RING_HZ: Array[float] = [1800.0, 2450.0]
const GRIND_RING_GAIN := 0.25
const GRIND_SEED := 303
const ROCKET_SECONDS := 1.5
const ROCKET_SMOOTHING := 0.85
const ROCKET_RUMBLE_HZ := 70.0
const ROCKET_RUMBLE_GAIN := 0.6
const ROCKET_SEED := 404
const HEART_PERIOD := 1.0
const HEART_BEEP_SECONDS := 0.14
const HEART_BEEP_HZ := 1000.0
const HEART_BEEP_DECAY := 0.06
const DASH_SECONDS := 0.4
const DASH_SMOOTHING := 0.6
const DASH_ATTACK := 0.06
const DASH_DECAY := 0.12
const DASH_SEED := 505
const FIRE_SECONDS := 0.25
const FIRE_START_HZ := 1200.0
const FIRE_END_HZ := 300.0
const FIRE_DECAY := 0.1
const ATTACH_SECONDS := 0.15
const ATTACH_HZ := 180.0
const ATTACH_NOISE_GAIN := 0.5
const ATTACH_DECAY := 0.04
const ATTACH_SEED := 606
const COMBO_SECONDS := 0.4
const COMBO_HZ := 660.0
const COMBO_FIFTH := 1.5
const COMBO_DECAY := 0.15
const SUB_SECONDS := 0.6
const SUB_HZ := 55.0
const SUB_ATTACK := 0.01
const SUB_DECAY := 0.25
const GOD_HZ := 110.0
const GOD_HARMONICS := 6
const GOD_VIBRATO_HZ := 0.5
const GOD_VIBRATO_DEPTH := 0.01
const GOD_INTRO_SECONDS := 1.0
const GOD_LOOP_SECONDS := 2.0
const GOD_OUTRO_SECONDS := 1.2
const DOCTOR_SECONDS := 2.4
const DOCTOR_LOW_HZ := 120.0
const DOCTOR_HIGH_HZ := 200.0
const DOCTOR_SYLLABLE := 0.15
const DOCTOR_SEED := 707

@export_group("Skating")
@export var rolling: AudioStream
@export var grind: AudioStream
@export var dash: AudioStream
@export var grapple_fire: AudioStream
@export var grapple_attach: AudioStream
@export var rocket: AudioStream

@export_group("Combo")
@export var combo_gain: AudioStream
## Low layer under [member combo_gain]; louder as the combo climbs.
@export var combo_sub: AudioStream

@export_group("Wind")
@export var wind_low: AudioStream
@export var wind_mid: AudioStream
@export var wind_high: AudioStream

@export_group("Hospital")
@export var heart_monitor: AudioStream

@export_group("Voices")
@export var god_voice_intro: AudioStream
@export var god_voice_loop: AudioStream
@export var god_voice_outro: AudioStream
@export var doctor_voice_intro: AudioStream
@export var doctor_voice_loop: AudioStream
@export var doctor_voice_outro: AudioStream

var _placeholders: Dictionary[StringName, AudioStream] = {}


## True when [param cue] is one of [constant ALL_CUES].
static func is_cue(cue: StringName) -> bool:
	return ALL_CUES.has(cue)


## The cue id of one segment of a speaker's voice, e.g. [code]&"god_voice_loop"[/code].
static func voice_cue(speaker: StringName, segment: StringName) -> StringName:
	return StringName("%s_voice_%s" % [speaker, segment])


## The stream for [param cue]: the authored slot, else its placeholder. Null for an unknown
## cue or a segment with neither (a voice intro or outro left empty).
func get_stream(cue: StringName) -> AudioStream:
	if not is_cue(cue):
		return null
	var authored := get(cue) as AudioStream
	if authored != null:
		return authored
	if not _placeholders.has(cue):
		_placeholders[cue] = placeholder(cue)
	return _placeholders[cue]


## Builds the stand-in sound for [param cue], fresh each call. Null for an unknown cue and for
## the doctor's intro and outro, which have no placeholder (the babble just starts and stops).
static func placeholder(cue: StringName) -> AudioStream:
	match cue:
		DASH:
			return _dash()
		GRAPPLE_FIRE:
			return _grapple_fire()
		GRAPPLE_ATTACH:
			return _grapple_attach()
		COMBO_GAIN:
			return _combo_gain()
		COMBO_SUB:
			return _combo_sub()
		ROLLING:
			return _rolling()
		GRIND:
			return _grind()
		ROCKET:
			return _rocket()
		WIND_LOW, WIND_MID, WIND_HIGH:
			return _wind(WIND_LAYERS.find(cue))
		HEART_MONITOR:
			return _heart_monitor()
		GOD_VOICE_INTRO:
			return _god_voice(GOD_INTRO_SECONDS, true, false)
		GOD_VOICE_LOOP:
			return _god_voice(GOD_LOOP_SECONDS, false, false)
		GOD_VOICE_OUTRO:
			return _god_voice(GOD_OUTRO_SECONDS, false, true)
		DOCTOR_VOICE_LOOP:
			return _doctor_voice()
	return null


static func _loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var seamless := ProceduralSounds.make_seamless(samples)
	ProceduralSounds.normalize(seamless)
	return ProceduralSounds.to_wav(seamless, true)


static func _one_shot(samples: PackedFloat32Array) -> AudioStreamWAV:
	ProceduralSounds.normalize(samples)
	return ProceduralSounds.to_wav(samples)


static func _wind(layer: int) -> AudioStreamWAV:
	var samples := ProceduralSounds.noise(WIND_SECONDS, WIND_SEED + layer, WIND_SMOOTHING[layer])
	ProceduralSounds.wobble(samples, WIND_WOBBLE_HZ[layer], WIND_WOBBLE_DEPTH)
	return _loop(samples)


static func _rolling() -> AudioStreamWAV:
	var samples := ProceduralSounds.noise(ROLL_SECONDS, ROLL_SEED, ROLL_SMOOTHING)
	ProceduralSounds.wobble(samples, ROLL_CLACK_HZ, ROLL_CLACK_DEPTH)
	return _loop(samples)


static func _grind() -> AudioStreamWAV:
	var samples := ProceduralSounds.noise(GRIND_SECONDS, GRIND_SEED, GRIND_SMOOTHING)
	for ring: float in GRIND_RING_HZ:
		ProceduralSounds.mix_into(samples, ProceduralSounds.tone(GRIND_SECONDS, ring),
			GRIND_RING_GAIN)
	return _loop(samples)


static func _rocket() -> AudioStreamWAV:
	var samples := ProceduralSounds.noise(ROCKET_SECONDS, ROCKET_SEED, ROCKET_SMOOTHING)
	ProceduralSounds.normalize(samples)
	ProceduralSounds.mix_into(samples, ProceduralSounds.tone(ROCKET_SECONDS, ROCKET_RUMBLE_HZ),
		ROCKET_RUMBLE_GAIN)
	return _loop(samples)


## One beep at the top of a one-beat loop; the rest is silence, so the seam is clean.
static func _heart_monitor() -> AudioStreamWAV:
	var beep := ProceduralSounds.tone(HEART_BEEP_SECONDS, HEART_BEEP_HZ)
	ProceduralSounds.envelope(beep, 0.0, HEART_BEEP_DECAY)
	ProceduralSounds.normalize(beep)
	var samples := PackedFloat32Array()
	samples.resize(ProceduralSounds.sample_count(HEART_PERIOD))
	ProceduralSounds.mix_into(samples, beep, 1.0)
	return ProceduralSounds.to_wav(samples, true)


static func _dash() -> AudioStreamWAV:
	var samples := ProceduralSounds.noise(DASH_SECONDS, DASH_SEED, DASH_SMOOTHING)
	ProceduralSounds.envelope(samples, DASH_ATTACK, DASH_DECAY)
	return _one_shot(samples)


static func _grapple_fire() -> AudioStreamWAV:
	var samples := ProceduralSounds.tone(FIRE_SECONDS, FIRE_START_HZ, FIRE_END_HZ)
	ProceduralSounds.envelope(samples, 0.0, FIRE_DECAY)
	return _one_shot(samples)


static func _grapple_attach() -> AudioStreamWAV:
	var samples := ProceduralSounds.tone(ATTACH_SECONDS, ATTACH_HZ)
	ProceduralSounds.mix_into(samples, ProceduralSounds.noise(ATTACH_SECONDS, ATTACH_SEED, 0.0),
		ATTACH_NOISE_GAIN)
	ProceduralSounds.envelope(samples, 0.0, ATTACH_DECAY)
	return _one_shot(samples)


static func _combo_gain() -> AudioStreamWAV:
	var samples := ProceduralSounds.tone(COMBO_SECONDS, COMBO_HZ)
	var fifth := ProceduralSounds.tone(COMBO_SECONDS, COMBO_HZ * COMBO_FIFTH)
	ProceduralSounds.mix_into(samples, fifth, 1.0)
	ProceduralSounds.envelope(samples, 0.0, COMBO_DECAY)
	return _one_shot(samples)


static func _combo_sub() -> AudioStreamWAV:
	var samples := ProceduralSounds.tone(SUB_SECONDS, SUB_HZ)
	ProceduralSounds.envelope(samples, SUB_ATTACK, SUB_DECAY)
	return _one_shot(samples)


## The god's held tone. The intro swells in and the outro dies away; the loop is steady.
static func _god_voice(seconds: float, swell_in: bool, die_out: bool) -> AudioStreamWAV:
	var samples := ProceduralSounds.drone(
		seconds, GOD_HZ, GOD_HARMONICS, GOD_VIBRATO_HZ, GOD_VIBRATO_DEPTH)
	if not swell_in and not die_out:
		return _loop(samples)
	ProceduralSounds.fade(samples, seconds if swell_in else 0.0, seconds if die_out else 0.0)
	return _one_shot(samples)


static func _doctor_voice() -> AudioStreamWAV:
	var samples := ProceduralSounds.babble(
		DOCTOR_SECONDS, DOCTOR_SEED, DOCTOR_LOW_HZ, DOCTOR_HIGH_HZ, DOCTOR_SYLLABLE)
	return _loop(samples)
