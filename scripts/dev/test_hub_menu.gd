class_name TestHubMenu
extends Control
## The test hub's list: one row per scene, a button and a short note. Pressing a row emits
## [signal entry_picked]; the [TestHub] decides what to do. Set [member entries] before the
## menu enters the tree, or call [method show_entries] later.

## The player picked the scene at [param path].
signal entry_picked(path: String)

## Rows to show, as [constant TestHub.ENTRIES] dictionaries.
var entries: Array[Dictionary] = []

@onready var _list: VBoxContainer = %List


func _ready() -> void:
	set_meta("verify_unit", "TestHubMenu")
	show_entries(entries)


## Rebuilds the list from [param rows] and focuses the first button.
func show_entries(rows: Array[Dictionary]) -> void:
	entries = rows
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		_list.add_child(_make_row(row))
	if _list.get_child_count() > 0:
		var first := _list.get_child(0).get_child(0) as Button
		first.grab_focus.call_deferred()


func _make_row(row: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	var button := Button.new()
	button.text = row[TestHub.KEY_TITLE]
	button.custom_minimum_size.x = _list.custom_minimum_size.x * 0.4
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_row_pressed.bind(String(row[TestHub.KEY_PATH])))
	box.add_child(button)
	var note := Label.new()
	note.text = row[TestHub.KEY_NOTE]
	note.theme_type_variation = &"HubNote"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(note)
	return box


func _on_row_pressed(path: String) -> void:
	entry_picked.emit(path)
