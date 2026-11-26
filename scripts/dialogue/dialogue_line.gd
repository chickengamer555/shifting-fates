class_name DialogueLine
extends Resource
## One line of dialogue: who says it, what they say, and an optional story event.

## A speaker id from [DialogueSpeakers], e.g. [code]&"god"[/code].
@export var speaker: StringName = DialogueSpeakers.NARRATION
## The words, revealed by the typewriter.
@export_multiline var text: String = ""
## Forces a box style ([code]god[/code], [code]player[/code], [code]neutral[/code]).
## Empty picks the style from the speaker.
@export var style: StringName = &""
## Fired through [signal DialogueRunner.event_triggered] when this line starts, e.g.
## [code]&"open_player_paint"[/code]. Empty for none.
@export var event: StringName = &""
## Author's note, never shown in game (e.g. "placeholder: rewrite once grinding is final").
@export_multiline var note: String = ""
