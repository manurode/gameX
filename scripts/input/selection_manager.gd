extends Node

const DRAG_THRESHOLD := 6.0
const UNIT_COLLISION_MASK := 2

var selected_units: Array[Unit] = []

var _drag_start_screen: Vector2
var _drag_current_screen: Vector2
var _is_dragging: bool = false
var _drag_started: bool = false

@onready var selection_box: Control = get_node_or_null("/root/Main/HUD/SelectionBox")


func _ready() -> void:
	if selection_box == null:
		selection_box = get_node_or_null("/root/Main/HUD/SelectionBox")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_started:
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var world_point := _screen_to_world(event.position)
		var target_unit := _pick_attackable_unit_at(world_point)
		if target_unit != null:
			_attack_selected_units(target_unit)
		else:
			_move_selected_units(world_point)
		get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_drag_start_screen = event.position
		_drag_current_screen = event.position
		_drag_started = true
		_is_dragging = false
		_update_selection_box()
		get_viewport().set_input_as_handled()
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
	get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_drag_current_screen = event.position
	if not _is_dragging and _drag_start_screen.distance_to(_drag_current_screen) >= DRAG_THRESHOLD:
		_is_dragging = true
	_update_selection_box()

func _move_selected_units(world_point: Vector2) -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.move_to(world_point)


func _attack_selected_units(target: Unit) -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.attack_target_unit(target)


func remove_unit_from_selection(unit: Unit) -> void:
	if selected_units.has(unit):
		if is_instance_valid(unit):
			unit.deselect()
		selected_units.erase(unit)

func _select_unit_at(world_point: Vector2, add_to_selection: bool) -> void:
	var picked_unit := _pick_unit_at(world_point)

	if picked_unit == null:
		if not add_to_selection:
			_clear_selection()
		return

	if add_to_selection:
		if picked_unit.is_selected:
			picked_unit.deselect()
			selected_units.erase(picked_unit)
		else:
			picked_unit.select()
			selected_units.append(picked_unit)
	else:
		_clear_selection()
		picked_unit.select()
		selected_units.append(picked_unit)

func _select_units_in_box(world_rect: Rect2, add_to_selection: bool = false) -> void:
	if not add_to_selection:
		_clear_selection()

	for unit in _pick_units_in_rect(world_rect):
		if add_to_selection and unit.is_selected:
			continue
		unit.select()
		if not selected_units.has(unit):
			selected_units.append(unit)

func _pick_unit_at(world_point: Vector2) -> Unit:
	var unit := _pick_unit_in_group(world_point, "selectable_units")
	if unit != null and unit.is_in_group("selectable_units"):
		return unit
	return null


func _pick_attackable_unit_at(world_point: Vector2) -> Unit:
	var unit := _pick_unit_in_group(world_point, "units")
	if unit == null:
		return null
	for selected in selected_units:
		if selected == unit:
			return null
	return unit


func _pick_unit_in_group(world_point: Vector2, group_name: StringName) -> Unit:
	var space_state := get_viewport().world_2d.direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_point
	params.collision_mask = UNIT_COLLISION_MASK
	params.collide_with_bodies = true
	params.collide_with_areas = false

	for result in space_state.intersect_point(params, 16):
		var collider: Object = result.collider
		if collider is Unit and (collider as Unit).is_in_group(group_name) and not (collider as Unit)._is_dying:
			return collider as Unit

	var best_unit: Unit = null
	var best_depth: float = INF
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Unit:
			var unit := node as Unit
			if unit._is_dying or not unit.contains_world_point(world_point):
				continue
			var depth := unit.global_position.y
			if depth < best_depth:
				best_depth = depth
				best_unit = unit

	return best_unit

func _pick_units_in_rect(world_rect: Rect2) -> Array[Unit]:
	var picked: Array[Unit] = []

	for node in get_tree().get_nodes_in_group("selectable_units"):
		if node is Unit and (node as Unit).intersects_world_rect(world_rect):
			picked.append(node as Unit)

	return picked

func _clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()

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
