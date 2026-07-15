extends Control

const MAP_PADDING := 4.0
const MINIMAP_SIZE := Vector2(170, 112)

const FRAME_BG := Color(0.1, 0.08, 0.06, 0.94)
const FRAME_BORDER := Color(0.42, 0.35, 0.24, 1.0)
const MAP_BG := Color(0.04, 0.03, 0.03, 1.0)
const GRASS_COLOR := Color(0.20, 0.36, 0.16)
const GRASS_VARIANT := Color(0.16, 0.30, 0.13)
const WATER_COLOR := Color(0.12, 0.26, 0.42)
const TREE_COLOR := Color(0.10, 0.24, 0.08)
const GOLD_COLOR := Color(0.78, 0.62, 0.20)
const FOOD_COLOR := Color(0.55, 0.72, 0.22)
const HILL_COLOR := Color(0.38, 0.32, 0.24)
const PLAYER_UNIT_COLOR := Color(0.45, 0.95, 0.55)
const CIVILIAN_COLOR := Color(0.85, 0.72, 0.25)
const ENEMY_COLOR := Color(0.95, 0.28, 0.22)
const BUILDING_COLOR := Color(0.75, 0.68, 0.48)
const TOWN_CENTER_COLOR := Color(0.85, 0.92, 1.0)
const VIEWPORT_BORDER := Color(1.0, 1.0, 1.0, 0.9)
const VIEWPORT_FILL := Color(1.0, 1.0, 1.0, 0.05)

const ENTITY_REFRESH_INTERVAL := 0.08

var _camera: Camera2D
var _ground: TinyTilesMap
var _map_bounds := Rect2()
var _terrain_texture: ImageTexture
var _resource_markers: Array[Dictionary] = []
var _entity_markers: Array[Dictionary] = []
var _entity_refresh_timer := 0.0
var _dragging := false


func _ready() -> void:
	custom_minimum_size = MINIMAP_SIZE
	size = MINIMAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func setup(camera: Camera2D, ground: TinyTilesMap) -> void:
	_camera = camera
	_ground = ground
	_map_bounds = ground.get_map_bounds()
	_build_terrain_cache()
	_build_resource_markers()
	_refresh_entity_markers()
	queue_redraw()


func _process(delta: float) -> void:
	if _camera == null:
		return

	_entity_refresh_timer -= delta
	if _entity_refresh_timer <= 0.0:
		_entity_refresh_timer = ENTITY_REFRESH_INTERVAL
		_refresh_entity_markers()
	queue_redraw()


func _draw() -> void:
	_draw_frame()
	_draw_terrain()
	_draw_resource_markers()
	_draw_entity_markers()
	_draw_viewport_rect()


func _gui_input(event: InputEvent) -> void:
	if _camera == null or _map_bounds.size == Vector2.ZERO:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			if _is_in_map_area(mouse_event.position):
				_dragging = true
				_navigate_to_local(mouse_event.position)
				accept_event()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		if _is_in_map_area(event.position):
			_navigate_to_local(event.position)
			accept_event()


func _draw_frame() -> void:
	var frame_rect := Rect2(Vector2.ZERO, size)
	draw_rect(frame_rect, FRAME_BG)
	draw_rect(frame_rect, FRAME_BORDER, false, 2.0)

	var content := _get_map_content_rect()
	var center := content.get_center()
	var half := content.size * 0.5
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
		center + Vector2(-half.x, 0.0),
		center + Vector2(0.0, -half.y),
	])
	draw_polyline(diamond, Color(0.35, 0.3, 0.22, 0.9), 1.0)


func _draw_terrain() -> void:
	if _terrain_texture == null:
		return
	var content := _get_map_content_rect()
	draw_texture_rect(_terrain_texture, content, false)


func _draw_resource_markers() -> void:
	for marker in _resource_markers:
		var pos: Vector2 = marker["pos"]
		var color: Color = marker["color"]
		var radius: float = marker.get("radius", 1.5)
		if not _is_inside_diamond(pos):
			continue
		draw_circle(pos, radius, color)


func _draw_entity_markers() -> void:
	for marker in _entity_markers:
		var pos: Vector2 = marker["pos"]
		var color: Color = marker["color"]
		var radius: float = marker.get("radius", 2.0)
		if not _is_inside_diamond(pos):
			continue
		draw_circle(pos, radius, color)
		if marker.get("outline", false):
			draw_arc(pos, radius + 0.8, 0.0, TAU, 12, Color(1, 1, 1, 0.35), 1.0)


func _draw_viewport_rect() -> void:
	if _camera == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var half_view := viewport_size / (2.0 * _camera.zoom)
	var cam_pos := _camera.global_position
	var world_rect := Rect2(cam_pos - half_view, viewport_size / _camera.zoom)

	var top_left := _world_to_minimap(world_rect.position)
	var bottom_right := _world_to_minimap(world_rect.end)
	var view_rect := Rect2(top_left, bottom_right - top_left)

	var content := _get_map_content_rect()
	view_rect = view_rect.intersection(content)
	if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
		return

	draw_rect(view_rect, VIEWPORT_FILL, true)
	draw_rect(view_rect, VIEWPORT_BORDER, false, 1.0)


func _build_terrain_cache() -> void:
	var content := _get_map_content_rect()
	var width := maxi(1, int(content.size.x))
	var height := maxi(1, int(content.size.y))
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(MAP_BG)

	for py in height:
		for px in width:
			var minimap_pos := content.position + Vector2(px + 0.5, py + 0.5)
			if not _is_inside_diamond(minimap_pos):
				continue
			var world_pos := _minimap_to_world(minimap_pos)
			image.set_pixel(px, py, _sample_terrain_color(world_pos))

	_terrain_texture = ImageTexture.create_from_image(image)


func _build_resource_markers() -> void:
	_resource_markers.clear()
	if _ground == null:
		return

	for placement in _ground.get_resource_placements():
		var kind: String = placement.get("kind", "")
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var world_pos := _ground.map_to_local(cell)
		var color := TREE_COLOR if kind == "wood" else GOLD_COLOR
		_resource_markers.append({
			"pos": _world_to_minimap(world_pos),
			"color": color,
			"radius": 1.5,
		})

	for placement in _ground.get_decoration_placements():
		if placement.get("kind", "") != "hill":
			continue
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var world_pos := _ground.map_to_local(cell)
		_resource_markers.append({
			"pos": _world_to_minimap(world_pos),
			"color": HILL_COLOR,
			"radius": 2.0,
		})


func _refresh_entity_markers() -> void:
	_entity_markers.clear()
	if _ground == null:
		return

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.building_state == Building.BuildingState.DESTROYED:
			continue
		var color := TOWN_CENTER_COLOR if building.building_type_id == "town_center" else BUILDING_COLOR
		var radius := 3.0 if building.building_type_id == "town_center" else 2.5
		_entity_markers.append({
			"pos": _world_to_minimap(building.global_position),
			"color": color,
			"radius": radius,
			"outline": building.building_type_id == "town_center",
		})

	for node in get_tree().get_nodes_in_group("selectable_units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if unit.hp <= 0:
			continue
		var color := CIVILIAN_COLOR if unit.is_civilian else PLAYER_UNIT_COLOR
		_entity_markers.append({
			"pos": _world_to_minimap(unit.global_position),
			"color": color,
			"radius": 2.0,
		})

	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Unit:
			continue
		var enemy := node as Unit
		if enemy.hp <= 0:
			continue
		_entity_markers.append({
			"pos": _world_to_minimap(enemy.global_position),
			"color": ENEMY_COLOR,
			"radius": 2.0,
		})

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not node is ResourceNode:
			continue
		var resource := node as ResourceNode
		if resource.resource_kind != ResourceNode.ResourceKind.FOOD:
			continue
		_entity_markers.append({
			"pos": _world_to_minimap(resource.global_position),
			"color": FOOD_COLOR,
			"radius": 1.5,
		})


func _sample_terrain_color(world_pos: Vector2) -> Color:
	if _ground.is_water_at(world_pos):
		return WATER_COLOR
	var cell := _ground.get_cell_at_world(world_pos)
	if cell.x % 3 == cell.y % 3:
		return GRASS_VARIANT
	return GRASS_COLOR


func _get_map_content_rect() -> Rect2:
	return Rect2(
		Vector2(MAP_PADDING, MAP_PADDING),
		size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var content := _get_map_content_rect()
	if _map_bounds.size == Vector2.ZERO:
		return content.position
	var t := (world_pos - _map_bounds.position) / _map_bounds.size
	return content.position + Vector2(t.x * content.size.x, t.y * content.size.y)


func _minimap_to_world(minimap_pos: Vector2) -> Vector2:
	var content := _get_map_content_rect()
	var t := (minimap_pos - content.position) / content.size
	return _map_bounds.position + Vector2(t.x * _map_bounds.size.x, t.y * _map_bounds.size.y)


func _is_inside_diamond(local_pos: Vector2) -> bool:
	var content := _get_map_content_rect()
	var center := content.get_center()
	var half := content.size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return false
	var rel := (local_pos - center) / half
	return absf(rel.x) + absf(rel.y) <= 1.0


func _is_in_map_area(local_pos: Vector2) -> bool:
	return _get_map_content_rect().has_point(local_pos) and _is_inside_diamond(local_pos)


func _navigate_to_local(local_pos: Vector2) -> void:
	var world_pos := _minimap_to_world(local_pos)
	_camera.position = world_pos
