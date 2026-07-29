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

## How far (in segment lengths) a post that already carries a wall can pull the
## drag away from the geometrically nearest post.
const WALL_CONNECT_SNAP_RADIUS := 1.1
## Score multiplier for those posts: below 1.0 they win ties against empty ground.
const WALL_CONNECT_BIAS := 0.72

var build_mode_active: bool = false
var selected_building_type: String = "house_small"
var ghost_valid: bool = false

var _ghost_sprite: Sprite2D
var _wall_ghost_container: Node2D
var _wall_ghost_sprites: Array[Sprite2D] = []
var _wall_dragging: bool = false
var _wall_start_post := Vector2i.ZERO
## Which leg of an L-shaped run is drawn first: -1 unset, 0 = SE (/), 1 = SW (\).
var _wall_primary_axis: int = -1
var _ground_layer: TinyTilesMap
var _buildings_container: Node2D
var _resource_manager: ResourceManager
var _selection_manager: Node
var _job_manager: JobManager
var _building_scene: PackedScene = preload("res://scenes/buildings/building.tscn")
## Standing walls, refreshed once per frame: segment keys + the posts they touch.
var _wall_cache_frame: int = -1
var _wall_segment_keys: Dictionary = {}
var _wall_connect_posts: Array[Vector2i] = []
var _last_ghost_type := ""
var _last_ghost_wall_key := ""
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
			var world_pos := _screen_to_world(mouse_event.position)
			if mouse_event.pressed:
				_wall_start_post = _snap_wall_post(world_pos)
				_wall_primary_axis = -1
				_wall_dragging = true
				_update_wall_preview(world_pos)
			else:
				if _wall_dragging:
					_place_wall_run(world_pos)
				_stop_wall_drag()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_stop_wall_drag()
			_cancel_build_mode()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _wall_dragging:
		_update_wall_preview(_screen_to_world(event.position))
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
			# Idle ghost previews the single segment the cursor points at, so a
			# plain click builds exactly what is highlighted.
			var hover := WallTexture.nearest_segment(_screen_to_world(get_viewport().get_mouse_position()))
			var center: Vector2 = hover["pos"]
			var vertical: bool = hover["vertical"]
			var key := WallTexture.segment_key(center, vertical)
			if key == _last_ghost_wall_key and _last_ghost_type == "wall" and _ghost_sprite.visible:
				return
			_last_ghost_wall_key = key
			_last_ghost_type = "wall"
			ghost_valid = _is_valid_wall_segment(center, vertical)
			_show_wall_ghost(_ghost_sprite, center, vertical, ghost_valid)
		return

	var world_pos := _screen_to_world(get_viewport().get_mouse_position())
	_ghost_sprite.global_position = world_pos
	# Free-form anchors move inside a cell; validity must track world_pos, not the
	# iso cell cache (that let a green ghost slide into a neighbour's footprint).
	ghost_valid = _is_valid_placement(world_pos)
	_last_ghost_type = selected_building_type
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
		_show_feedback_banner("De noche no se puede construir ni reparar")
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
		_last_ghost_wall_key = ""
		_ghost_sprite.texture = WallTexture.get_texture(true, "plot")
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
	# Re-check at click pos — do not trust a stale ghost_valid from a prior frame.
	if not _is_valid_placement(world_pos) or not _is_construction_allowed():
		return
	ghost_valid = true
	_place_single_building(world_pos, false)


func _place_single_building(world_pos: Vector2, vertical: bool, charge_resources: bool = true) -> Building:
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
	if selected_building_type == "wall" or selected_building_type == "gate":
		building.set_wall_vertical(vertical)
	_buildings_container.add_child(building)
	building.place_at(world_pos)
	if selected_building_type == "wall" or selected_building_type == "gate":
		building.notify_world_placed()
	if consume_free:
		_consume_free_placements(selected_building_type, 1)
		_finish_free_only_if_spent(selected_building_type)
	if _job_manager != null:
		_job_manager.alert_nearby_builders(building)
	return building


## Replace an ACTIVE muralla with a constructing puerta on the same segment.
func try_convert_wall_to_gate(wall: Building) -> Building:
	if not _is_construction_allowed():
		_show_feedback_banner("No se puede construir de noche")
		return null
	if wall == null or not is_instance_valid(wall):
		return null
	if wall.building_type_id != "wall" or wall.building_state != Building.BuildingState.ACTIVE:
		return null

	var cost := BuildingDatabase.get_cost("gate")
	if _resource_manager == null or not _resource_manager.can_afford(cost):
		_show_feedback_banner("Recursos insuficientes para la puerta")
		return null
	if not _resource_manager.spend(cost):
		return null

	var world_pos := wall.get_anchor_position()
	var vertical := wall.is_wall_vertical()
	if wall.is_selected:
		wall.deselect()
	if _selection_manager != null and _selection_manager.has_method("clear_selection"):
		_selection_manager.clear_selection()

	# Quiet remove — not combat destruction.
	wall.building_state = Building.BuildingState.DESTROYED
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("rebuild_navigation"):
		world.call_deferred("rebuild_navigation", wall)
	if wall.get_parent() != null:
		wall.get_parent().remove_child(wall)
	wall.queue_free()
	_wall_cache_frame = -1

	var prev_type := selected_building_type
	selected_building_type = "gate"
	var gate := _place_single_building(world_pos, vertical, false)
	selected_building_type = prev_type
	if gate == null:
		return null
	if _selection_manager != null and _selection_manager.has_method("select_building"):
		_selection_manager.select_building(gate)
	return gate


func _place_wall_run(mouse_world: Vector2) -> void:
	if not _is_construction_allowed():
		return

	var valid_segments: Array[Dictionary] = []
	var occupied_keys: Dictionary = {}
	for segment in _compute_wall_run(mouse_world):
		var key := WallTexture.segment_key(segment["pos"], segment["vertical"])
		if occupied_keys.has(key):
			continue
		if _is_valid_wall_segment(segment["pos"], segment["vertical"], occupied_keys):
			occupied_keys[key] = true
			valid_segments.append(segment)

	if valid_segments.is_empty():
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

	for segment in valid_segments:
		_place_single_building(segment["pos"], segment["vertical"], false)

	_finish_free_only_if_spent("wall")


## Segments the current drag would build: an L-shaped run of lattice edges from
## the pressed post to the hovered one. A drag that never leaves its post falls
## back to the single segment under the cursor (plain click = one wall).
func _compute_wall_run(mouse_world: Vector2) -> Array[Dictionary]:
	var segments := _wall_path_segments(_wall_start_post, _snap_wall_post(mouse_world))
	if segments.is_empty():
		segments.append(WallTexture.nearest_segment(mouse_world))
	return segments


func _wall_path_segments(start_post: Vector2i, end_post: Vector2i) -> Array[Dictionary]:
	var delta := end_post - start_post
	var order: Array[int] = [0, 1]
	if _resolve_wall_primary_axis(delta) == 1:
		order = [1, 0]
	var segments: Array[Dictionary] = []
	var cursor := start_post
	for axis in order:
		var vertical := axis == 1
		var steps: int = delta.y if vertical else delta.x
		var dir := signi(steps)
		var unit := Vector2i(0, dir) if vertical else Vector2i(dir, 0)
		for _i in absi(steps):
			var next_post := cursor + unit
			# A segment is keyed by its low post, whichever way the drag runs.
			var low_post := cursor if dir > 0 else next_post
			segments.append({
				"pos": WallTexture.segment_center(low_post, vertical),
				"vertical": vertical,
			})
			cursor = next_post
	return segments


## Keep the elbow of an L-run where the player first turned instead of letting it
## flip around under the cursor; it only re-arms once that leg collapses to zero.
func _resolve_wall_primary_axis(delta: Vector2i) -> int:
	if delta.x == 0 and delta.y == 0:
		_wall_primary_axis = -1
	elif _wall_primary_axis < 0:
		_wall_primary_axis = 0 if absi(delta.x) >= absi(delta.y) else 1
	elif _wall_primary_axis == 0 and delta.x == 0:
		_wall_primary_axis = 1
	elif _wall_primary_axis == 1 and delta.y == 0:
		_wall_primary_axis = 0
	return _wall_primary_axis


## Nearest lattice post, biased toward posts that already carry a wall so new
## runs latch onto what is standing and share its corner column.
func _snap_wall_post(world_pos: Vector2) -> Vector2i:
	var nearest := WallTexture.post_coords(world_pos)
	_refresh_wall_cache()
	if _wall_connect_posts.is_empty():
		return nearest

	var radius := WallTexture.get_segment_length() * WALL_CONNECT_SNAP_RADIUS
	var best := nearest
	var best_score := world_pos.distance_to(WallTexture.post_position(nearest))
	for post in _wall_connect_posts:
		var dist := world_pos.distance_to(WallTexture.post_position(post))
		if dist > radius:
			continue
		var score := dist * WALL_CONNECT_BIAS
		if score < best_score:
			best = post
			best_score = score
	return best


func _refresh_wall_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame == _wall_cache_frame:
		return
	_wall_cache_frame = frame
	_wall_segment_keys.clear()
	_wall_connect_posts.clear()

	var seen_posts: Dictionary = {}
	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if not other.is_wall_segment() or other.building_state == Building.BuildingState.DESTROYED:
			continue
		var center := other.get_anchor_position()
		var vertical := other.is_wall_vertical()
		_wall_segment_keys[WallTexture.segment_key(center, vertical)] = true
		for post in WallTexture.segment_end_posts(center, vertical):
			if seen_posts.has(post):
				continue
			seen_posts[post] = true
			_wall_connect_posts.append(post)


func _update_wall_preview(mouse_world: Vector2) -> void:
	_refresh_wall_cache()
	var run := _compute_wall_run(mouse_world)
	var pending: Dictionary = {}
	var previews: Array[Dictionary] = []
	var budget := _max_affordable_wall_segments(run.size())

	for segment in run:
		var key := WallTexture.segment_key(segment["pos"], segment["vertical"])
		# Runs flow straight through walls that already stand: no ghost, no cost.
		if _wall_segment_keys.has(key) or pending.has(key):
			continue
		var valid := budget > 0 and _is_valid_wall_segment(segment["pos"], segment["vertical"], pending)
		if valid:
			pending[key] = true
			budget -= 1
		previews.append({"pos": segment["pos"], "vertical": segment["vertical"], "valid": valid})

	# Ghosts share one container, so paint them back-to-front like the real walls.
	previews.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)
	_ensure_wall_ghost_count(previews.size())
	for i in previews.size():
		_show_wall_ghost(
			_wall_ghost_sprites[i],
			previews[i]["pos"],
			previews[i]["vertical"],
			previews[i]["valid"]
		)
	for i in range(previews.size(), _wall_ghost_sprites.size()):
		_wall_ghost_sprites[i].visible = false

	ghost_valid = not pending.is_empty()


func _show_wall_ghost(ghost: Sprite2D, center: Vector2, vertical: bool, valid: bool) -> void:
	ghost.texture = WallTexture.get_texture(vertical, "plot")
	ghost.global_position = center
	ghost.rotation_degrees = 0.0
	if ghost.texture != null:
		# Plant the ghost exactly like the finished wall (Building._sprite_draw_offset).
		ghost.offset = Vector2(0.0, -ghost.texture.get_height() * 0.5 + DepthSort.WALL_PLANT)
	ghost.scale = Vector2.ONE * BuildingDatabase.get_visual_scale("wall")
	ghost.modulate = Color(0.4, 0.95, 0.55, 0.6) if valid else Color(0.95, 0.35, 0.35, 0.45)
	ghost.visible = true


func _ensure_wall_ghost_count(count: int) -> void:
	while _wall_ghost_sprites.size() < count:
		var ghost := Sprite2D.new()
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.z_index = 49
		_wall_ghost_container.add_child(ghost)
		_wall_ghost_sprites.append(ghost)


func _clear_wall_ghosts() -> void:
	for ghost in _wall_ghost_sprites:
		ghost.visible = false


func _stop_wall_drag() -> void:
	_wall_dragging = false
	_wall_primary_axis = -1
	_clear_wall_ghosts()
	_wall_cache_frame = -1
	_last_ghost_wall_key = ""


func _is_valid_wall_segment(
	center: Vector2,
	vertical: bool,
	pending_keys: Dictionary = {}
) -> bool:
	if not _is_construction_allowed():
		return false
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(center):
		return false

	var key := WallTexture.segment_key(center, vertical)
	if pending_keys.has(key):
		return false
	_refresh_wall_cache()
	if _wall_segment_keys.has(key):
		return false

	# Only the painted base blocks a wall. Tall art (roofs, towers) covers ground
	# it does not occupy, and reserving that would forbid visually free tiles.
	var outline := WallTexture.get_ground_outline(center, vertical)
	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_state == Building.BuildingState.DESTROYED:
			continue
		# Wall-vs-wall is fully described by segment keys: distinct edges of the
		# lattice never overlap, they only ever share a post.
		if other.is_wall_segment():
			continue
		if _polygons_overlap(outline, other.get_ground_footprint_polygon()):
			return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and _polygon_overlaps_obstacle(outline, node as TerrainObstacle):
			return false

	if get_free_placements("wall") <= 0:
		if _free_only_build:
			return false
		var cost := BuildingDatabase.get_cost("wall")
		if _resource_manager != null and not _resource_manager.can_afford(cost):
			return false

	return true


func _polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	return not Geometry2D.intersect_polygons(a, b).is_empty()


func _polygon_overlaps_obstacle(outline: PackedVector2Array, obstacle: TerrainObstacle) -> bool:
	if obstacle == null or not obstacle.blocks_movement:
		return false
	var outlines := obstacle.get_nav_block_outlines()
	if outlines.is_empty():
		return Geometry2D.is_point_in_polygon(obstacle.global_position, outline)
	for other in outlines:
		if _polygons_overlap(outline, other):
			return true
	return false


func _is_valid_placement(world_pos: Vector2) -> bool:
	return _is_valid_placement_at(world_pos, selected_building_type, false)


func _is_valid_placement_at(world_pos: Vector2, type_id: String, _vertical: bool) -> bool:
	if type_id == "wall":
		var hover := WallTexture.nearest_segment(world_pos)
		return _is_valid_wall_segment(hover["pos"], hover["vertical"])

	if not _is_construction_allowed():
		return false
	if _ground_layer == null:
		return false
	if _ground_layer.is_water_at(world_pos):
		return false

	# Ground plan only — tall sprite AABBs (roofs, towers) must not reserve open tiles.
	var test_poly := BuildingFootprint.world_placement_outline(world_pos, type_id)
	if test_poly.size() < 3:
		return false
	# Inflate both sides so finished nav clearances leave a unit-wide corridor.
	var reserved := BuildingFootprint.expand_polygon(test_poly, BuildingFootprint.PLACEMENT_WALK_CLEARANCE)

	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and (node as Building).building_state != Building.BuildingState.DESTROYED:
			var other := node as Building
			var other_poly := other.get_ground_footprint_polygon()
			if other.is_wall_segment():
				# A wall only reserves its painted base, so buildings may sit against it.
				if _polygons_overlap(test_poly, other_poly):
					return false
			elif _polygons_overlap(
				reserved,
				BuildingFootprint.expand_polygon(other_poly, BuildingFootprint.PLACEMENT_WALK_CLEARANCE)
			):
				return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and _polygon_overlaps_obstacle(test_poly, node as TerrainObstacle):
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


func _show_feedback_banner(text: String, duration: float = 3.5) -> void:
	var hud := get_node_or_null("/root/Main/Layout/WorldView/SubViewport/HUD")
	if hud != null and hud.has_method("show_banner"):
		hud.show_banner(text, duration)


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
