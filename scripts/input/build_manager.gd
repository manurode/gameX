extends Node2D

signal build_mode_changed(active: bool, type_id: String)

const BUILD_HOTKEYS: Dictionary = {
	KEY_1: "house_small",
	KEY_2: "house_big",
	KEY_3: "lumber_camp",
	KEY_4: "mill",
	KEY_5: "mine",
	KEY_6: "stable",
	KEY_7: "barracks",
	KEY_8: "arcanum",
	KEY_9: "tower",
	KEY_0: "wall",
}

## Minimum travel along a leg before a mid-drag turn commits a corner.
const WALL_TURN_MIN_SEGMENTS := 1.0
## Pull the cursor onto existing wall anchors so corners land exactly.
const WALL_CORNER_SNAP_FACTOR := 0.7

var build_mode_active: bool = false
var selected_building_type: String = "house_small"
var ghost_valid: bool = false

var _ghost_sprite: Sprite2D
var _wall_ghost_container: Node2D
var _wall_ghost_sprites: Array[Sprite2D] = []
var _wall_dragging: bool = false
var _wall_drag_start: Vector2 = Vector2.ZERO
var _wall_corners: Array[Vector2] = []
var _wall_leg_vertical: int = -1  # -1 unset, 0 = SE (/), 1 = SW (\)
var _ground_layer: TinyTilesMap
var _buildings_container: Node2D
var _resource_manager: ResourceManager
var _selection_manager: Node
var _job_manager: JobManager
var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")
var _wall_anchor_cache: Array[Vector2] = []
var _wall_anchor_cache_frame: int = -1
var _last_ghost_cell := Vector2i(1 << 30, 1 << 30)
var _last_ghost_type := ""
## Free placements granted by boons (type_id -> remaining count).
var _free_placements: Dictionary = {}
## When true, only free placements are allowed (no paid extras) until they run out.
var _free_only_build: bool = false


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
	add_to_group("build_manager")
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
				_wall_corners = [world_pos]
				# Start every drag on the horizontal wall; upward motion unlocks vertical.
				_wall_leg_vertical = 1 if WallTexture.default_orientation() else 0
				_wall_dragging = true
				_update_wall_preview_polyline(world_pos)
			else:
				if _wall_dragging:
					_place_wall_polyline(world_pos)
				_stop_wall_drag()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_stop_wall_drag()
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _wall_dragging:
		var world_pos := _snap_wall_position(_screen_to_world(event.position))
		_sync_wall_corners_to_mouse(world_pos)
		_update_wall_preview_polyline(world_pos)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not build_mode_active:
		_ghost_sprite.visible = false
		_clear_wall_ghosts()
		_last_ghost_cell = Vector2i(1 << 30, 1 << 30)
		return

	if selected_building_type == "wall":
		if _wall_dragging:
			_ghost_sprite.visible = false
		else:
			var world_pos := _snap_wall_position(_screen_to_world(get_viewport().get_mouse_position()))
			var cell := _ground_layer.get_cell_at_world(world_pos) if _ground_layer != null else Vector2i.ZERO
			if cell == _last_ghost_cell and _last_ghost_type == "wall" and _ghost_sprite.visible:
				return
			_last_ghost_cell = cell
			_last_ghost_type = "wall"
			# Idle ghost always shows the horizontal wall; drag-up selects vertical.
			var vertical := WallTexture.default_orientation()
			_ghost_sprite.global_position = world_pos
			_ghost_sprite.texture = WallTexture.get_texture(vertical, "plot")
			if _ghost_sprite.texture != null:
				_ghost_sprite.offset = Vector2(0.0, -_ghost_sprite.texture.get_height() * 0.5 + 48.0)
			_ghost_sprite.scale = Vector2.ONE * BuildingDatabase.get_visual_scale("wall")
			ghost_valid = _is_valid_wall_segment(world_pos, vertical)
			_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.65) if ghost_valid else Color(0.95, 0.35, 0.35, 0.55)
			_ghost_sprite.rotation_degrees = 0.0
			_ghost_sprite.visible = true
		return

	var world_pos := _screen_to_world(get_viewport().get_mouse_position())
	var place_cell := _ground_layer.get_cell_at_world(world_pos) if _ground_layer != null else Vector2i.ZERO
	_ghost_sprite.global_position = world_pos
	if place_cell != _last_ghost_cell or _last_ghost_type != selected_building_type:
		_last_ghost_cell = place_cell
		_last_ghost_type = selected_building_type
		ghost_valid = _is_valid_placement(world_pos)
	_ghost_sprite.modulate = Color(0.4, 0.95, 0.55, 0.65) if ghost_valid else Color(0.95, 0.35, 0.35, 0.55)
	_ghost_sprite.visible = true


func start_build_mode(type_id: String) -> void:
	_start_build_mode(type_id)


## Grants free placements and enters build mode (same ghost/cursor flow as buying).
## Free-only: cannot spend resources for extra pieces; exits when the grant is used up.
func grant_free_placements(type_id: String, count: int) -> void:
	if not BuildingDatabase.is_buildable(type_id) or count <= 0:
		return
	_free_placements[type_id] = int(_free_placements.get(type_id, 0)) + count
	_start_build_mode(type_id)
	_free_only_build = true


func get_free_placements(type_id: String) -> int:
	return int(_free_placements.get(type_id, 0))


func _start_build_mode(type_id: String) -> void:
	if not BuildingDatabase.is_buildable(type_id):
		return
	if not _is_construction_allowed():
		return
	_stop_wall_drag()
	# Manual build (hotkeys/UI) leaves free-only mode so paid construction works normally.
	_free_only_build = false
	selected_building_type = type_id
	build_mode_active = true
	_update_ghost_texture()
	build_mode_changed.emit(true, type_id)


func cancel_build_mode() -> void:
	_cancel_build_mode()


func _cancel_build_mode() -> void:
	_stop_wall_drag()
	_free_only_build = false
	build_mode_active = false
	_ghost_sprite.visible = false
	build_mode_changed.emit(false, "")


func _finish_free_only_if_spent(type_id: String) -> void:
	if _free_only_build and get_free_placements(type_id) <= 0:
		_cancel_build_mode()


func _update_ghost_texture() -> void:
	var def := BuildingDatabase.get_definition(selected_building_type)
	if def.is_empty():
		return
	if selected_building_type == "wall":
		_ghost_sprite.texture = WallTexture.get_texture(WallTexture.default_orientation(), "plot")
	else:
		var texture_path: String = def.get("texture", "")
		if not texture_path.is_empty():
			var plot_path := texture_path.get_basename() + "_plot.png"
			if ResourceLoader.exists(plot_path):
				_ghost_sprite.texture = load(plot_path)
			else:
				_ghost_sprite.texture = load(texture_path)
	if _ghost_sprite.texture != null:
		var foot := 48.0 if selected_building_type == "wall" else 64.0
		_ghost_sprite.offset = Vector2(0.0, -_ghost_sprite.texture.get_height() * 0.5 + foot)
		var visual_scale := BuildingDatabase.get_visual_scale(selected_building_type)
		_ghost_sprite.scale = Vector2(visual_scale, visual_scale)
		_ghost_sprite.modulate = def.get("tint", Color(0.4, 0.95, 0.55, 0.55))


func _try_place_building(world_pos: Vector2) -> void:
	if not ghost_valid or not _is_construction_allowed():
		return
	_place_single_building(world_pos, false)


func _place_single_building(
	world_pos: Vector2,
	vertical: bool,
	charge_resources: bool = true,
	retile_walls: bool = true
) -> Building:
	if not _is_construction_allowed():
		return null
	var consume_free := false
	if charge_resources:
		if get_free_placements(selected_building_type) > 0:
			charge_resources = false
			consume_free = true
		elif _free_only_build:
			return null
		else:
			var cost := BuildingDatabase.get_cost(selected_building_type)
			if _resource_manager == null or not _resource_manager.spend(cost):
				return null

	var building: Building = _building_scene.instantiate()
	building.configure(selected_building_type, Building.BuildingState.CONSTRUCTING, 0.0)
	if selected_building_type == "wall":
		building.set_wall_vertical(vertical)
	_buildings_container.add_child(building)
	building.place_at(world_pos)
	if selected_building_type == "wall":
		building.notify_world_placed()
		if retile_walls:
			retile_walls_at([world_pos])
	if consume_free:
		_consume_free_placements(selected_building_type, 1)
		_finish_free_only_if_spent(selected_building_type)
	if _job_manager != null:
		_job_manager.alert_nearby_builders(building)
	return building


func _place_wall_polyline(end_pos: Vector2) -> void:
	if not _is_construction_allowed():
		return
	var segments := _compute_wall_polyline_segments(end_pos)
	if segments.is_empty():
		return

	var valid_segments: Array[Dictionary] = []
	var occupied_keys: Dictionary = {}
	for segment in segments:
		var key := WallTexture.cell_key(segment["pos"])
		if occupied_keys.has(key):
			continue
		# Existing wall at this cell: keep it and retile after (corner / T upgrade).
		if _find_wall_at(segment["pos"]) != null:
			occupied_keys[key] = true
			continue
		if _is_valid_wall_segment(segment["pos"], segment["vertical"], occupied_keys):
			occupied_keys[key] = true
			valid_segments.append(segment)

	if valid_segments.is_empty():
		# Still retile so snapping onto an existing wall upgrades junctions.
		var touch_cells: Array[Vector2] = []
		for segment in segments:
			touch_cells.append(segment["pos"])
		retile_walls_at(touch_cells)
		return

	var affordable := _max_affordable_wall_segments(valid_segments.size())
	if affordable <= 0:
		return
	if affordable < valid_segments.size():
		valid_segments = valid_segments.slice(0, affordable)

	var free_to_use := mini(valid_segments.size(), get_free_placements("wall"))
	var paid_count := valid_segments.size() - free_to_use
	if _free_only_build and paid_count > 0:
		# Cap to remaining free segments; never mix paid pieces into a boon grant.
		valid_segments = valid_segments.slice(0, free_to_use)
		paid_count = 0
		free_to_use = valid_segments.size()
		if free_to_use <= 0:
			return
	if paid_count > 0:
		var unit_cost := BuildingDatabase.get_cost("wall")
		var total_cost := _multiply_cost(unit_cost, paid_count)
		if _resource_manager == null or not _resource_manager.spend(total_cost):
			return
	if free_to_use > 0:
		_consume_free_placements("wall", free_to_use)

	var placed_cells: Array[Vector2] = []
	for segment in valid_segments:
		_place_single_building(segment["pos"], segment["vertical"], false, false)
		placed_cells.append(segment["pos"])
	for segment in segments:
		placed_cells.append(segment["pos"])
	retile_walls_at(placed_cells)

	_finish_free_only_if_spent("wall")


func _sync_wall_corners_to_mouse(mouse_pos: Vector2) -> void:
	if _wall_corners.is_empty():
		_wall_corners = [_wall_drag_start]

	var from := _wall_corners[_wall_corners.size() - 1]
	var delta := mouse_pos - from
	if delta.length_squared() < 1.0:
		return

	var desired_vertical := WallTexture.orientation_from_delta(delta)
	if _wall_leg_vertical < 0:
		_wall_leg_vertical = 1 if desired_vertical else 0
		return

	var current_vertical := _wall_leg_vertical == 1
	if desired_vertical == current_vertical:
		_trim_wall_corners_beyond(mouse_pos)
		return

	# Direction changed: commit a corner on the current axis, then start the new leg.
	var corner := WallTexture.project_to_axis(from, mouse_pos, current_vertical)
	var min_turn := WallTexture.get_segment_spacing() * WALL_TURN_MIN_SEGMENTS * 0.5
	if corner.distance_to(from) < min_turn:
		# Still near the last corner — just switch active orientation.
		_wall_leg_vertical = 1 if desired_vertical else 0
		return

	if corner.distance_squared_to(from) > 0.01:
		_wall_corners.append(corner)
	_wall_leg_vertical = 1 if desired_vertical else 0


func _trim_wall_corners_beyond(mouse_pos: Vector2) -> void:
	# If the cursor retreats past a committed corner, pop it so the path can reshape.
	while _wall_corners.size() > 1:
		var last: Vector2 = _wall_corners[_wall_corners.size() - 1]
		var prev: Vector2 = _wall_corners[_wall_corners.size() - 2]
		var leg_delta := last - prev
		if leg_delta.length_squared() < 0.01:
			_wall_corners.pop_back()
			continue
		var mouse_along := (mouse_pos - prev).dot(leg_delta.normalized())
		var leg_len := leg_delta.length()
		if mouse_along < leg_len * 0.5:
			_wall_corners.pop_back()
			var new_from: Vector2 = _wall_corners[_wall_corners.size() - 1]
			var back_delta := mouse_pos - new_from
			if back_delta.length_squared() > 1.0:
				_wall_leg_vertical = 1 if WallTexture.orientation_from_delta(back_delta) else 0
			else:
				_wall_leg_vertical = 1 if WallTexture.default_orientation() else 0
		else:
			break


func _compute_wall_polyline_segments(end_pos: Vector2) -> Array[Dictionary]:
	## Polyline points are segment centers. Turns share one lattice cell — retile
	## swaps that cell to a corner/junction sprite instead of stacking two straights.
	var points: Array[Vector2] = []
	for corner in _wall_corners:
		points.append(corner)

	var leg_vertical := WallTexture.default_orientation()
	if _wall_leg_vertical >= 0:
		leg_vertical = _wall_leg_vertical == 1

	# Keep the free end on the active axis so the last segment hits the corner exactly.
	var end := WallTexture.project_to_axis(
		points[points.size() - 1] if not points.is_empty() else end_pos,
		end_pos,
		leg_vertical
	)
	if not points.is_empty():
		end = _snap_drag_end_to_corner(points[points.size() - 1], end, end_pos, leg_vertical)
	if points.is_empty():
		points.append(end)
	elif points[points.size() - 1].distance_squared_to(end) > 0.01:
		points.append(end)

	var segments: Array[Dictionary] = []
	var seen: Dictionary = {}
	for i in range(points.size() - 1):
		var leg_delta: Vector2 = points[i + 1] - points[i]
		var vertical := WallTexture.orientation_from_delta(leg_delta)
		# Prefer the locked leg orientation when this is the active free end.
		if i == points.size() - 2 and _wall_leg_vertical >= 0:
			vertical = _wall_leg_vertical == 1
		var leg := _compute_straight_wall_segments(points[i], points[i + 1], vertical)
		for segment in leg:
			var key := WallTexture.cell_key(segment["pos"])
			if seen.has(key):
				continue
			seen[key] = true
			segments.append(segment)

	if segments.is_empty() and not points.is_empty():
		var vertical := leg_vertical
		segments.append({"pos": points[0], "vertical": vertical})

	return segments


func _compute_straight_wall_segments(
	start_pos: Vector2,
	end_pos: Vector2,
	vertical: bool
) -> Array[Dictionary]:
	## Place centers on the locked axis from start through the projected end.
	var start := WallTexture.snap_position(start_pos)
	var end := WallTexture.project_to_axis(start, end_pos, vertical)
	var step := WallTexture.get_segment_step(vertical)
	var segments: Array[Dictionary] = []

	if step.length_squared() < 0.01:
		segments.append({"pos": start, "vertical": vertical})
		return segments

	var along := (end - start).dot(step.normalized())
	var count := maxi(1, int(round(absf(along) / step.length())) + 1)
	var dir := 1.0 if along >= 0.0 else -1.0
	for i in count:
		var pos := start + step * float(i) * dir
		segments.append({"pos": WallTexture.snap_position(pos), "vertical": vertical})

	return segments


func _snap_wall_position(world_pos: Vector2) -> Vector2:
	var raw := WallTexture.snap_position(world_pos)
	return _snap_to_wall_anchor(raw, world_pos)


func _snap_to_wall_anchor(raw: Vector2, world_pos: Vector2) -> Vector2:
	## Magnet onto existing wall centers / neighbor slots so corners close cleanly.
	var anchors := _get_wall_corner_anchors()
	if anchors.is_empty():
		return raw

	var radius := WallTexture.get_segment_step(false).length() * WALL_CORNER_SNAP_FACTOR
	var best := raw
	var best_dist := world_pos.distance_to(raw)
	for anchor in anchors:
		var dist := world_pos.distance_to(anchor)
		if dist <= radius and dist < best_dist:
			best = anchor
			best_dist = dist
	return best


func _snap_drag_end_to_corner(
	from: Vector2,
	projected: Vector2,
	world_pos: Vector2,
	vertical: bool
) -> Vector2:
	## While dragging, only snap to anchors that lie on the active wall axis.
	var anchors := _get_wall_corner_anchors()
	if anchors.is_empty():
		return projected

	var radius := WallTexture.get_segment_step(vertical).length() * WALL_CORNER_SNAP_FACTOR
	var best := projected
	var best_dist := INF
	for anchor in anchors:
		var on_axis := WallTexture.project_to_axis(from, anchor, vertical)
		if on_axis.distance_squared_to(anchor) > 1.0:
			continue
		var dist := world_pos.distance_to(anchor)
		if dist <= radius and dist < best_dist:
			best = anchor
			best_dist = dist
	return best if best_dist < INF else projected


func _get_wall_corner_anchors() -> Array[Vector2]:
	var frame := Engine.get_process_frames()
	if frame == _wall_anchor_cache_frame:
		return _wall_anchor_cache

	_wall_anchor_cache_frame = frame
	_wall_anchor_cache.clear()
	var seen: Dictionary = {}
	var se_step := WallTexture.get_segment_step(false)
	var sw_step := WallTexture.get_segment_step(true)

	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_type_id != "wall" or other.building_state == Building.BuildingState.DESTROYED:
			continue
		var origin := WallTexture.snap_position(other.get_anchor_position())
		var candidates: Array[Vector2] = [
			origin,
			WallTexture.snap_position(origin + se_step),
			WallTexture.snap_position(origin - se_step),
			WallTexture.snap_position(origin + sw_step),
			WallTexture.snap_position(origin - sw_step),
		]
		for candidate in candidates:
			var key := "%d:%d" % [roundi(candidate.x), roundi(candidate.y)]
			if seen.has(key):
				continue
			seen[key] = true
			_wall_anchor_cache.append(candidate)

	return _wall_anchor_cache


func _update_wall_preview_polyline(end_pos: Vector2) -> void:
	var segments := _compute_wall_polyline_segments(end_pos)
	_ensure_wall_ghost_count(segments.size())

	var occupied_keys: Dictionary = {}
	var pending_cells: Dictionary = {}
	for segment in segments:
		pending_cells[WallTexture.cell_key(segment["pos"])] = true
	var any_valid := false
	var affordable_left := _max_affordable_wall_segments(segments.size())

	for i in segments.size():
		var segment: Dictionary = segments[i]
		var ghost := _wall_ghost_sprites[i]
		var key := WallTexture.cell_key(segment["pos"])
		var existing := _find_wall_at(segment["pos"])

		# Don't stack a translucent ghost on top of a finished wall — that was the
		# messy "double corner" look. Existing cells still count as valid (retile).
		if existing != null:
			ghost.visible = false
			any_valid = true
			continue

		ghost.global_position = segment["pos"]
		ghost.rotation_degrees = 0.0
		var preview_mask := _preview_wall_mask_at(segment["pos"], pending_cells, segment["vertical"])
		# Prefer complete art at ghost alpha — plot foundations look broken at corners.
		ghost.texture = WallTexture.get_texture_for_mask(preview_mask, "complete")
		if ghost.texture != null:
			ghost.offset = Vector2(0.0, -ghost.texture.get_height() * 0.5 + 48.0)
		ghost.scale = Vector2.ONE * BuildingDatabase.get_visual_scale("wall")
		ghost.visible = true

		var segment_valid := false
		if not occupied_keys.has(key) and affordable_left > 0:
			segment_valid = _is_valid_wall_segment(segment["pos"], segment["vertical"], occupied_keys)
			if segment_valid:
				occupied_keys[key] = true
				affordable_left -= 1
				any_valid = true

		ghost.modulate = Color(0.4, 0.95, 0.55, 0.55) if segment_valid else Color(0.95, 0.35, 0.35, 0.45)

	for i in range(segments.size(), _wall_ghost_sprites.size()):
		_wall_ghost_sprites[i].visible = false

	ghost_valid = any_valid


func _ensure_wall_ghost_count(count: int) -> void:
	while _wall_ghost_sprites.size() < count:
		var ghost := Sprite2D.new()
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.texture = WallTexture.get_texture(false)
		ghost.offset = Vector2(0.0, -ghost.texture.get_height() * 0.5 + 48.0)
		ghost.scale = Vector2.ONE * BuildingDatabase.get_visual_scale("wall")
		ghost.z_index = 49
		_wall_ghost_container.add_child(ghost)
		_wall_ghost_sprites.append(ghost)


func _clear_wall_ghosts() -> void:
	for ghost in _wall_ghost_sprites:
		ghost.visible = false


func _stop_wall_drag() -> void:
	_wall_dragging = false
	_wall_corners.clear()
	_wall_leg_vertical = -1
	_clear_wall_ghosts()
	_wall_anchor_cache_frame = -1


func _is_near_axis(delta: Vector2, step: Vector2) -> bool:
	if delta.length_squared() < 0.01 or step.length_squared() < 0.01:
		return false
	var axis := step.normalized()
	var along := absf(delta.dot(axis))
	var cross := absf(delta.x * axis.y - delta.y * axis.x)
	return along > cross


func _is_valid_wall_segment(
	world_pos: Vector2,
	vertical: bool,
	pending_keys: Dictionary = {}
) -> bool:
	if not _is_construction_allowed():
		return false
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(world_pos):
		return false

	var key := WallTexture.cell_key(world_pos)
	if pending_keys.has(key):
		return false

	var snap := WallTexture.snap_position(world_pos)
	var spacing := WallTexture.get_segment_spacing()
	var footprint := WallTexture.footprint(vertical)
	var half := footprint * 0.35
	var test_rect := Rect2(snap - half, half * 2.0)

	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_state == Building.BuildingState.DESTROYED:
			continue

		if other.building_type_id == "wall":
			if not _wall_conflicts_with_existing(snap, vertical, other, spacing):
				continue
			return false

		# Non-wall buildings: keep a modest footprint overlap check.
		if test_rect.intersects(other.get_selection_rect(), true):
			return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and _placement_overlaps_obstacle(snap, test_rect, node as TerrainObstacle):
			return false

	if get_free_placements("wall") <= 0:
		if _free_only_build:
			return false
		var cost := BuildingDatabase.get_cost("wall")
		if _resource_manager != null and not _resource_manager.can_afford(cost):
			return false

	return true


func _placement_overlaps_obstacle(world_pos: Vector2, test_rect: Rect2, obstacle: TerrainObstacle) -> bool:
	if obstacle == null or not obstacle.blocks_movement:
		return false
	var outlines := obstacle.get_nav_block_outlines()
	if outlines.is_empty():
		return test_rect.has_point(obstacle.global_position)
	var corners := [
		test_rect.position,
		test_rect.position + Vector2(test_rect.size.x, 0.0),
		test_rect.position + test_rect.size,
		test_rect.position + Vector2(0.0, test_rect.size.y),
	]
	for outline in outlines:
		if outline.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(world_pos, outline):
			return true
		for point in outline:
			if test_rect.has_point(point):
				return true
		for corner in corners:
			if Geometry2D.is_point_in_polygon(corner, outline):
				return true
	return false


func _wall_conflicts_with_existing(
	snap: Vector2,
	vertical: bool,
	other: Building,
	_spacing: float
) -> bool:
	var other_pos := WallTexture.snap_position(other.get_anchor_position())
	var dist := snap.distance_to(other_pos)
	var step_len := WallTexture.get_segment_step(vertical).length()

	# One wall building per lattice cell — never stack SE+SW sprites.
	if dist < 1.0:
		return true

	var self_mask := WallTexture.mask_from_vertical(vertical)
	var other_mask := other.get_wall_mask()
	# Too close along a shared axis — overlapping chain pieces.
	if WallTexture.has_se_axis(self_mask) and WallTexture.has_se_axis(other_mask):
		if dist < step_len * 0.85 and _is_near_axis(snap - other_pos, WallTexture.get_segment_step(false)):
			return true
	if WallTexture.has_sw_axis(self_mask) and WallTexture.has_sw_axis(other_mask):
		if dist < step_len * 0.85 and _is_near_axis(snap - other_pos, WallTexture.get_segment_step(true)):
			return true
	return false


func _find_wall_at(world_pos: Vector2) -> Building:
	var snap := WallTexture.snap_position(world_pos)
	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_type_id != "wall":
			continue
		if other.building_state == Building.BuildingState.DESTROYED:
			continue
		if WallTexture.snap_position(other.get_anchor_position()).distance_squared_to(snap) < 1.0:
			return other
	return null


func _collect_wall_cells(extra_pending: Dictionary = {}) -> Dictionary:
	## cell_key -> true for existing walls plus optional pending preview cells.
	var cells: Dictionary = extra_pending.duplicate()
	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_type_id != "wall":
			continue
		if other.building_state == Building.BuildingState.DESTROYED:
			continue
		cells[WallTexture.cell_key(other.get_anchor_position())] = true
	return cells


func _compute_wall_mask_at(world_pos: Vector2, occupied_cells: Dictionary, fallback_vertical: bool) -> int:
	var snap := WallTexture.snap_position(world_pos)
	var mask := 0
	for dir_bit in WallTexture.all_dir_bits():
		var neighbor := WallTexture.snap_position(snap + WallTexture.dir_offset(dir_bit))
		if occupied_cells.has(WallTexture.cell_key(neighbor)):
			mask |= dir_bit
	return WallTexture.normalize_mask(mask, fallback_vertical)


func _preview_wall_mask_at(world_pos: Vector2, pending_cells: Dictionary, fallback_vertical: bool) -> int:
	return _compute_wall_mask_at(world_pos, _collect_wall_cells(pending_cells), fallback_vertical)


func retile_walls_at(cells: Array) -> void:
	## Recompute junction sprites for the given cells and their lattice neighbors.
	var occupied := _collect_wall_cells()
	var targets: Dictionary = {}
	for cell in cells:
		if typeof(cell) != TYPE_VECTOR2 and typeof(cell) != TYPE_VECTOR2I:
			continue
		var snap := WallTexture.snap_position(Vector2(cell))
		targets[WallTexture.cell_key(snap)] = snap
		for dir_bit in WallTexture.all_dir_bits():
			var neighbor := WallTexture.snap_position(snap + WallTexture.dir_offset(dir_bit))
			targets[WallTexture.cell_key(neighbor)] = neighbor

	for key in targets.keys():
		var pos: Vector2 = targets[key]
		var wall := _find_wall_at(pos)
		if wall == null:
			continue
		var mask := _compute_wall_mask_at(pos, occupied, wall.is_wall_vertical())
		if wall.get_wall_mask() != mask:
			wall.set_wall_mask(mask)
	_wall_anchor_cache_frame = -1


func _is_valid_placement(world_pos: Vector2) -> bool:
	return _is_valid_placement_at(world_pos, selected_building_type, false)


func _is_valid_placement_at(world_pos: Vector2, type_id: String, vertical: bool) -> bool:
	if type_id == "wall":
		return _is_valid_wall_segment(world_pos, vertical)

	if not _is_construction_allowed():
		return false
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(world_pos):
		return false

	var def := BuildingDatabase.get_definition(type_id)
	var footprint: Vector2 = def.get("footprint", Vector2(70.0, 45.0))
	var overlap_scale := 0.55
	var half: Vector2 = footprint * overlap_scale
	var test_rect := Rect2(world_pos - half, half * 2.0)

	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and (node as Building).building_state != Building.BuildingState.DESTROYED:
			var other := node as Building
			if test_rect.intersects(other.get_selection_rect(), true):
				return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and _placement_overlaps_obstacle(world_pos, test_rect, node as TerrainObstacle):
			return false

	if get_free_placements(type_id) <= 0:
		if _free_only_build:
			return false
		var cost := BuildingDatabase.get_cost(type_id)
		if _resource_manager != null and not _resource_manager.can_afford(cost):
			return false

	if BuildingDatabase.is_gather_building(type_id):
		if (
			not BuildingDatabase.spawns_gather_source(type_id)
			and not _has_gather_node_nearby(world_pos, type_id)
		):
			return false

	return true


func _multiply_cost(cost: Dictionary, count: int) -> Dictionary:
	return {
		"wood": cost.get("wood", 0) * count,
		"gold": cost.get("gold", 0) * count,
		"food": cost.get("food", 0) * count,
	}


func _is_construction_allowed() -> bool:
	var manager := get_tree().get_first_node_in_group("day_night_manager")
	return not (manager is DayNightManager) or (manager as DayNightManager).is_construction_allowed()


func _max_affordable_wall_segments(desired: int) -> int:
	if desired <= 0:
		return 0
	var free_left := get_free_placements("wall") if selected_building_type == "wall" else 0
	if _free_only_build:
		return mini(desired, free_left)
	var paid_desired := maxi(0, desired - free_left)
	var paid_affordable := _max_resource_wall_segments(paid_desired)
	return mini(desired, free_left + paid_affordable)


func _max_resource_wall_segments(desired: int) -> int:
	if desired <= 0 or _resource_manager == null:
		return 0
	var unit_cost := BuildingDatabase.get_cost("wall")
	var wood_cost: int = unit_cost.get("wood", 0)
	var gold_cost: int = unit_cost.get("gold", 0)
	var food_cost: int = unit_cost.get("food", 0)
	var max_by_res := desired
	if wood_cost > 0:
		max_by_res = mini(max_by_res, int(_resource_manager.wood / wood_cost))
	if gold_cost > 0:
		max_by_res = mini(max_by_res, int(_resource_manager.gold / gold_cost))
	if food_cost > 0:
		max_by_res = mini(max_by_res, int(_resource_manager.food / food_cost))
	return maxi(0, max_by_res)


func _consume_free_placements(type_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var available := get_free_placements(type_id)
	var used := mini(available, count)
	if used <= 0:
		return 0
	var remaining := available - used
	if remaining > 0:
		_free_placements[type_id] = remaining
	else:
		_free_placements.erase(type_id)
	return used


func _has_gather_node_nearby(world_pos: Vector2, type_id: String) -> bool:
	var gather_type: String = BuildingDatabase.get_gather_type(type_id)
	if gather_type.is_empty():
		return true

	var def := BuildingDatabase.get_definition(type_id)
	var radius_cells: int = def.get("gather_radius_cells", 3)
	# ~1 full iso tile per radius cell from the visual edge (fallback path).
	var max_dist := float(radius_cells) * DepthSort.ISO_HALF_TILE * 2.0
	var place_cell := (
		_ground_layer.local_to_map(world_pos) if _ground_layer != null else Vector2i.ZERO
	)

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not node is ResourceNode:
			continue
		var resource_node := node as ResourceNode
		if not resource_node.has_resources():
			continue
		if resource_node.get_resource_key() != gather_type:
			continue
		# Primary: adjacent to any footprint cell (works on all sides of large masses).
		if resource_node.is_near_cell_for_building(place_cell, radius_cells):
			return true
		# Fallback: visual sprite bounds (nodes without a map footprint).
		if resource_node.is_near_for_building(world_pos, max_dist):
			return true
	return false


func _screen_to_world(screen_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_point


func _is_pointer_over_ui(_screen_pos: Vector2) -> bool:
	var hub := get_node_or_null("/root/Main/Layout/HubMargin/GameHub")
	if hub == null:
		hub = get_node_or_null("/root/Main/Layout/GameHub")
	if hub is Control:
		var root_mouse := get_tree().root.get_mouse_position()
		return (hub as Control).get_global_rect().has_point(root_mouse)
	return false
