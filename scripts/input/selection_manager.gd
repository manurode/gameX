extends Node

const DRAG_THRESHOLD := 6.0

var selected_units: Array[Node] = []

var _drag_start_screen: Vector2
var _drag_current_screen: Vector2
var _is_dragging: bool = false
var _drag_started: bool = false

@onready var selection_box: Control = get_node_or_null("/root/Main/HUD/SelectionBox")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_started:
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_move_selected_units(_screen_to_world(event.position))
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_drag_start_screen = event.position
		_drag_current_screen = event.position
		_drag_started = true
		_is_dragging = false
		_update_selection_box()
		return

	if not _drag_started:
		return

	_drag_started = false
	_drag_current_screen = event.position
	_hide_selection_box()

	if _is_dragging:
		_select_units_in_box(
			_screen_rect_to_world_rect(_get_screen_drag_rect()),
			event.shift_pressed
		)
	else:
		_select_unit_at(_screen_to_world(event.position), event.shift_pressed)

	_is_dragging = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_drag_current_screen = event.position
	if not _is_dragging and _drag_start_screen.distance_to(_drag_current_screen) >= DRAG_THRESHOLD:
		_is_dragging = true
	_update_selection_box()

func _move_selected_units(world_point: Vector2) -> void:
	if selected_units.is_empty():
		return

	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("move_to"):
			unit.call("move_to", world_point)

func _select_unit_at(world_point: Vector2, add_to_selection: bool) -> void:
	var closest_unit: Node = null
	var closest_distance: float = INF

	for unit in get_tree().get_nodes_in_group("units"):
		if not _is_selectable_unit(unit):
			continue
		if not unit.call("contains_world_point", world_point):
			continue

		var unit_node := unit as Node2D
		var distance: float = unit_node.global_position.distance_to(world_point)
		if distance < closest_distance:
			closest_distance = distance
			closest_unit = unit

	if closest_unit == null:
		if not add_to_selection:
			_clear_selection()
		return

	if add_to_selection:
		if closest_unit.get("is_selected"):
			closest_unit.call("deselect")
			selected_units.erase(closest_unit)
		else:
			closest_unit.call("select")
			selected_units.append(closest_unit)
	else:
		_clear_selection()
		closest_unit.call("select")
		selected_units.append(closest_unit)

func _select_units_in_box(world_rect: Rect2, add_to_selection: bool = false) -> void:
	if not add_to_selection:
		_clear_selection()

	for unit in get_tree().get_nodes_in_group("units"):
		if not _is_selectable_unit(unit):
			continue
		if not unit.call("intersects_world_rect", world_rect):
			continue
		if add_to_selection and unit.get("is_selected"):
			continue
		unit.call("select")
		if not selected_units.has(unit):
			selected_units.append(unit)

func _clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.call("deselect")
	selected_units.clear()

func _is_selectable_unit(unit: Node) -> bool:
	return unit is Node2D and unit.has_method("contains_world_point")

func _screen_to_world(screen_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_point

func _screen_rect_to_world_rect(screen_rect: Rect2) -> Rect2:
	var top_left := _screen_to_world(screen_rect.position)
	var bottom_right := _screen_to_world(screen_rect.position + screen_rect.size)
	return Rect2(top_left, bottom_right - top_left)

func _get_screen_drag_rect() -> Rect2:
	var start := _drag_start_screen
	var end := _drag_current_screen
	return Rect2(
		Vector2(minf(start.x, end.x), minf(start.y, end.y)),
		Vector2(absf(end.x - start.x), absf(end.y - start.y))
	)

func _update_selection_box() -> void:
	if selection_box == null or not _is_dragging:
		return

	var drag_rect := _get_screen_drag_rect()
	selection_box.visible = true
	selection_box.position = drag_rect.position
	selection_box.size = drag_rect.size

func _hide_selection_box() -> void:
	if selection_box != null:
		selection_box.visible = false
