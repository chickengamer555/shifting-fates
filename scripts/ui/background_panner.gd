class_name BackgroundPanner
extends Control
## Slowly pans across a list of images, cross-fading from each one to the next.
##
## Each image is shown for [member seconds_per_image]; during the last [member fade_seconds]
## the next one fades in over it. Images are drawn a little larger than this control and slide
## sideways, alternating direction. With no images the dark [code]Placeholder[/code] child shows.

## The pictures to show, e.g. screenshots of the levels. Empty shows the placeholder.
@export var images: Array[Texture2D] = []:
	set(value):
		images = value
		if is_node_ready():
			_restart()
## How long each image is the main one, including its fade out.
@export_range(0.1, 60.0, 0.1, "suffix:s") var seconds_per_image: float = 8.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var fade_seconds: float = 1.5
## Extra size the images are drawn at, as a fraction of this control; the pan travels it.
@export_range(0.0, 0.5, 0.01) var pan_fraction: float = 0.08

## How many times the next image has taken over since the images were set.
var transitions: int = 0
## Index in [member images] of the main image.
var current_index: int = 0

## Seconds since the main image took over.
var _elapsed: float = 0.0

@onready var _placeholder: Control = $Placeholder
@onready var _front: TextureRect = $Front
@onready var _back: TextureRect = $Back


func _ready() -> void:
	clip_contents = true
	_restart()


func _process(delta: float) -> void:
	if images.is_empty():
		return
	_elapsed += delta
	var fade := minf(fade_seconds, seconds_per_image)
	if _elapsed >= seconds_per_image:
		_elapsed -= seconds_per_image
		current_index = _next_index()
		transitions += 1
		_front.texture = images[current_index]
	var fade_start := seconds_per_image - fade
	var incoming := _elapsed > fade_start and fade > 0.0
	_back.visible = incoming
	var life := seconds_per_image + fade
	_place(_front, (_elapsed + fade) / life, current_index)
	if incoming:
		var next := _next_index()
		_back.texture = images[next]
		_back.modulate.a = (_elapsed - fade_start) / fade
		_place(_back, (_elapsed - fade_start) / life, next)


func _restart() -> void:
	transitions = 0
	current_index = 0
	_elapsed = 0.0
	var has_images := not images.is_empty()
	_placeholder.visible = not has_images
	_front.visible = has_images
	_back.visible = false
	_front.texture = images[0] if has_images else null


func _next_index() -> int:
	return (current_index + 1) % images.size()


## Sizes [param rect] to cover this control plus the pan margin and slides it by
## [param progress] (0 to 1); odd images slide the other way.
func _place(rect: TextureRect, progress: float, index: int) -> void:
	var margin := size * pan_fraction
	rect.size = size + margin
	var t := clampf(progress, 0.0, 1.0)
	if index % 2 == 1:
		t = 1.0 - t
	rect.position = Vector2(-margin.x * t, -margin.y * 0.5)
