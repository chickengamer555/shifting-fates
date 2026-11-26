extends CanvasLayer
## Full-screen post effects drawn above everything else: currently the CRT filter.
##
## One autoload, so the filter covers every screen (menus, levels, dialogue, fades, the test
## hub) exactly once. It follows a Settings node: the [code]Settings[/code] autoload unless
## [member settings] is set before this enters the tree. Toggling or changing the intensity
## in Settings applies live. No [code]class_name[/code]: autoloads are reached by name.

const SETTINGS_SCRIPT := preload("res://autoload/settings.gd")
const CRT_SHADER := preload("res://scenes/ui/shaders/crt.gdshader")
## Above the screen fade (layer 128) and every menu.
const TOP_LAYER := 1000
const INTENSITY_PARAM := &"intensity"

## The preferences followed. Null at ready means the [code]Settings[/code] autoload.
var settings: SETTINGS_SCRIPT = null
## True while the CRT filter is drawn.
var crt_visible: bool:
	get:
		return _crt.visible
## The intensity the CRT shader is using now.
var crt_intensity: float:
	get:
		return float((_crt.material as ShaderMaterial).get_shader_parameter(INTENSITY_PARAM))

var _crt: ColorRect = null


func _init() -> void:
	layer = TOP_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crt = ColorRect.new()
	_crt.name = "Crt"
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = CRT_SHADER
	_crt.material = material
	add_child(_crt)


func _ready() -> void:
	set_meta("verify_unit", "ScreenEffects")
	if settings == null:
		settings = Settings
	settings.changed.connect(_on_settings_changed)
	apply()


## Shows or hides the CRT filter and sets its strength from [member settings].
func apply() -> void:
	_crt.visible = settings.crt_enabled and settings.crt_intensity > 0.0
	(_crt.material as ShaderMaterial).set_shader_parameter(
		INTENSITY_PARAM, settings.crt_intensity)


func _on_settings_changed() -> void:
	apply()
