extends Node
## Developer preview of the main menu: shows it with one screen open and one wish lit, so
## each look can be rendered without input.

enum Screen { MAIN, SETTINGS, CREDITS }

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

@export var screen: Screen = Screen.MAIN
## Wish shown hovered / focused (0 = new game ... 3 = credits).
@export_range(0, 3) var lit_wish: int = 0
@export var has_save: bool = true


func _ready() -> void:
	var menu := MENU_SCENE.instantiate() as MainMenu
	menu.has_save = has_save
	add_child(menu)
	var wishes: Array[BaseButton] = [
		menu.get_node("%NewGameButton") as BaseButton,
		menu.get_node("%LoadButton") as BaseButton,
		menu.get_node("%SettingsButton") as BaseButton,
		menu.get_node("%CreditsButton") as BaseButton,
	]
	match screen:
		Screen.SETTINGS:
			wishes[2].pressed.emit()
		Screen.CREDITS:
			wishes[3].pressed.emit()
		_:
			wishes[lit_wish].grab_focus.call_deferred()
