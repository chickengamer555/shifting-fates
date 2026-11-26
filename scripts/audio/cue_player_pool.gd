class_name CuePlayerPool
extends Node
## A fixed set of players for one-shot sounds: [member flat_size] non-positional players named
## [code]Flat0[/code] up and [member spatial_size] positional ones named [code]Spatial0[/code] up.
##
## The players are made once in [method _ready] and never added to or freed afterwards. A
## request takes an idle player; when every one is busy it takes the one handed out longest
## ago, cutting that sound short. Volume and pitch are reset on every hand-out.

const DEFAULT_SIZE := 8
const DEFAULT_BUS := &"SFX"

@export var flat_size: int = DEFAULT_SIZE
@export var spatial_size: int = DEFAULT_SIZE
@export var bus: StringName = DEFAULT_BUS

var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
## Hand-out order, oldest first, so a full pool steals the oldest sound.
var _flat_order: Array[AudioStreamPlayer] = []
var _spatial_order: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	for i: int in flat_size:
		var player := AudioStreamPlayer.new()
		player.name = "Flat%d" % i
		player.bus = bus
		add_child(player)
		_flat.append(player)
	for i: int in spatial_size:
		var player := AudioStreamPlayer3D.new()
		player.name = "Spatial%d" % i
		player.bus = bus
		add_child(player)
		_spatial.append(player)


## Plays [param stream] without position. Returns the player used, or null for an empty pool.
func play_flat(stream: AudioStream, volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer:
	if _flat.is_empty():
		return null
	var player := _take_flat()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	return player


## Plays [param stream] at [param at] in world space. Returns the player used, or null for an
## empty pool.
func play_at(stream: AudioStream, at: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer3D:
	if _spatial.is_empty():
		return null
	var player := _take_spatial()
	player.position = at
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	return player


## Stops every pooled one-shot, flat and positional. Screen swaps leave one-shots alone
## so a menu click can finish; tests use this to start from silence.
func stop_all() -> void:
	for player: AudioStreamPlayer in _flat:
		player.stop()
	for player: AudioStreamPlayer3D in _spatial:
		player.stop()


func _take_flat() -> AudioStreamPlayer:
	var chosen: AudioStreamPlayer = null
	for player: AudioStreamPlayer in _flat:
		if not player.playing:
			chosen = player
			break
	if chosen == null:
		chosen = _flat_order.pop_front()
	_flat_order.erase(chosen)
	_flat_order.append(chosen)
	return chosen


func _take_spatial() -> AudioStreamPlayer3D:
	var chosen: AudioStreamPlayer3D = null
	for player: AudioStreamPlayer3D in _spatial:
		if not player.playing:
			chosen = player
			break
	if chosen == null:
		chosen = _spatial_order.pop_front()
	_spatial_order.erase(chosen)
	_spatial_order.append(chosen)
	return chosen
