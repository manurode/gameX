extends Node2D

signal build_mode_changed(active: bool, type_id: String)

const BUILD_HOTKEYS: Dictionary = {
	KEY_1: "house_small",
	KEY_2: "house_big",
	KEY_3: "mill",
	KEY_4: "stable",
	KEY_5: "tower",
	KEY_6: "wall",
	KEY_7: "castle_small",
	KEY_8: "castle_big",
}

var build_mode_active: bool = false
var selected_building_type: String = "house_small"
var ghost_valid: bool = false

var _ghost_sprite: Sprite2D
var _ground_layer: TinyTilesMap
var _buildings_container: Node2D
var _resource_manager: ResourceManager
var _selection_manager: Node
var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")


func setup(
	ground_layer: TinyTilesMap,
	buildings_container: Node2D,
	resource_manager: ResourceManager,
	selection_manager: Node
) -> void:
	_ground_layer = ground_layer
	_buildings_container = buildings_container
	_resource_manager = resource_manager
	_selection_manager = selection_manager
	_create_ghost()


func _create_ghost() -> void:
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.centered = true
	_ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.55)
	_ghost_sprite.visible = false
	_ghost_sprite.z_index = 50
	add_child(_ghost_sprite)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and build_mode_active:
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode in BUILD_HOTKEYS:
			_start_build_mode(BUILD_HOTKEYS[key_event.keycode])
			get_viewport().set_input_as_handled()
			return

	if not build_mode_active:
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_building(_screen_to_world(mouse_event.position))
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_build_mode()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not build_mode_active:
		_ghost_sprite.visible = false
		return

	var world_pos := _screen_to_world(get_viewport().get_mouse_position())
	_ghost_sprite.global_position = world_pos
	ghost_valid = _is_valid_placement(world_pos)
	_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.65) if ghost_valid else Color(0.95, 0.35, 0.35, 0.55)
	_ghost_sprite.visible = true


func _start_build_mode(type_id: String) -> void:
	selected_building_type = type_id
	build_mode_active = true
	_update_ghost_texture()
	build_mode_changed.emit(true, type_id)


func _cancel_build_mode() -> void:
	build_mode_active = false
	_ghost_sprite.visible = false
	build_mode_changed.emit(false, "")


func _update_ghost_texture() -> void:
	var def := BuildingDatabase.get_definition(selected_building_type)
	if def.is_empty():
		return
	if def.get("procedural", false):
		_ghost_sprite.texture = _create_wall_texture()
	else:
		var texture_path: String = def.get("texture", "")
		if not texture_path.is_empty():
			_ghost_sprite.texture = load(texture_path)
	if _ghost_sprite.texture != null:
		_ghost_sprite.offset = Vector2(0.0, -_ghost_sprite.texture.get_height() * 0.5 + 64.0)


func _create_wall_texture() -> Texture2D:
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 128:
			var noise := sin(float(x) * 0.35) * 0.08 + cos(float(y) * 0.5) * 0.06
			var base := 0.42 + noise
			if y < 6 or y > 57:
				base *= 0.75
			image.set_pixel(x, y, Color(base * 0.55, base * 0.52, base * 0.48, 1.0))
	return ImageTexture.create_from_image(image)


func _try_place_building(world_pos: Vector2) -> void:
	if not ghost_valid:
		return
	var cost := BuildingDatabase.get_cost(selected_building_type)
	if _resource_manager == null or not _resource_manager.spend(cost):
		return

	var building: Building = _building_scene.instantiate()
	building.configure(selected_building_type, Building.BuildingState.CONSTRUCTING, 0.0)
	_buildings_container.add_child(building)
	building.global_position = world_pos
	building.construction_completed.connect(_on_building_completed.bind(building))

	_assign_builders_to(building)
	_request_nav_rebuild()


func _on_building_completed(_building: Building) -> void:
	_request_nav_rebuild()


func _assign_builders_to(site: Building) -> void:
	if _selection_manager == null:
		return
	var assigned := false
	for unit in _selection_manager.selected_units:
		if is_instance_valid(unit) and unit.can_build:
			unit.assign_construction(site)
			assigned = true
	if not assigned:
		for node in get_tree().get_nodes_in_group("units"):
			if node is Unit and (node as Unit).can_build:
				(node as Unit).assign_construction(site)


func _is_valid_placement(world_pos: Vector2) -> bool:
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(world_pos):
		return false

	var def := BuildingDatabase.get_definition(selected_building_type)
	var half: Vector2 = def.get("footprint", Vector2(70.0, 45.0)) * 0.55
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

	var cost := BuildingDatabase.get_cost(selected_building_type)
	if _resource_manager != null and not _resource_manager.can_afford(cost):
		return false

	return true


func _request_nav_rebuild() -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("rebuild_navigation"):
		world.call_deferred("rebuild_navigation")


func _screen_to_world(screen_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_point
