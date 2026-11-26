class_name GodOrb
extends Control
## A god on screen: an oscillating ball of light drawn by [code]god_orb.gdshader[/code].
##
## The light breathes slowly while the god is silent and quickens and brightens while it
## speaks ([member speaking]); every [method pulse] (one per word revealed) gives a brief kick,
## so the light follows the text. [member presence] fades the orb in and out, and
## [member flare] adds extra brightness for flashes. The orb sits at the centre of its rect;
## set [member Control.pivot_offset] to the centre to scale it about the light.

const SHADER := preload("res://scenes/ui/shaders/god_orb.gdshader")
## Brightness of a present, silent orb before breathing.
const CALM_LEVEL := 0.55
## Extra brightness while speaking.
const SPEAK_LEVEL := 0.3
## Extra brightness right after a [method pulse].
const PULSE_LEVEL := 0.22
## Durations are clamped to at least this, so a zero setting never divides by zero.
const MIN_SECONDS := 0.001

## The god this orb stands for (a [DialogueSpeakers] id).
@export var speaker: StringName = DialogueSpeakers.GOD
@export var tint: Color = Color(1.0, 0.98, 0.92):
	set(value):
		tint = value
		_set_uniform(&"tint", value)
## Target visibility, 0 (gone) to 1 (fully there); fractions give a dim, distant god.
@export_range(0.0, 1.0) var presence: float = 1.0
## Seconds to fade [member presence] in or out.
@export var presence_seconds: float = 1.2
## Breaths per second while silent and while speaking.
@export var calm_hz: float = 0.3
@export var speaking_hz: float = 1.1
## How far a breath swings the brightness while silent and while speaking (fraction).
@export_range(0.0, 1.0) var calm_swing: float = 0.08
@export_range(0.0, 1.0) var speaking_swing: float = 0.14
## Seconds for a [method pulse] kick to fade to a third.
@export var pulse_seconds: float = 0.35
## Seconds to ease in and out of speaking.
@export var speak_ease_seconds: float = 0.4
## Extra brightness on top of everything (flashes, the opening's growing light).
@export var flare: float = 0.0
## Shader seed; neighbouring orbs should differ so they never flicker in step.
@export var seed: float = 0.0:
	set(value):
		seed = value
		_set_uniform(&"seed", value)

## True while this god is talking.
var speaking: bool = false
## Brightness drawn this frame (0 = invisible), including breathing, pulses and flare.
var intensity: float = 0.0
## The breathing swing this frame, -1..1; text can flicker with it.
var breath: float = 0.0

var _shown_presence: float = 0.0
var _speak: float = 0.0
var _kick: float = 0.0
var _phase: float = 0.0
var _material := ShaderMaterial.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	material = _material


func _ready() -> void:
	set_meta("verify_unit", "GodOrb")
	_set_uniform(&"tint", tint)
	_set_uniform(&"seed", seed)
	resized.connect(_on_resized)
	_on_resized()


func _process(delta: float) -> void:
	_shown_presence = move_toward(
		_shown_presence, presence, delta / maxf(presence_seconds, MIN_SECONDS))
	_speak = move_toward(
		_speak, 1.0 if speaking else 0.0, delta / maxf(speak_ease_seconds, MIN_SECONDS))
	_kick *= exp(-delta / maxf(pulse_seconds, MIN_SECONDS))
	_phase = fmod(_phase + TAU * lerpf(calm_hz, speaking_hz, _speak) * delta, TAU)
	breath = sin(_phase)
	_update_intensity()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


## A brief brightening, e.g. as a new word of this god's line appears.
func pulse() -> void:
	_kick = 1.0


## Jumps straight to [member presence] instead of fading (e.g. when a scene starts).
func snap_presence() -> void:
	_shown_presence = presence
	_update_intensity()


func _update_intensity() -> void:
	var swing := lerpf(calm_swing, speaking_swing, _speak)
	var level := CALM_LEVEL + SPEAK_LEVEL * _speak + PULSE_LEVEL * _kick
	intensity = _shown_presence * (level * (1.0 + swing * breath) + flare)
	_set_uniform(&"intensity", intensity)
	_set_uniform(&"speak", _speak)
	visible = intensity > 0.0


func _set_uniform(uniform: StringName, value: Variant) -> void:
	_material.set_shader_parameter(uniform, value)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()
