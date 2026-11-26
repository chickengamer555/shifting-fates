extends Node
## Debug-build hotkeys that work in every scene.
##
## F1 ([code]toggle_test_hub[/code]) opens the developer [TestHub]: from anywhere else it
## replaces the running scene with the hub; inside the hub it returns to the hub list.
## Release builds ignore it. No [code]class_name[/code]: autoloads are reached by name.

const TEST_HUB_PATH := "res://scenes/dev/test_hub.tscn"
const TOGGLE_ACTION := &"toggle_test_hub"


func _ready() -> void:
	# Also while a pause menu has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event.is_action_pressed(TOGGLE_ACTION):
		return
	get_viewport().set_input_as_handled()
	open_test_hub()


## Shows the test hub list, loading the hub scene first when it is not the running scene.
func open_test_hub() -> void:
	var tree := get_tree()
	var hub := tree.current_scene as TestHub
	if hub != null:
		hub.show_hub()
		return
	tree.paused = false
	tree.change_scene_to_file(TEST_HUB_PATH)
