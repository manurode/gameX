extends Node

signal selection_changed(selected_units: Array)
signal building_selection_changed(selected_building: Building)
signal resource_selection_changed(selected_resource: ResourceNode)

const DRAG_THRESHOLD := 6.0
const UNIT_COLLISION_MASK := 2
const GARRISON_ATTACK_PICK_RADIUS := 80.0
const CURSOR_DEFAULT: StringName = &"default"
const CURSOR_GATHER_WOOD: StringName = &"gather_wood"
const CURSOR_GATHER_GOLD: StringName = &"gather_gold"
const CURSOR_GATHER_FOOD: StringName = &"gather_food"
const CURSOR_BUILD: StringName = &"build"
const CURSOR_ATTACK: StringName = &"attack"

var selected_units: Array[Unit] = []
var selected_building: Building = null
var selected_resource: ResourceNode = null

var _drag_start_screen: Vector2
var _drag_current_screen: Vector2
var _is_dragging: bool = false
var _drag_started: bool = false
var _buildings_container: Node2D
var _resource_manager: ResourceManager

@onready var selection_box: Control = get_node_or_null("/root/Main/Layout/WorldView/SubViewport/HUD/SelectionBox")


func setup(buildings_container: Node2D, resource_manager: ResourceManager) -> void:
	_buildings_container = buildings_container
	_resource_manager = resource_manager


func get_cursor_action_at(screen_point: Vector2) -> StringName:
	if _is_placement_mode_active() or _is_pointer_over_ui(screen_point):
		return CURSOR_DEFAULT

	var world_point := _screen_to_world(screen_point)
	if _can_selected_garrison_attack_at(world_point):
		return CURSOR_ATTACK

	if _pick_attackable_unit_at(world_point) != null:
		return CURSOR_ATTACK

	var building := _pick_building_at(world_point)
	if building != null and _can_build_or_repair(building):
		return CURSOR_BUILD

	var resource_node := _pick_resource_node_at(world_point)
	if resource_node != null and _can_gather_resource(resource_node):
		match resource_node.get_resource_key():
			"wood":
				return CURSOR_GATHER_WOOD
			"gold":
				return CURSOR_GATHER_GOLD
			"food":
				return CURSOR_GATHER_FOOD

	if building != null and _can_attack_building(building):
		return CURSOR_ATTACK
	return CURSOR_DEFAULT


func _ready() -> void:
	if selection_box == null:
		selection_box = get_node_or_null("/root/Main/Layout/WorldView/SubViewport/HUD/SelectionBox")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if _is_pointer_over_ui(mouse_event.position):
			return
	if _is_placement_mode_active() and event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT or mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_started:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_E:
			_exit_garrison_for_selected()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_U:
			_try_upgrade_building_at_cursor()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_Q:
			_expand_selection_to_squads()
			get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var world_point := _screen_to_world(event.position)
		if _try_garrison_building_command(world_point):
			get_viewport().set_input_as_handled()
			return

		var target_unit := _pick_attackable_unit_at(world_point)
		if target_unit != null:
			_attack_selected_units(target_unit)
			get_viewport().set_input_as_handled()
			return

		# Prefer build/repair over gather when the click hits a relevant building,
		# so resource pick radii don't swallow construction/repair orders.
		var target_building := _pick_building_at(world_point)
		if target_building != null and _should_prefer_building_command(target_building):
			_handle_building_command(target_building, world_point, event.shift_pressed)
			get_viewport().set_input_as_handled()
			return

		if _try_gather_resource_command(world_point):
			get_viewport().set_input_as_handled()
			return

		if target_building != null:
			_handle_building_command(target_building, world_point, event.shift_pressed)
			get_viewport().set_input_as_handled()
			return

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

	var add_to_selection := event.shift_pressed or event.ctrl_pressed
	if _is_dragging:
		_select_units_in_box(
			_screen_rect_to_world_rect(_get_screen_drag_rect()),
			add_to_selection
		)
	else:
		_select_unit_at(_screen_to_world(event.position), add_to_selection)

	_is_dragging = false
	get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_drag_current_screen = event.position
	if not _is_dragging and _drag_start_screen.distance_to(_drag_current_screen) >= DRAG_THRESHOLD:
		_is_dragging = true
	_update_selection_box()


func _handle_building_command(building: Building, world_point: Vector2, force_attack: bool = false) -> void:
	if building.building_state == Building.BuildingState.CONSTRUCTING:
		_assign_builders_to_construction(building)
		return

	for unit in selected_units:
		if not is_instance_valid(unit):
			continue

		if unit.garrisoned_building == building:
			continue

		var should_attack := (
			force_attack
			or building.is_hostile_to(unit)
			or building.has_enemy_garrison(unit)
		)
		if should_attack and building.building_state == Building.BuildingState.ACTIVE:
			if unit.can_attack:
				unit.attack_target_building_node(building)
			continue

		if unit.can_attack:
			if building.building_state == Building.BuildingState.ACTIVE:
				unit.move_to(building.get_approach_point(unit.global_position))
			else:
				unit.move_to(world_point)
		elif unit.can_build and building.can_be_repaired() and _can_afford_repair(building):
			unit.assign_repair(building)
		elif unit.can_build:
			if building.building_state == Building.BuildingState.CONSTRUCTING:
				unit.assign_construction(building)
			else:
				unit.move_to(building.get_approach_point(unit.global_position))
		else:
			unit.move_to(world_point)


func _should_prefer_building_command(building: Building) -> bool:
	if building.building_state == Building.BuildingState.CONSTRUCTING:
		for unit in selected_units:
			if is_instance_valid(unit) and unit.can_build:
				return true
		return false
	if not building.can_be_repaired():
		return false
	if not _can_afford_repair(building):
		return false
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_build and not unit.can_attack:
			return true
	return false


func _try_gather_resource_command(world_point: Vector2) -> bool:
	var resource_node := _pick_resource_node_at(world_point)
	if resource_node == null:
		return false

	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager == null or not job_manager is JobManager:
		return false

	var gatherers: Array = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit.is_civilian and unit.can_gather:
			gatherers.append(unit)

	if gatherers.is_empty():
		return false

	return (job_manager as JobManager).assign_villagers_to_resource(gatherers, resource_node)


func _pick_resource_node_at(world_point: Vector2) -> ResourceNode:
	var best_node: ResourceNode = null
	var best_depth := -INF
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not node is ResourceNode:
			continue
		var resource_node := node as ResourceNode
		if not resource_node.has_resources():
			continue
		if not resource_node.contains_point(world_point):
			continue
		# Prefer the front-most resource in y-sort (higher sort key draws in front).
		var depth := DepthSort.sort_y(resource_node)
		if depth > best_depth:
			best_depth = depth
			best_node = resource_node
	return best_node


func _assign_builders_to_construction(site: Building) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_build:
			unit.assign_construction(site)


func _try_upgrade_building_at_cursor() -> void:
	if _resource_manager == null:
		return
	var world_point := _screen_to_world(get_viewport().get_mouse_position())
	var building := _pick_building_at(world_point)
	if building == null or not building.can_be_upgraded():
		return
	building.try_upgrade(_resource_manager)


func _exit_garrison_for_selected() -> void:
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.exit_all_garrison()
		return
	var by_building: Dictionary = {}
	for unit in selected_units:
		if not is_instance_valid(unit) or unit.garrisoned_building == null:
			continue
		var building: Building = unit.garrisoned_building
		if not by_building.has(building):
			by_building[building] = []
		by_building[building].append(unit)
	for building in by_building:
		if is_instance_valid(building):
			building.exit_garrison_units(by_building[building])


func _move_selected_units(world_point: Vector2) -> void:
	Unit.assign_move_destinations(selected_units, world_point)


func _notify_selection_changed() -> void:
	selection_changed.emit(selected_units)


func _expand_selection_to_squads() -> void:
	var squad_ids: Dictionary = {}
	for unit in selected_units:
		if is_instance_valid(unit):
			var squad_id: String = unit.get_meta("squad_id", "")
			if not squad_id.is_empty():
				squad_ids[squad_id] = true
	if squad_ids.is_empty():
		return
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if unit.team_id != Team.PLAYER:
			continue
		var squad_id: String = unit.get_meta("squad_id", "")
		if squad_ids.has(squad_id) and not selected_units.has(unit):
			unit.select()
			selected_units.append(unit)
	_notify_selection_changed()


func _attack_selected_units(target: Unit) -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.can_attack:
			unit.attack_target_unit(target)


func remove_unit_from_selection(unit: Unit) -> void:
	if selected_units.has(unit):
		if is_instance_valid(unit):
			unit.deselect()
		selected_units.erase(unit)
		_notify_selection_changed()


func _select_unit_at(world_point: Vector2, add_to_selection: bool) -> void:
	var garrisoned_building := _pick_building_for_selection(world_point)
	if garrisoned_building != null and garrisoned_building.is_garrison_occupied():
		_select_building_at(garrisoned_building, add_to_selection)
		return

	var picked_unit := _pick_unit_at(world_point)

	if picked_unit == null:
		var picked_building := _pick_building_for_selection(world_point)
		if picked_building != null:
			_select_building_at(picked_building, add_to_selection)
			return
		var picked_resource := _pick_resource_node_at(world_point)
		if picked_resource != null and not picked_resource.is_infinite:
			_select_resource_at(picked_resource, add_to_selection)
			return
		if not add_to_selection:
			_clear_selection()
		return

	_deselect_building()
	_deselect_resource()

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

	_notify_selection_changed()


func _select_units_in_box(world_rect: Rect2, add_to_selection: bool = false) -> void:
	if not add_to_selection:
		_clear_selection(false)
	else:
		_deselect_building(false)
		_deselect_resource(false)

	for unit in _pick_units_in_rect(world_rect):
		if add_to_selection and unit.is_selected:
			continue
		unit.select()
		if not selected_units.has(unit):
			selected_units.append(unit)

	_notify_selection_changed()


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
	if selected_units.is_empty():
		return null

	for selected in selected_units:
		if is_instance_valid(selected) and selected.can_attack and selected.is_hostile_to(unit):
			return unit

	return null


func _can_build_or_repair(building: Building) -> bool:
	if building.building_state == Building.BuildingState.CONSTRUCTING:
		for unit in selected_units:
			if is_instance_valid(unit) and unit.can_build:
				return true
		return false
	if not building.can_be_repaired():
		return false
	if not _can_afford_repair(building):
		return false
	for unit in selected_units:
		# Building commands prioritize combat-capable units as attackers.
		if is_instance_valid(unit) and unit.can_build and not unit.can_attack:
			return true
	return false


func _can_afford_repair(building: Building) -> bool:
	return (
		building.repair_paid
		or (
			_resource_manager != null
			and _resource_manager.can_afford(building.get_repair_cost())
		)
	)


func _can_gather_resource(resource_node: ResourceNode) -> bool:
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if not job_manager is JobManager:
		return false
	return (job_manager as JobManager).can_assign_villagers_to_resource(
		selected_units,
		resource_node
	)


func _can_attack_building(building: Building) -> bool:
	if building.building_state != Building.BuildingState.ACTIVE:
		return false
	for unit in selected_units:
		if not is_instance_valid(unit) or not unit.can_attack:
			continue
		if building.is_hostile_to(unit) or building.has_enemy_garrison(unit):
			return true
	return false


func _can_selected_garrison_attack_at(world_point: Vector2) -> bool:
	if selected_building == null or not is_instance_valid(selected_building):
		return false
	if not selected_building.can_garrison or not selected_building.is_garrison_occupied():
		return false
	if _pick_hostile_unit_for_building(world_point, selected_building) != null:
		return true
	var target := _pick_building_at(world_point)
	if target == null or target == selected_building:
		return false
	return _can_garrison_attack_building(selected_building, target)


func _can_garrison_attack_building(attacker: Building, target: Building) -> bool:
	if (
		attacker.get_attack_point().distance_to(target.get_attack_point())
		> attacker.get_garrison_attack_range()
	):
		return false
	if Team.are_hostile(attacker.team_id, target.team_id):
		return true
	for unit in target.garrisoned_units:
		if is_instance_valid(unit) and Team.are_hostile(unit.team_id, attacker.team_id):
			return true
	return false


func select_building(building: Building) -> void:
	_select_building_at(building, false)


func _select_building_at(building: Building, add_to_selection: bool) -> void:
	if not add_to_selection:
		_clear_selection(false)
	else:
		_clear_unit_selection(false)
		_deselect_resource(false)

	if selected_building == building and not add_to_selection:
		return

	if selected_building != null and is_instance_valid(selected_building):
		selected_building.deselect()

	selected_building = building
	building.select()
	building_selection_changed.emit(selected_building)


func _select_resource_at(resource: ResourceNode, add_to_selection: bool) -> void:
	if not add_to_selection:
		_clear_selection(false)
	else:
		_clear_unit_selection(false)
		_deselect_building(false)

	if selected_resource == resource and not add_to_selection:
		return

	if selected_resource != null and is_instance_valid(selected_resource):
		if selected_resource.depleted.is_connected(_on_selected_resource_depleted):
			selected_resource.depleted.disconnect(_on_selected_resource_depleted)
		selected_resource.deselect()

	selected_resource = resource
	resource.select()
	if not resource.depleted.is_connected(_on_selected_resource_depleted):
		resource.depleted.connect(_on_selected_resource_depleted)
	resource_selection_changed.emit(selected_resource)


func _deselect_building(notify: bool = true) -> void:
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.deselect()
	selected_building = null
	if notify:
		building_selection_changed.emit(null)


func _deselect_resource(notify: bool = true) -> void:
	if selected_resource != null and is_instance_valid(selected_resource):
		if selected_resource.depleted.is_connected(_on_selected_resource_depleted):
			selected_resource.depleted.disconnect(_on_selected_resource_depleted)
		selected_resource.deselect()
	selected_resource = null
	if notify:
		resource_selection_changed.emit(null)


func _on_selected_resource_depleted() -> void:
	_deselect_resource()


func _clear_unit_selection(notify: bool = true) -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	if notify:
		_notify_selection_changed()


func _pick_building_for_selection(world_point: Vector2) -> Building:
	var best_building: Building = null
	var best_depth: float = INF
	for node in get_tree().get_nodes_in_group("selectable_buildings"):
		if node is Building:
			var building := node as Building
			if building.building_state == Building.BuildingState.DESTROYED:
				continue
			if not building.contains_world_point(world_point):
				continue
			var depth := DepthSort.sort_y(building)
			if depth < best_depth:
				best_depth = depth
				best_building = building
	return best_building


func _pick_building_at(world_point: Vector2) -> Building:
	var best_building: Building = null
	var best_depth: float = INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building:
			var building := node as Building
			if building.building_state == Building.BuildingState.DESTROYED:
				continue
			if not building.contains_command_point(world_point):
				continue
			var depth := DepthSort.sort_y(building)
			if depth < best_depth:
				best_depth = depth
				best_building = building
	return best_building


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
			if unit._is_dying or unit.garrisoned_building != null or not unit.contains_world_point(world_point):
				continue
			var depth := DepthSort.sort_y(unit)
			if depth < best_depth:
				best_depth = depth
				best_unit = unit

	return best_unit


func _pick_units_in_rect(world_rect: Rect2) -> Array[Unit]:
	var picked: Array[Unit] = []

	for node in get_tree().get_nodes_in_group("selectable_units"):
		if node is Unit:
			var unit := node as Unit
			if unit.garrisoned_building != null:
				continue
			if unit.intersects_world_rect(world_rect):
				picked.append(unit)

	return picked


func _try_garrison_building_command(world_point: Vector2) -> bool:
	if selected_building == null or not is_instance_valid(selected_building):
		return false
	if not selected_building.can_garrison or not selected_building.is_garrison_occupied():
		return false

	var hostile_unit := _pick_hostile_unit_for_building(world_point, selected_building)
	if hostile_unit != null:
		selected_building.order_garrison_attack_unit(hostile_unit)
		return true

	var target_building := _pick_building_at(world_point)
	if target_building != null and target_building != selected_building:
		if _can_garrison_attack_building(selected_building, target_building):
			selected_building.order_garrison_attack_building(target_building)
			return true

	return false


func _pick_hostile_unit_for_building(world_point: Vector2, building: Building) -> Unit:
	var direct := _pick_unit_in_group(world_point, "units")
	var attack_range := building.get_garrison_attack_range()
	var origin := building.get_attack_point()
	if (
		direct != null
		and not direct._is_dying
		and Team.are_hostile(building.team_id, direct.team_id)
		and origin.distance_to(direct.get_sprite_center()) <= attack_range
	):
		return direct

	var best_unit: Unit = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if (
			unit._is_dying
			or unit.garrisoned_building != null
			or not Team.are_hostile(building.team_id, unit.team_id)
		):
			continue
		var click_distance := unit.get_sprite_center().distance_to(world_point)
		if click_distance > GARRISON_ATTACK_PICK_RADIUS:
			continue
		if origin.distance_to(unit.get_sprite_center()) > attack_range:
			continue
		if click_distance < best_distance:
			best_distance = click_distance
			best_unit = unit
	return best_unit


func _order_garrison_attack(building: Building, target_unit: Unit, target_building: Building) -> void:
	if target_unit != null:
		building.order_garrison_attack_unit(target_unit)
	elif target_building != null:
		building.order_garrison_attack_building(target_building)


func _clear_selection(notify: bool = true) -> void:
	_clear_unit_selection(false)
	_deselect_building(false)
	_deselect_resource(false)
	if notify:
		_notify_selection_changed()
		building_selection_changed.emit(null)
		resource_selection_changed.emit(null)


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


func _is_build_mode_active() -> bool:
	var build_manager := get_parent().get_node_or_null("BuildManager")
	return build_manager != null and build_manager.build_mode_active


func _is_spawn_mode_active() -> bool:
	var spawn_manager := get_parent().get_node_or_null("UnitSpawnManager")
	return spawn_manager != null and spawn_manager.spawn_mode_active


func _is_placement_mode_active() -> bool:
	return _is_build_mode_active() or _is_spawn_mode_active()


func _is_pointer_over_ui(screen_pos: Vector2) -> bool:
	var hovered_control := get_viewport().gui_get_hovered_control()
	if (
		hovered_control != null
		and hovered_control.visible
		and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE
	):
		return true

	var hud := get_node_or_null("/root/Main/Layout/WorldView/SubViewport/HUD")
	if hud == null:
		return false

	var cycle_panel := hud.get_node_or_null("TopLeft/MarginContainer/CyclePanel")
	if cycle_panel is Control and (cycle_panel as Control).get_global_rect().has_point(screen_pos):
		return true

	var top_left := hud.get_node_or_null("TopLeft/MarginContainer")
	if top_left is Control and (top_left as Control).get_global_rect().has_point(screen_pos):
		return true

	var hub := get_node_or_null("/root/Main/Layout/HubMargin/GameHub")
	if hub == null:
		hub = get_node_or_null("/root/Main/Layout/GameHub")
	if hub is Control:
		var root_mouse := get_tree().root.get_mouse_position()
		if (hub as Control).get_global_rect().has_point(root_mouse):
			return true

	return false
