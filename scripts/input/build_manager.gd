extends Node2D

signal build_mode_changed(active: bool, type_id: String)

const BUILD_HOTKEYS: Dictionary = {
	KEY_1: "house_small",
	KEY_2: "house_big",
	KEY_3: "lumber_camp",
	KEY_4: "mill",
	KEY_5: "mine",
	KEY_6: "stable",
	KEY_7: "tower",
	KEY_8: "wall",
}

var build_mode_active: bool = false
var selected_building_type: String = "house_small"
var ghost_valid: bool = false

var _ghost_sprite: Sprite2D
var _wall_ghost_container: Node2D
var _wall_ghost_sprites: Array[Sprite2D] = []
var _wall_dragging: bool = false
var _wall_drag_start: Vector2 = Vector2.ZERO
var _ground_layer: TinyTilesMap
var _buildings_container: Node2D
var _resource_manager: ResourceManager
var _selection_manager: Node
var _job_manager: JobManager
var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")


func setup(
	ground_layer: TinyTilesMap,
	buildings_container: Node2D,
	resource_manager: ResourceManager,
	selection_manager: Node,
	job_manager: JobManager = null
) -> void:
	_ground_layer = ground_layer
	_buildings_container = buildings_container
	_resource_manager = resource_manager
	_selection_manager = selection_manager
	_job_manager = job_manager
	_create_ghost()


func _create_ghost() -> void:
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.centered = true
	_ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.55)
	_ghost_sprite.visible = false
	_ghost_sprite.z_index = 50
	add_child(_ghost_sprite)

	_wall_ghost_container = Node2D.new()
	_wall_ghost_container.z_index = 49
	add_child(_wall_ghost_container)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and build_mode_active:
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode in BUILD_HOTKEYS:
			var type_id: String = BUILD_HOTKEYS[key_event.keycode]
			if BuildingDatabase.is_buildable(type_id):
				_start_build_mode(type_id)
				get_viewport().set_input_as_handled()
			return

	if not build_mode_active:
		return

	if selected_building_type == "wall":
		_handle_wall_input(event)
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if _is_pointer_over_ui(mouse_event.position):
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_building(_screen_to_world(mouse_event.position))
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_build_mode()
			get_viewport().set_input_as_handled()


func _handle_wall_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if _is_pointer_over_ui(mouse_event.position):
			return

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos := _snap_wall_position(_screen_to_world(mouse_event.position))
			if mouse_event.pressed:
				_wall_drag_start = world_pos
				_wall_dragging = true
				_update_wall_preview(_wall_drag_start, world_pos)
			else:
				if _wall_dragging:
					_place_wall_line(_wall_drag_start, world_pos)
				_stop_wall_drag()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_stop_wall_drag()
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _wall_dragging:
		var world_pos := _snap_wall_position(_screen_to_world(event.position))
		_update_wall_preview(_wall_drag_start, world_pos)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not build_mode_active:
		_ghost_sprite.visible = false
		_clear_wall_ghosts()
		return

	if selected_building_type == "wall":
		if _wall_dragging:
			_ghost_sprite.visible = false
		else:
			var world_pos := _screen_to_world(get_viewport().get_mouse_position())
			_ghost_sprite.global_position = world_pos
			ghost_valid = _is_valid_placement(world_pos)
			_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.65) if ghost_valid else Color(0.95, 0.35, 0.35, 0.55)
			_ghost_sprite.rotation_degrees = 0.0
			_ghost_sprite.visible = true
		return

	var world_pos := _screen_to_world(get_viewport().get_mouse_position())
	_ghost_sprite.global_position = world_pos
	ghost_valid = _is_valid_placement(world_pos)
	_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.65) if ghost_valid else Color(0.95, 0.35, 0.35, 0.55)
	_ghost_sprite.visible = true


func start_build_mode(type_id: String) -> void:
	_start_build_mode(type_id)


func _start_build_mode(type_id: String) -> void:
	if not BuildingDatabase.is_buildable(type_id):
		return
	_stop_wall_drag()
	selected_building_type = type_id
	build_mode_active = true
	_update_ghost_texture()
	build_mode_changed.emit(true, type_id)


func cancel_build_mode() -> void:
	_cancel_build_mode()


func _cancel_build_mode() -> void:
	_stop_wall_drag()
	build_mode_active = false
	_ghost_sprite.visible = false
	build_mode_changed.emit(false, "")


func _update_ghost_texture() -> void:
	var def := BuildingDatabase.get_definition(selected_building_type)
	if def.is_empty():
		return
	if def.get("procedural", false):
		_ghost_sprite.texture = WallTexture.get_texture()
	else:
		var texture_path: String = def.get("texture", "")
		if not texture_path.is_empty():
			_ghost_sprite.texture = load(texture_path)
	if _ghost_sprite.texture != null:
		_ghost_sprite.offset = Vector2(0.0, -_ghost_sprite.texture.get_height() * 0.5 + 64.0)
		_ghost_sprite.modulate = def.get("tint", Color(0.4, 0.95, 0.55, 0.55))


func _try_place_building(world_pos: Vector2) -> void:
	if not ghost_valid:
		return
	_place_single_building(world_pos, false)


func _place_single_building(world_pos: Vector2, vertical: bool) -> Building:
	var cost := BuildingDatabase.get_cost(selected_building_type)
	if _resource_manager == null or not _resource_manager.spend(cost):
		return null

	var building: Building = _building_scene.instantiate()
	building.configure(selected_building_type, Building.BuildingState.CONSTRUCTING, 0.0)
	if vertical:
		building.set_wall_vertical(true)
	_buildings_container.add_child(building)
	building.global_position = world_pos
	building.construction_completed.connect(_on_building_completed.bind(building))
	if _job_manager != null:
		_job_manager.alert_nearby_builders(building)
	_request_nav_rebuild(building)
	return building


func _place_wall_line(start_pos: Vector2, end_pos: Vector2) -> void:
	var segments := _compute_wall_segments(start_pos, end_pos)
	if segments.is_empty():
		return
	if not _can_afford_wall_line(segments.size()):
		return

	for segment in segments:
		if not _is_valid_wall_segment(segment["pos"], segment["vertical"]):
			return

	var unit_cost := BuildingDatabase.get_cost("wall")
	var total_cost := _multiply_cost(unit_cost, segments.size())
	if _resource_manager == null or not _resource_manager.spend(total_cost):
		return

	for segment in segments:
		_place_single_building(segment["pos"], segment["vertical"])


func _compute_wall_segments(start_pos: Vector2, end_pos: Vector2) -> Array[Dictionary]:
	var spacing := WallTexture.get_segment_spacing()
	var delta := end_pos - start_pos
	var horizontal := absf(delta.x) >= absf(delta.y)
	var segments: Array[Dictionary] = []

	if horizontal:
		var y := start_pos.y
		var x_min := minf(start_pos.x, end_pos.x)
		var x_max := maxf(start_pos.x, end_pos.x)
		var x := x_min
		while x <= x_max + 0.01:
			segments.append({"pos": Vector2(x, y), "vertical": false})
			x += spacing
	else:
		var x := start_pos.x
		var y_min := minf(start_pos.y, end_pos.y)
		var y_max := maxf(start_pos.y, end_pos.y)
		var y := y_min
		while y <= y_max + 0.01:
			segments.append({"pos": Vector2(x, y), "vertical": true})
			y += spacing

	return segments


func _snap_wall_position(world_pos: Vector2) -> Vector2:
	var spacing := WallTexture.get_segment_spacing()
	return Vector2(
		round(world_pos.x / spacing) * spacing,
		round(world_pos.y / spacing) * spacing
	)


func _update_wall_preview(start_pos: Vector2, end_pos: Vector2) -> void:
	var segments := _compute_wall_segments(start_pos, end_pos)
	_ensure_wall_ghost_count(segments.size())

	var line_valid := not segments.is_empty()
	if line_valid:
		if not _can_afford_wall_line(segments.size()):
			line_valid = false
		else:
			for segment in segments:
				if not _is_valid_wall_segment(segment["pos"], segment["vertical"]):
					line_valid = false
					break

	for i in segments.size():
		var segment: Dictionary = segments[i]
		var ghost := _wall_ghost_sprites[i]
		ghost.global_position = segment["pos"]
		ghost.rotation_degrees = 90.0 if segment["vertical"] else 0.0
		ghost.visible = true
		ghost.modulate = Color(0.4, 0.95, 0.55, 0.55) if line_valid else Color(0.95, 0.35, 0.35, 0.55)

	for i in range(segments.size(), _wall_ghost_sprites.size()):
		_wall_ghost_sprites[i].visible = false

	ghost_valid = line_valid


func _ensure_wall_ghost_count(count: int) -> void:
	while _wall_ghost_sprites.size() < count:
		var ghost := Sprite2D.new()
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.texture = WallTexture.get_texture()
		ghost.offset = Vector2(0.0, -ghost.texture.get_height() * 0.5 + 64.0)
		ghost.z_index = 49
		_wall_ghost_container.add_child(ghost)
		_wall_ghost_sprites.append(ghost)


func _clear_wall_ghosts() -> void:
	for ghost in _wall_ghost_sprites:
		ghost.visible = false


func _stop_wall_drag() -> void:
	_wall_dragging = false
	_clear_wall_ghosts()


func _is_valid_wall_segment(world_pos: Vector2, vertical: bool) -> bool:
	return _is_valid_placement_at(world_pos, "wall", vertical)


func _is_valid_placement(world_pos: Vector2) -> bool:
	return _is_valid_placement_at(world_pos, selected_building_type, false)


func _is_valid_placement_at(world_pos: Vector2, type_id: String, vertical: bool) -> bool:
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(world_pos):
		return false

	var def := BuildingDatabase.get_definition(type_id)
	var footprint: Vector2 = def.get("footprint", Vector2(70.0, 45.0))
	if type_id == "wall" and vertical:
		footprint = Vector2(footprint.y, footprint.x)
	var overlap_scale := 0.5 if type_id == "wall" else 0.55
	var half: Vector2 = footprint * overlap_scale
	var test_rect := Rect2(world_pos - half, half * 2.0)

	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and (node as Building).building_state != Building.BuildingState.DESTROYED:
			var other := node as Building
			if test_rect.intersects(other.get_selection_rect(), true):
				return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and (node as TerrainObstacle).blocks_movement:
			var obstacle := node as TerrainObstacle
			if test_rect.has_point(obstacle.global_position):
				return false

	var cost := BuildingDatabase.get_cost(type_id)
	if _resource_manager != null and not _resource_manager.can_afford(cost):
		return false

	if BuildingDatabase.is_gather_building(type_id):
		if not _has_gather_node_nearby(world_pos, type_id):
			return false

	return true


func _multiply_cost(cost: Dictionary, count: int) -> Dictionary:
	return {
		"wood": cost.get("wood", 0) * count,
		"stone": cost.get("stone", 0) * count,
		"food": cost.get("food", 0) * count,
	}


func _can_afford_wall_line(segment_count: int) -> bool:
	if segment_count <= 0 or _resource_manager == null:
		return false
	var total_cost := _multiply_cost(BuildingDatabase.get_cost("wall"), segment_count)
	return _resource_manager.can_afford(total_cost)


func _on_building_completed(building: Building) -> void:
	_request_nav_rebuild(building)


func _has_gather_node_nearby(world_pos: Vector2, type_id: String) -> bool:
	var gather_type: String = BuildingDatabase.get_gather_type(type_id)
	if gather_type.is_empty():
		return true

	var def := BuildingDatabase.get_definition(type_id)
	var radius_cells: int = def.get("gather_radius_cells", 3)
	var cell := _ground_layer.local_to_map(world_pos)

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not node is ResourceNode:
			continue
		var resource_node := node as ResourceNode
		if not resource_node.has_resources():
			continue
		if resource_node.get_resource_key() != gather_type:
			continue
		var node_cell := _ground_layer.local_to_map(resource_node.global_position)
		if Vector2(cell - node_cell).length() <= float(radius_cells):
			return true
	return false


func _request_nav_rebuild(changed_building: Building = null) -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("rebuild_navigation"):
		world.call_deferred("rebuild_navigation", changed_building)


func _screen_to_world(screen_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_point


func _is_pointer_over_ui(screen_pos: Vector2) -> bool:
	var hub := get_node_or_null("/root/Main/HUD/GameHub")
	if hub is Control and (hub as Control).get_global_rect().has_point(screen_pos):
		return true
	return false
