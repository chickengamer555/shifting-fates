class_name WindAmbience
extends Node
## Whooshing wind that builds with speed: layers that crossfade in as the skater goes faster.
##
## Layer [i] starts at [member start_speeds][i] and fades in over [member fade_span] m/s. Once
## the next layer is fully in, a lower layer holds at [member lower_layer_hold] of its level, so
## the mix brightens without getting thinner. At or below the first start speed every layer is
## silent and stopped. Call [method set_speed] every frame; levels ease toward their targets
## over [member smoothing_time] (0 snaps). [member level] scales everything, for ducking.
## Layer players are children named [code]Layer0[/code] up, created in [method _ready], and
## fetch their stream from [member bank] the first time they become audible.

## Level used for a silent layer, in dB.
const SILENT_DB := -80.0
## Weights at or under this count as silent.
const WEIGHT_EPSILON := 0.0001
const DEFAULT_BUS := &"SFX"

## Where layer streams come from: [member layer_cues][i] is read from it.
@export var bank: SoundBank
## The [SoundBank] cue played by each layer, slowest first.
@export var layer_cues: Array[StringName] = SoundBank.WIND_LAYERS.duplicate()
## Speed (m/s) where each layer begins to fade in, ascending, one per layer.
@export var start_speeds: PackedFloat32Array = PackedFloat32Array([10.0, 16.0, 22.0])
## Speed range (m/s) over which a layer goes from silent to full.
@export var fade_span: float = 6.0
## Share of its level a layer keeps once the layer above it is full.
@export_range(0.0, 1.0) var lower_layer_hold: float = 0.35
## Seconds for a layer to move all the way between silent and full. 0 snaps at once.
@export var smoothing_time: float = 0.4
## When true, [method _process] eases the levels; turn off to call [method advance] yourself.
@export var auto_advance: bool = true
@export var bus: StringName = DEFAULT_BUS

## Overall level, 0 to 1, multiplied into every layer (ducking).
var level: float = 1.0:
	set(value):
		level = clampf(value, 0.0, 1.0)
		_apply_volumes()
## The last speed given to [method set_speed].
var speed: float = 0.0
## Where each layer's weight is heading, 0 to 1.
var target_weights: PackedFloat32Array = PackedFloat32Array()
## Each layer's current weight, 0 to 1.
var weights: PackedFloat32Array = PackedFloat32Array()
## Sum of the current weights: 0 is silent, the layer count is everything at full.
var intensity: float:
	get:
		return _sum(weights)
## Sum of the target weights.
var target_intensity: float:
	get:
		return _sum(target_weights)
## How many layers are audible now.
var active_layers: int:
	get:
		var count := 0
		for weight: float in weights:
			if weight > WEIGHT_EPSILON:
				count += 1
		return count
## Index of the highest audible layer, or -1 when silent.
var highest_layer: int:
	get:
		for i: int in range(weights.size() - 1, -1, -1):
			if weights[i] > WEIGHT_EPSILON:
				return i
		return -1

var _players: Array[AudioStreamPlayer] = []


func _init() -> void:
	set_meta("verify_unit", "WindAmbience")


func _ready() -> void:
	for i: int in start_speeds.size():
		var player := AudioStreamPlayer.new()
		player.name = "Layer%d" % i
		player.bus = bus
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)
	target_weights.resize(start_speeds.size())
	weights.resize(start_speeds.size())


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


## Target weight of every layer at [param at_speed]: layer i rises from 0 to 1 over
## [param span] m/s from [param starts][i], then drops to [param hold] as layer i + 1 rises.
static func layer_targets(at_speed: float, starts: PackedFloat32Array, span: float,
		hold: float) -> PackedFloat32Array:
	var rise := PackedFloat32Array()
	rise.resize(starts.size())
	for i: int in starts.size():
		var into := at_speed - starts[i]
		rise[i] = clampf(into / span, 0.0, 1.0) if span > 0.0 else (1.0 if into > 0.0 else 0.0)
	var out := PackedFloat32Array()
	out.resize(starts.size())
	for i: int in starts.size():
		var next_rise := rise[i + 1] if i + 1 < starts.size() else 0.0
		out[i] = rise[i] * (1.0 - (1.0 - hold) * next_rise)
	return out


## Sets the skater's speed (m/s) and retargets every layer. With no smoothing the levels
## change at once; otherwise [method advance] moves them.
func set_speed(new_speed: float) -> void:
	speed = new_speed if is_finite(new_speed) else 0.0
	target_weights = layer_targets(speed, start_speeds, fade_span, lower_layer_hold)
	if smoothing_time <= 0.0:
		advance(0.0)


## Eases each layer toward its target by [param delta] seconds and applies the volumes.
func advance(delta: float) -> void:
	var step := delta / smoothing_time if smoothing_time > 0.0 else 1.0
	for i: int in weights.size():
		weights[i] = move_toward(weights[i], target_weights[i], step)
	_apply_volumes()


func _apply_volumes() -> void:
	for i: int in _players.size():
		var player := _players[i]
		var gain := weights[i] * level
		if gain <= WEIGHT_EPSILON:
			player.volume_db = SILENT_DB
			if player.playing:
				player.stop()
			continue
		player.volume_db = maxf(linear_to_db(gain), SILENT_DB)
		if not player.playing:
			_start(i)


func _start(layer: int) -> void:
	var player := _players[layer]
	if player.stream == null and bank != null and layer < layer_cues.size():
		player.stream = bank.get_stream(layer_cues[layer])
	if player.stream != null:
		player.play()


static func _sum(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total
