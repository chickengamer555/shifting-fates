class_name MouseCursor
extends RefCounted
## Captures and frees the mouse for gameplay, in one place.
##
## [member requested_mode] remembers the last mode asked for. It matches
## [member Input.mouse_mode] on a desktop; display servers without a mouse (headless) ignore
## the request, so it is also the value to check in tests. Static only, never instantiate.

## The mouse mode most recently asked for through [method capture] or [method release].
static var requested_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


## Hides the cursor and locks it to the window for mouse look.
static func capture() -> void:
	requested_mode = Input.MOUSE_MODE_CAPTURED
	# Godot skips a capture request when it already reports CAPTURED, even if the first grab
	# was refused (window not focused yet, e.g. the editor's Game tab). VISIBLE first forces
	# a fresh grab.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Shows the cursor and lets it move freely (menus, painting).
static func release() -> void:
	requested_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## True when the game last asked for a captured mouse.
static func is_captured() -> bool:
	return requested_mode == Input.MOUSE_MODE_CAPTURED
