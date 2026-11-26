class_name SustainedVoice
extends AudioStreamPlayer
## A voice that holds its middle: intro once, then the loop segment for as long as the speaker
## talks, then the outro. Asking it to start again while talking keeps the loop going instead
## of restarting the intro, so line after line of dialogue sounds like one sustained voice.
##
## Phases run IDLE -> INTRO -> LOOP -> OUTRO -> IDLE; a missing intro or outro is skipped.
## Segment time is counted from frame deltas (times [member AudioStreamPlayer.pitch_scale]),
## like a loop-point music player, so the logic does not depend on the audio driver.
## The loop segment is replayed from the top each pass unless the stream loops by itself.

## The voice moved to another phase.
signal phase_changed(phase: Phase)

enum Phase { IDLE, INTRO, LOOP, OUTRO }

## Level used for a silent voice, in dB.
const SILENT_DB := -80.0

## Played once when the voice starts. Optional.
@export var intro: AudioStream
## Held for as long as the voice is talking.
@export var loop_segment: AudioStream
## Played once when the voice stops. Optional.
@export var outro: AudioStream
## When true, [method _process] advances the segment clock; turn off to call
## [method advance] yourself.
@export var auto_advance: bool = true

## 0 to 1 loudness of the voice (the doctor fades out as the light grows).
var level: float = 1.0:
	set(value):
		level = clampf(value, 0.0, 1.0)
		volume_db = linear_to_db(level) if level > 0.0 else SILENT_DB
var phase: Phase = Phase.IDLE
## Seconds into the current segment.
var segment_time: float = 0.0
## Times the intro has played since this node was made.
var intro_plays: int = 0
## Full passes of the loop segment since it last began.
var loops: int = 0


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


## True while the intro or the loop is playing.
func is_talking() -> bool:
	return phase == Phase.INTRO or phase == Phase.LOOP


## Starts talking. While already talking this does nothing: the loop is held, not restarted.
## During the outro it goes straight back into the loop. Returns false without a loop segment.
func start() -> bool:
	if loop_segment == null:
		return false
	if is_talking():
		return true
	if phase == Phase.OUTRO or intro == null:
		_enter(Phase.LOOP)
	else:
		_enter(Phase.INTRO)
	return true


## Stops talking: plays the outro (or goes idle without one). Does nothing when not talking.
func stop_talking() -> void:
	if not is_talking():
		return
	_enter(Phase.OUTRO if outro != null else Phase.IDLE)


## Moves the segment clock on by [param delta] seconds and changes segment at each end.
## Streams of no fixed length (generators) never end on their own.
func advance(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	segment_time += delta * pitch_scale
	var length := _segment_stream().get_length()
	while length > 0.0 and segment_time >= length and phase != Phase.IDLE:
		segment_time -= length
		match phase:
			Phase.INTRO:
				_enter(Phase.LOOP, segment_time)
			Phase.LOOP:
				loops += 1
				if not _loops_itself(loop_segment):
					play(segment_time)
			Phase.OUTRO:
				_enter(Phase.IDLE)
		length = _segment_stream().get_length() if phase != Phase.IDLE else 0.0


func _enter(next: Phase, offset: float = 0.0) -> void:
	phase = next
	segment_time = offset
	match next:
		Phase.INTRO:
			intro_plays += 1
		Phase.LOOP:
			loops = 0
	if next == Phase.IDLE:
		stop()
	else:
		stream = _segment_stream()
		play(offset)
	phase_changed.emit(phase)


func _segment_stream() -> AudioStream:
	match phase:
		Phase.INTRO:
			return intro
		Phase.OUTRO:
			return outro
	return loop_segment


static func _loops_itself(segment: AudioStream) -> bool:
	if segment is AudioStreamWAV:
		return (segment as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	var flag: Variant = segment.get("loop")
	return flag is bool and flag
