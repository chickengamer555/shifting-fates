extends Node
## Developer preview of the dialogue look: shows [member stage] (level art or a whole level)
## and steps its dialogue on a timer, so it can be watched or rendered without input.
##
## With [member box_path] empty the preview adds its own [DialogueBox] and plays
## [member lines]; otherwise it steps the stage's box at [member box_path].

## One entry per line: [code]speaker|text[/code], e.g. [code]god|Hello my child[/code].
const FIELD_SEPARATOR := "|"
## advance() finishes the typing line, the next call shows the following line.
const ADVANCES_PER_LINE := 2
const BOX_SCENE := preload("res://scenes/ui/dialogue_box.tscn")

@export var stage: PackedScene = null
## Box inside [member stage] to step; empty adds a box and plays [member lines].
@export var box_path: NodePath = ^""
@export var lines: PackedStringArray = []
## Seconds each line stays before the next.
@export var seconds_per_line: float = 3.0
## Lines skipped straight away (to look at a later line).
@export var skip_lines: int = 0

var _box: DialogueBox = null
var _left: float = 0.0


func _ready() -> void:
	var shown := stage.instantiate() if stage != null else null
	if shown != null:
		add_child(shown)
	if box_path.is_empty() or shown == null:
		var layer := CanvasLayer.new()
		add_child(layer)
		_box = BOX_SCENE.instantiate() as DialogueBox
		layer.add_child(_box)
		_box.play(_sequence())
	else:
		_box = shown.get_node(box_path) as DialogueBox
	for _i: int in range(skip_lines * ADVANCES_PER_LINE):
		_box.advance()
	_left = seconds_per_line


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = seconds_per_line
	for _i: int in range(ADVANCES_PER_LINE):
		_box.advance()


func _sequence() -> DialogueSequence:
	var sequence := DialogueSequence.new()
	for entry: String in lines:
		var fields := entry.split(FIELD_SEPARATOR, true, 1)
		var line := DialogueLine.new()
		line.speaker = StringName(fields[0])
		line.text = fields[1] if fields.size() > 1 else ""
		sequence.lines.append(line)
	return sequence
