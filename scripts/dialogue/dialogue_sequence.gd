class_name DialogueSequence
extends Resource
## An ordered conversation, played line by line by a [DialogueRunner].

## Stable name used to look the sequence up, e.g. [code]&"opening"[/code].
@export var id: StringName = &""
@export var lines: Array[DialogueLine] = []
