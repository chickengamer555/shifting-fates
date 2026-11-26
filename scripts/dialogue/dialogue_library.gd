class_name DialogueLibrary
extends RefCounted
## Loads the authored [DialogueSequence] files and checks them for authoring mistakes.

const DEFAULT_DIRECTORY := "res://data/dialogue"
const SEQUENCE_EXTENSIONS: PackedStringArray = ["tres", "res"]


## Every sequence in [param directory], keyed by its [member DialogueSequence.id].
## Uses [method ResourceLoader.list_directory], so it also works in exported builds.
static func load_directory(directory: String = DEFAULT_DIRECTORY) -> Dictionary:
	var found := {}
	for entry: String in ResourceLoader.list_directory(directory):
		if not SEQUENCE_EXTENSIONS.has(entry.get_extension()):
			continue
		var sequence := load(directory.path_join(entry)) as DialogueSequence
		if sequence != null:
			found[sequence.id] = sequence
	return found


## Human-readable problems with [param sequence]; empty when it is fine to play.
static func validate(sequence: DialogueSequence) -> PackedStringArray:
	var problems: PackedStringArray = []
	if sequence.id == &"":
		problems.append("sequence %s has no id" % sequence.resource_path)
	if sequence.lines.is_empty():
		problems.append("sequence '%s' has no lines" % sequence.id)
	for index: int in sequence.lines.size():
		var line := sequence.lines[index]
		if line == null:
			problems.append("'%s' line %d is empty" % [sequence.id, index])
			continue
		if line.text.strip_edges().is_empty():
			problems.append("'%s' line %d has no text" % [sequence.id, index])
		if not DialogueSpeakers.is_valid(line.speaker):
			problems.append("'%s' line %d has unknown speaker '%s'" % [
				sequence.id, index, line.speaker])
	return problems
