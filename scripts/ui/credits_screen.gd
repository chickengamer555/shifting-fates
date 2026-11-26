class_name CreditsScreen
extends Control
## Scrollable credits with a Back button. Edit [member credits_text] in the inspector.

## The player left the screen. The owner decides what to show next.
signal closed

const DEFAULT_CREDITS := """Shifting Fates

Game by chickengamer555

Built with Godot Engine
godotengine.org

Fonts
(credit the fonts used here)

Sounds
(credit the sounds and music used here)

Thank you for playing."""

@export_multiline var credits_text: String = DEFAULT_CREDITS:
	set(value):
		credits_text = value
		if is_node_ready():
			_credits_label.text = credits_text

@onready var _credits_label: Label = %CreditsText
@onready var _scroll: ScrollContainer = %Scroll
@onready var _back_button: BaseButton = %BackButton


func _ready() -> void:
	set_meta("verify_unit", "CreditsScreen")
	_credits_label.text = credits_text
	_back_button.pressed.connect(_on_back_button_pressed)
	visibility_changed.connect(_on_visibility_changed)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _on_back_button_pressed() -> void:
	closed.emit()


func _on_visibility_changed() -> void:
	if visible:
		_scroll.scroll_vertical = 0
		_back_button.grab_focus.call_deferred()
