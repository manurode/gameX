extends Camera2D

const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.5
const PAN_SPEED := 650.0
const ZOOM_STEP := 0.08
const EDGE_PAN_MARGIN := 24
const EDGE_PAN_SPEED := 550.0
const START_ZOOM := 0.85

var map_bounds := Rect2(0.0, 0.0, 1800.0, 900.0)
var _mouse_in_window := false


func _ready() -> void:
	make_current()
	zoom = Vector2(START_ZOOM, START_ZOOM)


func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
	position = bounds.get_center()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_in_window = true
		NOTIFICATION_WM_MOUSE_EXIT:
			_mouse_in_window = false


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_pan(delta)
	_clamp_to_map()


func _handle_keyboard_pan(delta: float) -> void:
	var direction := Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_up", "camera_pan_down")
	if direction == Vector2.ZERO:
		return

	position += direction.normalized() * PAN_SPEED * delta / zoom.x


func _handle_edge_pan(delta: float) -> void:
	if not _mouse_in_window or not get_viewport().get_window().has_focus():
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var direction := Vector2.ZERO

	if mouse_pos.x <= EDGE_PAN_MARGIN:
		direction.x -= 1.0
	elif mouse_pos.x >= viewport_size.x - EDGE_PAN_MARGIN:
		direction.x += 1.0

	if mouse_pos.y <= EDGE_PAN_MARGIN:
		direction.y -= 1.0
	elif mouse_pos.y >= viewport_size.y - EDGE_PAN_MARGIN:
		direction.y += 1.0

	if direction != Vector2.ZERO:
		position += direction.normalized() * EDGE_PAN_SPEED * delta / zoom.x


func _clamp_to_map() -> void:
	var half_view := get_viewport().get_visible_rect().size / (2.0 * zoom)

	var min_x := map_bounds.position.x + half_view.x
	var max_x := map_bounds.end.x - half_view.x
	if min_x <= max_x:
		position.x = clampf(position.x, min_x, max_x)

	var min_y := map_bounds.position.y + half_view.y
	var max_y := map_bounds.end.y - half_view.y
	if min_y <= max_y:
		position.y = clampf(position.y, min_y, max_y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return

		var delta_zoom := 0.0
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			delta_zoom = ZOOM_STEP
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			delta_zoom = -ZOOM_STEP

		if delta_zoom != 0.0:
			var new_zoom := clampf(zoom.x + delta_zoom, MIN_ZOOM, MAX_ZOOM)
			zoom = Vector2(new_zoom, new_zoom)
			_clamp_to_map()
