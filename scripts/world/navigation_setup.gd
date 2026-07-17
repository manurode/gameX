extends NavigationRegion2D

const SECTOR_SIZE := 16
const REBUILD_DEBOUNCE := 0.12
const PATH_CELL_SIZE := Vector2(24.0, 24.0)
const AGENT_CLEARANCE := 16.0
const SEGMENT_SAMPLE_STEP := 8.0
const CLOSEST_POINT_SEARCH_LIMIT := 48
const DYNAMIC_REBUILD_RADIUS := 128.0
const PATHS_PER_FRAME := 12
const PATH_CACHE_LIMIT := 512

var _ground_layer: TinyTilesMap
var _sector_regions: Dictionary = {}
var _dirty_sectors: Dictionary = {}
var _dirty_path_grid_points: Dictionary = {}
var _obstacles: Array = []
var _buildings: Array = []
var _rebuild_timer: Timer
var _path_grid := AStarGrid2D.new()
var _path_grid_origin := Vector2.ZERO
var _path_grid_size := Vector2i.ZERO
var _navigation_version := 0
var _path_cache: Dictionary = {}
var _path_queue: Array[Dictionary] = []
var _path_queue_keys: Dictionary = {}
var _path_queue_head := 0
var _blocker_bounds_cache: Array = []
var _blocker_bounds_version := -1


func setup_from_ground(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer
	add_to_group("navigation_manager")
	navigation_polygon = null
	_create_sector_regions()
	set_process(true)


func _process(_delta: float) -> void:
	_process_path_queue()


func rebuild_navigation(obstacles: Array = [], buildings: Array = []) -> void:
	if _ground_layer == null:
		return
	update_sources(obstacles, buildings)
	for sector_key in _sector_regions:
		_rebuild_sector(sector_key)
	_dirty_sectors.clear()
	_rebuild_path_grid()


func update_sources(obstacles: Array, buildings: Array) -> void:
	_obstacles = obstacles.duplicate()
	_buildings = buildings.duplicate()
	_blocker_bounds_cache.clear()
	_blocker_bounds_version = -1


func request_rebuild_at(world_position: Vector2) -> void:
	if _ground_layer == null:
		return
	var radius_vector := Vector2(DYNAMIC_REBUILD_RADIUS, DYNAMIC_REBUILD_RADIUS)
	var min_cell := Vector2i(1 << 30, 1 << 30)
	var max_cell := Vector2i(-(1 << 30), -(1 << 30))
	for corner in [
		world_position - radius_vector,
		world_position + radius_vector,
		world_position + Vector2(radius_vector.x, -radius_vector.y),
		world_position + Vector2(-radius_vector.x, radius_vector.y),
	]:
		var corner_cell := _ground_layer.get_cell_at_world(corner)
		min_cell = min_cell.min(corner_cell)
		max_cell = max_cell.max(corner_cell)
	var min_sector := Vector2i(
		floori(float(min_cell.x) / float(SECTOR_SIZE)),
		floori(float(min_cell.y) / float(SECTOR_SIZE))
	)
	var max_sector := Vector2i(
		floori(float(max_cell.x) / float(SECTOR_SIZE)),
		floori(float(max_cell.y) / float(SECTOR_SIZE))
	)
	for y in range(min_sector.y, max_sector.y + 1):
		for x in range(min_sector.x, max_sector.x + 1):
			var key := Vector2i(x, y)
			if key in _sector_regions:
				_dirty_sectors[key] = true
	_mark_path_grid_dirty(world_position)
	_ensure_rebuild_timer()
	_rebuild_timer.start(REBUILD_DEBOUNCE)


func _create_sector_regions() -> void:
	for region in _sector_regions.values():
		if is_instance_valid(region):
			region.queue_free()
	_sector_regions.clear()
	_dirty_sectors.clear()
	_dirty_path_grid_points.clear()

	var map_size := _ground_layer.get_map_size()
	var sector_count := Vector2i(
		ceili(float(map_size.x) / float(SECTOR_SIZE)),
		ceili(float(map_size.y) / float(SECTOR_SIZE))
	)
	for sector_y in sector_count.y:
		for sector_x in sector_count.x:
			var key := Vector2i(sector_x, sector_y)
			var region := NavigationRegion2D.new()
			region.name = "Sector_%d_%d" % [sector_x, sector_y]
			region.use_edge_connections = true
			add_child(region)
			_sector_regions[key] = region


func _rebuild_sector(sector: Vector2i) -> void:
	var region: NavigationRegion2D = _sector_regions.get(sector)
	if region == null:
		return
	var cell_rect := _get_sector_cell_rect(sector)
	var blocked_cells := _get_blocked_cells(cell_rect)
	var navigation_polygon := NavigationPolygon.new()
	var vertices := PackedVector2Array()
	var vertex_indices: Dictionary = {}
	var polygons: Array[PackedInt32Array] = []
	for y in range(cell_rect.position.y, cell_rect.end.y):
		for x in range(cell_rect.position.x, cell_rect.end.x):
			var cell := Vector2i(x, y)
			if not _ground_layer.is_walkable_cell(cell) or cell in blocked_cells:
				continue
			var polygon := PackedInt32Array()
			for point in _get_cell_corners(cell):
				var vertex_index: int
				if point in vertex_indices:
					vertex_index = vertex_indices[point]
				else:
					vertex_index = vertices.size()
					vertices.append(point)
					vertex_indices[point] = vertex_index
				polygon.append(vertex_index)
			polygons.append(polygon)

	navigation_polygon.vertices = vertices
	for polygon in polygons:
		navigation_polygon.add_polygon(polygon)
	region.navigation_polygon = navigation_polygon


func _get_sector_cell_rect(sector: Vector2i) -> Rect2i:
	var start := sector * SECTOR_SIZE
	var size := Vector2i(SECTOR_SIZE, SECTOR_SIZE)
	var map_size := _ground_layer.get_map_size()
	size.x = mini(size.x, map_size.x - start.x)
	size.y = mini(size.y, map_size.y - start.y)
	return Rect2i(start, size)


func _get_blocked_cells(cell_rect: Rect2i) -> Dictionary:
	var blocked: Dictionary = {}
	for obstacle in _obstacles:
		if (
			is_instance_valid(obstacle)
			and obstacle is TerrainObstacle
			and (obstacle as TerrainObstacle).blocks_movement
		):
			for outline in (obstacle as TerrainObstacle).get_nav_block_outlines():
				_mark_outline_cells(outline, cell_rect, blocked)
	for building in _buildings:
		if is_instance_valid(building) and building is Building:
			var active_building := building as Building
			if active_building.blocks_navigation:
				_mark_outline_cells(active_building.get_nav_block_outline(), cell_rect, blocked)
	return blocked


func _mark_outline_cells(
	world_outline: PackedVector2Array,
	cell_rect: Rect2i,
	blocked: Dictionary
) -> void:
	if world_outline.size() < 3:
		return
	var local_outline := PackedVector2Array()
	var min_cell := Vector2i(1 << 30, 1 << 30)
	var max_cell := Vector2i(-(1 << 30), -(1 << 30))
	for world_point in world_outline:
		var local_point := _ground_layer.to_local(world_point)
		local_outline.append(local_point)
		var point_cell := _ground_layer.local_to_map(local_point)
		min_cell = min_cell.min(point_cell)
		max_cell = max_cell.max(point_cell)

	var candidate_rect := Rect2i(
		min_cell - Vector2i.ONE,
		max_cell - min_cell + Vector2i(3, 3)
	).intersection(cell_rect)
	for y in range(candidate_rect.position.y, candidate_rect.end.y):
		for x in range(candidate_rect.position.x, candidate_rect.end.x):
			var cell := Vector2i(x, y)
			var cell_center := _ground_layer.map_to_local(cell)
			if Geometry2D.is_point_in_polygon(cell_center, local_outline):
				blocked[cell] = true


func _get_cell_corners(cell: Vector2i) -> PackedVector2Array:
	var center := _ground_layer.map_to_local(cell)
	var half_width := float(TinyTilesMap.TILE_SIZE.x) * 0.5
	var half_height := float(TinyTilesMap.TILE_SIZE.y) * 0.5
	return PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(half_width, 0.0),
		center + Vector2(0.0, half_height),
		center + Vector2(-half_width, 0.0),
	])


func _ensure_rebuild_timer() -> void:
	if _rebuild_timer != null:
		return
	_rebuild_timer = Timer.new()
	_rebuild_timer.one_shot = true
	_rebuild_timer.timeout.connect(_rebuild_dirty_sectors)
	add_child(_rebuild_timer)


func _rebuild_dirty_sectors() -> void:
	var sectors := _dirty_sectors.keys()
	_dirty_sectors.clear()
	for sector in sectors:
		_rebuild_sector(sector)
	_rebuild_dirty_path_grid()


func _mark_path_grid_dirty(world_position: Vector2) -> void:
	if _path_grid_size == Vector2i.ZERO:
		return

	var radius_vector := Vector2(DYNAMIC_REBUILD_RADIUS, DYNAMIC_REBUILD_RADIUS)
	var min_id := _world_to_grid(world_position - radius_vector) - Vector2i.ONE
	var max_id := _world_to_grid(world_position + radius_vector) + Vector2i.ONE
	min_id = min_id.max(Vector2i.ZERO)
	max_id = max_id.min(_path_grid_size - Vector2i.ONE)
	for y in range(min_id.y, max_id.y + 1):
		for x in range(min_id.x, max_id.x + 1):
			_dirty_path_grid_points[Vector2i(x, y)] = true


func _rebuild_dirty_path_grid() -> void:
	if _dirty_path_grid_points.is_empty() or _path_grid_size == Vector2i.ZERO:
		return

	var dirty_points := _dirty_path_grid_points.keys()
	_dirty_path_grid_points.clear()
	for dirty_point in dirty_points:
		var point_id: Vector2i = dirty_point
		_path_grid.set_point_solid(
			point_id,
			not _is_world_point_walkable(_grid_to_world(point_id))
		)
	_bump_navigation_version()


func get_navigation_path(from_position: Vector2, target_position: Vector2) -> PackedVector2Array:
	var cache_key := _make_path_cache_key(from_position, target_position)
	if _path_cache.has(cache_key):
		return _path_cache[cache_key]

	queue_navigation_path(from_position, target_position)
	return PackedVector2Array()


func queue_navigation_path(from_position: Vector2, target_position: Vector2) -> void:
	if _path_grid_size == Vector2i.ZERO:
		return

	var cache_key := _make_path_cache_key(from_position, target_position)
	if _path_cache.has(cache_key) or _path_queue_keys.has(cache_key):
		return

	_path_queue_keys[cache_key] = true
	_path_queue.append({
		"from": from_position,
		"to": target_position,
		"key": cache_key,
	})


func queue_navigation_paths(requests: Array) -> void:
	for request in requests:
		if request is Dictionary:
			queue_navigation_path(request.get("from", Vector2.ZERO), request.get("to", Vector2.ZERO))


func _process_path_queue() -> void:
	var processed := 0
	while _path_queue_head < _path_queue.size() and processed < PATHS_PER_FRAME:
		var request: Dictionary = _path_queue[_path_queue_head]
		_path_queue_head += 1
		var cache_key: String = request.get("key", "")
		_path_queue_keys.erase(cache_key)
		if cache_key.is_empty() or _path_cache.has(cache_key):
			processed += 1
			continue

		var from_position: Vector2 = request.get("from", Vector2.ZERO)
		var target_position: Vector2 = request.get("to", Vector2.ZERO)
		_path_cache[cache_key] = _compute_navigation_path(from_position, target_position)
		if _path_cache.size() > PATH_CACHE_LIMIT:
			_evict_path_cache()
		processed += 1

	if _path_queue_head > 64 and _path_queue_head * 2 > _path_queue.size():
		_path_queue = _path_queue.slice(_path_queue_head)
		_path_queue_head = 0


func _evict_path_cache() -> void:
	# Drop roughly half the entries instead of wiping the whole cache.
	var keys := _path_cache.keys()
	var drop_count := keys.size() / 2
	for i in drop_count:
		_path_cache.erase(keys[i])


func _compute_navigation_path(from_position: Vector2, target_position: Vector2) -> PackedVector2Array:
	if _path_grid_size == Vector2i.ZERO:
		return PackedVector2Array()

	var start_id := _find_closest_walkable_id(_world_to_grid(from_position))
	var target_id := _find_closest_walkable_id(_world_to_grid(target_position))
	if start_id == Vector2i(-1, -1) or target_id == Vector2i(-1, -1):
		return PackedVector2Array()

	var id_path := _path_grid.get_id_path(start_id, target_id, false)
	if id_path.is_empty():
		return PackedVector2Array()

	var raw_path := PackedVector2Array()
	raw_path.append(from_position)
	for point_id in id_path:
		raw_path.append(_grid_to_world(point_id))

	var reachable_target := _grid_to_world(target_id)
	if _is_world_point_walkable(target_position):
		reachable_target = target_position
	if raw_path[-1].distance_squared_to(reachable_target) > 1.0:
		raw_path.append(reachable_target)

	return _smooth_path(raw_path)


func _make_path_cache_key(from_position: Vector2, target_position: Vector2) -> String:
	var start_id := _world_to_grid(from_position)
	var target_id := _world_to_grid(target_position)
	# Compact integer key string avoids Dictionary Array-key pitfalls.
	return "%d_%d_%d_%d_%d" % [
		_navigation_version,
		start_id.x,
		start_id.y,
		target_id.x,
		target_id.y,
	]


func _bump_navigation_version() -> void:
	_navigation_version += 1
	_path_cache.clear()
	_path_queue.clear()
	_path_queue_keys.clear()
	_path_queue_head = 0
	_blocker_bounds_version = -1


func get_closest_walkable_point(world_position: Vector2) -> Vector2:
	if _path_grid_size == Vector2i.ZERO:
		return world_position
	var point_id := _find_closest_walkable_id(_world_to_grid(world_position))
	if point_id == Vector2i(-1, -1):
		return world_position
	return _grid_to_world(point_id)


func get_navigation_version() -> int:
	return _navigation_version


func _rebuild_path_grid() -> void:
	if _ground_layer == null:
		return

	var bounds := _ground_layer.get_map_bounds().grow(
		maxf(float(TinyTilesMap.TILE_SIZE.x), float(TinyTilesMap.TILE_SIZE.y)) * 0.5
	)
	_path_grid_origin = Vector2(
		floorf(bounds.position.x / PATH_CELL_SIZE.x) * PATH_CELL_SIZE.x,
		floorf(bounds.position.y / PATH_CELL_SIZE.y) * PATH_CELL_SIZE.y
	)
	_path_grid_size = Vector2i(
		ceili(bounds.size.x / PATH_CELL_SIZE.x) + 1,
		ceili(bounds.size.y / PATH_CELL_SIZE.y) + 1
	)

	_path_grid = AStarGrid2D.new()
	_path_grid.region = Rect2i(Vector2i.ZERO, _path_grid_size)
	_path_grid.offset = _path_grid_origin
	_path_grid.cell_size = PATH_CELL_SIZE
	_path_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_path_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_path_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_path_grid.update()

	for y in _path_grid_size.y:
		for x in _path_grid_size.x:
			var point_id := Vector2i(x, y)
			if not _is_world_point_walkable(_grid_to_world(point_id)):
				_path_grid.set_point_solid(point_id, true)

	_bump_navigation_version()


func _world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(
		roundi((world_position.x - _path_grid_origin.x) / PATH_CELL_SIZE.x),
		roundi((world_position.y - _path_grid_origin.y) / PATH_CELL_SIZE.y)
	)


func _grid_to_world(point_id: Vector2i) -> Vector2:
	return _path_grid_origin + Vector2(point_id) * PATH_CELL_SIZE


func _is_grid_id_valid(point_id: Vector2i) -> bool:
	return (
		point_id.x >= 0
		and point_id.y >= 0
		and point_id.x < _path_grid_size.x
		and point_id.y < _path_grid_size.y
	)


func _find_closest_walkable_id(center_id: Vector2i) -> Vector2i:
	if _is_grid_id_valid(center_id) and not _path_grid.is_point_solid(center_id):
		return center_id

	for radius in range(1, CLOSEST_POINT_SEARCH_LIMIT + 1):
		var best_id := Vector2i(-1, -1)
		var best_distance_sq := INF
		for x in range(center_id.x - radius, center_id.x + radius + 1):
			for y in [center_id.y - radius, center_id.y + radius]:
				var candidate := Vector2i(x, y)
				if _is_grid_id_valid(candidate) and not _path_grid.is_point_solid(candidate):
					var distance_sq := Vector2(candidate - center_id).length_squared()
					if distance_sq < best_distance_sq:
						best_distance_sq = distance_sq
						best_id = candidate
		for y in range(center_id.y - radius + 1, center_id.y + radius):
			for x in [center_id.x - radius, center_id.x + radius]:
				var candidate := Vector2i(x, y)
				if _is_grid_id_valid(candidate) and not _path_grid.is_point_solid(candidate):
					var distance_sq := Vector2(candidate - center_id).length_squared()
					if distance_sq < best_distance_sq:
						best_distance_sq = distance_sq
						best_id = candidate
		if best_id != Vector2i(-1, -1):
			return best_id

	return Vector2i(-1, -1)


func _ensure_blocker_bounds_cache() -> void:
	if _blocker_bounds_version == _navigation_version and not _blocker_bounds_cache.is_empty():
		return
	_blocker_bounds_version = _navigation_version
	_blocker_bounds_cache.clear()
	for obstacle in _obstacles:
		if (
			not is_instance_valid(obstacle)
			or not (obstacle is TerrainObstacle)
			or not (obstacle as TerrainObstacle).blocks_movement
		):
			continue
		for outline in (obstacle as TerrainObstacle).get_nav_block_outlines():
			if outline.size() < 3:
				continue
			_blocker_bounds_cache.append({
				"outline": outline,
				"rect": _outline_bounds(outline).grow(AGENT_CLEARANCE),
			})
	for building in _buildings:
		if not is_instance_valid(building) or not (building is Building):
			continue
		var active_building := building as Building
		if not active_building.blocks_navigation:
			continue
		var outline := active_building.get_nav_block_outline()
		if outline.size() < 3:
			continue
		_blocker_bounds_cache.append({
			"outline": outline,
			"rect": _outline_bounds(outline).grow(AGENT_CLEARANCE),
		})


func _outline_bounds(outline: PackedVector2Array) -> Rect2:
	var min_v := outline[0]
	var max_v := outline[0]
	for i in range(1, outline.size()):
		min_v = min_v.min(outline[i])
		max_v = max_v.max(outline[i])
	return Rect2(min_v, max_v - min_v)


func _is_world_point_walkable(world_position: Vector2) -> bool:
	if _ground_layer == null:
		return false
	if not _ground_layer.is_walkable_cell(_ground_layer.get_cell_at_world(world_position)):
		return false

	_ensure_blocker_bounds_cache()
	for blocker in _blocker_bounds_cache:
		var rect: Rect2 = blocker["rect"]
		if not rect.has_point(world_position):
			continue
		if _is_point_blocked_by_outline(world_position, blocker["outline"]):
			return false

	return true


func _is_point_blocked_by_outline(point: Vector2, outline: PackedVector2Array) -> bool:
	if outline.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(point, outline):
		return true

	for i in outline.size():
		var segment_start := outline[i]
		var segment_end := outline[(i + 1) % outline.size()]
		var closest := Geometry2D.get_closest_point_to_segment(point, segment_start, segment_end)
		if point.distance_squared_to(closest) <= AGENT_CLEARANCE * AGENT_CLEARANCE:
			return true
	return false


func _smooth_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	if raw_path.size() <= 2:
		return raw_path

	var result := PackedVector2Array([raw_path[0]])
	var anchor_index := 0
	while anchor_index < raw_path.size() - 1:
		var furthest_visible := anchor_index + 1
		for candidate_index in range(raw_path.size() - 1, anchor_index, -1):
			if _has_clear_segment(raw_path[anchor_index], raw_path[candidate_index]):
				furthest_visible = candidate_index
				break
		result.append(raw_path[furthest_visible])
		anchor_index = furthest_visible
	return result


func _has_clear_segment(from_position: Vector2, to_position: Vector2) -> bool:
	var distance := from_position.distance_to(to_position)
	var sample_count := maxi(1, ceili(distance / SEGMENT_SAMPLE_STEP))
	for i in range(1, sample_count + 1):
		var point := from_position.lerp(to_position, float(i) / float(sample_count))
		var grid_id := _world_to_grid(point)
		if not _is_grid_id_valid(grid_id) or _path_grid.is_point_solid(grid_id):
			return false
	return true
