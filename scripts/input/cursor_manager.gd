extends Node

const CURSOR_TEXTURES: Dictionary = {
	&"default": preload("res://assets/ui/cursors/cursor_default.png"),
	&"gather_wood": preload("res://assets/ui/cursors/cursor_gather_wood.png"),
	&"gather_gold": preload("res://assets/ui/cursors/cursor_gather_gold.png"),
	&"gather_food": preload("res://assets/ui/cursors/cursor_gather_food.png"),
	&"build": preload("res://assets/ui/cursors/cursor_build.png"),
	&"build_forbidden": preload("res://assets/ui/cursors/cursor_build_forbidden.png"),
	&"attack": preload("res://assets/ui/cursors/cursor_attack.png"),
}
const HOTSPOT := Vector2(2.0, 2.0)
const IDLE_REFRESH_SECONDS := 0.1

var _selection_manager: Node
var _current_action: StringName = &""
var _last_mouse_position := Vector2.INF
var _idle_refresh_elapsed := 0.0


func setup(selection_manager: Node) -> void:
	_selection_manager = selection_manager
	_refresh_cursor(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# UI buttons use POINTING_HAND; keep the same medieval arrow over the HUD.
	Input.set_custom_mouse_cursor(
		CURSOR_TEXTURES[&"default"],
		Input.CURSOR_POINTING_HAND,
		HOTSPOT
	)
	_apply_action(&"default")


func _process(delta: float) -> void:
	var mouse_position := get_viewport().get_mouse_position()
	if mouse_position != _last_mouse_position:
		_last_mouse_position = mouse_position
		_idle_refresh_elapsed = 0.0
		_refresh_cursor()
		return
	_idle_refresh_elapsed += delta
	if _idle_refresh_elapsed >= IDLE_REFRESH_SECONDS:
		_idle_refresh_elapsed = 0.0
		_refresh_cursor()


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func _refresh_cursor(force: bool = false) -> void:
	var action: StringName = &"default"
	if _selection_manager != null and _selection_manager.has_method("get_cursor_action_at"):
		action = _selection_manager.call(
			"get_cursor_action_at",
			get_viewport().get_mouse_position()
		)
	if force or action != _current_action:
		_apply_action(action)


func _apply_action(action: StringName) -> void:
	if not CURSOR_TEXTURES.has(action):
		action = &"default"
	_current_action = action
	Input.set_custom_mouse_cursor(CURSOR_TEXTURES[action], Input.CURSOR_ARROW, HOTSPOT)
