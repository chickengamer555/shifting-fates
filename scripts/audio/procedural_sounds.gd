class_name ProceduralSounds
extends RefCounted
## Builds placeholder sounds in code, so the game has audio before real files are dropped in.
##
## Every sound is a 16-bit mono [AudioStreamWAV] made from a fixed seed: the same call always
## gives the same bytes. Building happens in two steps: a generator returns raw samples
## ([PackedFloat32Array], -1 to 1), shapers change them in place, and [method to_wav] packs
## them. Loops are cross-faded end into start so they wrap without a click.
## Static only. [method SoundBank.placeholder] picks the recipe for each cue.

## Sample rate of every generated sound. Low on purpose: placeholders, not final audio.
const MIX_RATE := 22050
## Largest value of a signed 16-bit sample.
const SAMPLE_MAX := 32767.0
const BYTES_PER_SAMPLE := 2
## Peak level after [method normalize], leaving headroom for layered sounds.
const DEFAULT_PEAK := 0.6
## Length of the end-into-start blend that makes a loop seamless, in seconds.
const LOOP_BLEND_SECONDS := 0.1
## Fewest samples any generator returns, so a zero duration still makes a valid stream.
const MIN_SAMPLES := 1


## How many samples [param seconds] of audio needs at [constant MIX_RATE].
static func sample_count(seconds: float) -> int:
	return maxi(int(round(seconds * MIX_RATE)), MIN_SAMPLES)


## White noise from [param noise_seed], low-passed by [param smoothing] (0 = raw hiss,
## close to 1 = a dull rumble). Not normalized: call [method normalize] after.
static func noise(seconds: float, noise_seed: int, smoothing: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var keep := clampf(smoothing, 0.0, 0.9999)
	var out := PackedFloat32Array()
	out.resize(sample_count(seconds))
	var state := 0.0
	for i: int in out.size():
		state = lerpf(rng.randf_range(-1.0, 1.0), state, keep)
		out[i] = state
	return out


## A sine at [param frequency] Hz, gliding to [param end_frequency] when that is positive.
static func tone(seconds: float, frequency: float,
		end_frequency: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(sample_count(seconds))
	var target := end_frequency if end_frequency > 0.0 else frequency
	var phase := 0.0
	for i: int in out.size():
		var t := float(i) / out.size()
		phase += TAU * lerpf(frequency, target, t) / MIX_RATE
		out[i] = sin(phase)
	return out


## A buzzy voice-like tone: [param harmonics] stacked partials of [param frequency] with a slow
## vibrato of [param vibrato_depth] (fraction of the pitch) at [param vibrato_rate] Hz.
static func drone(seconds: float, frequency: float, harmonics: int, vibrato_rate: float,
		vibrato_depth: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(sample_count(seconds))
	var phase := 0.0
	for i: int in out.size():
		var time := float(i) / MIX_RATE
		var pitch := frequency * (1.0 + vibrato_depth * sin(TAU * vibrato_rate * time))
		phase += TAU * pitch / MIX_RATE
		var value := 0.0
		for partial: int in range(1, harmonics + 1):
			value += sin(phase * partial) / partial
		out[i] = value
	return out


## Speech-like babble: syllables of [param syllable_seconds], each a tone at a pitch picked
## from [param low_hz] to [param high_hz] by [param babble_seed], swelling in and out.
static func babble(seconds: float, babble_seed: int, low_hz: float, high_hz: float,
		syllable_seconds: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = babble_seed
	var out := PackedFloat32Array()
	out.resize(sample_count(seconds))
	var syllable_length := sample_count(syllable_seconds)
	var pitch := low_hz
	var phase := 0.0
	for i: int in out.size():
		var in_syllable := i % syllable_length
		if in_syllable == 0:
			pitch = rng.randf_range(low_hz, high_hz)
		phase += TAU * pitch / MIX_RATE
		var swell := sin(PI * float(in_syllable) / syllable_length)
		out[i] = (sin(phase) + 0.5 * sin(phase * 2.0)) * swell * swell
	return out


## Adds [param layer] times [param gain] into [param samples], up to the shorter length.
static func mix_into(samples: PackedFloat32Array, layer: PackedFloat32Array, gain: float) -> void:
	for i: int in mini(samples.size(), layer.size()):
		samples[i] += layer[i] * gain


## Scales [param samples] so the loudest one sits at [param peak]. Silence is left alone.
static func normalize(samples: PackedFloat32Array, peak: float = DEFAULT_PEAK) -> void:
	var loudest := 0.0
	for value: float in samples:
		loudest = maxf(loudest, absf(value))
	if loudest <= 0.0:
		return
	var scale := peak / loudest
	for i: int in samples.size():
		samples[i] *= scale


## Shapes [param samples] with a linear fade in over [param attack] seconds and an
## exponential fall with time constant [param decay] seconds (0 = no decay).
static func envelope(samples: PackedFloat32Array, attack: float, decay: float) -> void:
	var attack_samples := float(sample_count(attack))
	for i: int in samples.size():
		var gain := minf(float(i) / attack_samples, 1.0) if attack > 0.0 else 1.0
		if decay > 0.0:
			gain *= exp(-float(i) / (decay * MIX_RATE))
		samples[i] *= gain


## Fades [param samples] in over [param fade_in] and out over [param fade_out] seconds.
static func fade(samples: PackedFloat32Array, fade_in: float, fade_out: float) -> void:
	var in_samples := sample_count(fade_in)
	var out_samples := sample_count(fade_out)
	var size := samples.size()
	for i: int in size:
		var gain := 1.0
		if fade_in > 0.0:
			gain = minf(gain, float(i) / in_samples)
		if fade_out > 0.0:
			gain = minf(gain, float(size - 1 - i) / out_samples)
		samples[i] *= clampf(gain, 0.0, 1.0)


## Swells the level by [param depth] (0..1) at about [param rate] Hz, rounded to a whole number
## of cycles over the sound so a loop wobbles the same way every pass.
static func wobble(samples: PackedFloat32Array, rate: float, depth: float) -> void:
	var seconds := float(samples.size()) / MIX_RATE
	var cycles := maxf(round(rate * seconds), 1.0)
	for i: int in samples.size():
		var t := float(i) / samples.size()
		samples[i] *= 1.0 - depth * 0.5 * (1.0 - cos(TAU * cycles * t))


## Blends the tail of [param samples] into its head and drops the tail, so playing the result
## on repeat has no seam. The sound gets [constant LOOP_BLEND_SECONDS] shorter.
static func make_seamless(samples: PackedFloat32Array) -> PackedFloat32Array:
	var blend := mini(sample_count(LOOP_BLEND_SECONDS), samples.size() >> 1)
	var length := samples.size() - blend
	var out := samples.slice(0, length)
	for i: int in blend:
		var t := float(i) / blend
		out[i] = samples[i] * t + samples[length + i] * (1.0 - t)
	return out


## Packs [param samples] into a 16-bit mono stream; [param loop] repeats the whole sound.
static func to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * BYTES_PER_SAMPLE)
	for i: int in samples.size():
		var value := int(round(clampf(samples[i], -1.0, 1.0) * SAMPLE_MAX))
		data.encode_s16(i * BYTES_PER_SAMPLE, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## Loudest sample of a 16-bit mono [param stream], 0 to 1. 0 for null or empty streams.
static func peak_of(stream: AudioStreamWAV) -> float:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return 0.0
	var data := stream.data
	var loudest := 0
	for offset: int in range(0, data.size() - 1, BYTES_PER_SAMPLE):
		loudest = maxi(loudest, absi(data.decode_s16(offset)))
	return loudest / SAMPLE_MAX
