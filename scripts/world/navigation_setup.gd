extends NavigationRegion2D

const SECTOR_SIZE := 16
const REBUILD_DEBOUNCE := 0.12
const PATH_CELL_SIZE := Vector2(24.0, 24.0)
const AGENT_CLEARANCE := 16.0
const SEGMENT_SAMPLE_STEP := 8.0
const CLOSEST_POINT_SEARCH_LIMIT := 48
const DYNAMIC_REBUILD_RADIUS := 128.0
const PATHS_PER_FRAME := 12
## Hard ceiling on queue work per frame. A saturated queue (whole army repathing
## after a nav change) must never blow the frame; leftovers roll to the next one.
const PATH_QUEUE_BUDGET_USEC := 3000
## Same idea for nav rebuilds: a wall run dirties thousands of grid points, which
## used to land on one frame as a visible hitch.
const REBUILD_BUDGET_USEC := 3000
const PATH_CACHE_LIMIT := 512
## Breach decisions ("can I walk around this muralla?") are cluster-scale
## questions, so every enemy in the same neighbourhood heading for the same goal
## shares one answer. Without this each enemy ran its own synchronous A* every
## scan tick, which is what made a walled night cost several times a bare one.
const METRICS_CELL_SPAN := 4
const METRICS_CACHE_TTL_MSEC := 500
## The async path queue is budgeted, but breach metrics were not: when a muralla
## fell, the version bump dropped every cached path and the whole horde ran a
## cold synchronous A* on its next scan, stalling frames for seconds. Cap the
## synchronous work per physics frame and let latecomers reuse their last answer.
const METRICS_SYNC_BUDGET_USEC := 1500
## A* only pays for itself when a route exists. Asking AStarGrid2D for a path into
## a sealed town makes it expand every open cell on the map (~16ms here) before
## reporting failure, and a walled night asks exactly that, constantly. Labelling
## connected regions turns that answer into two array reads.
const COMPONENT_NONE := -1
const COMPONENT_UNVISITED := -2
const COMPONENT_BUILD_BUDGET_USEC := 2000

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
var _metrics_cache: Dictionary = {}
var _metrics_budget_frame := -1
var _metrics_budget_started := 0
var _components := PackedInt32Array()
var _components_ready := false
var _component_scratch := PackedInt32Array()
var _component_queue := PackedInt32Array()
var _component_queue_head := 0
var _component_queue_tail := 0
var _component_build_active := false
var _component_build_scan := 0
var _component_next_label := 0
var _path_queue: Array[Dictionary] = []
var _path_queue_keys: Dictionary = {}
var _path_queue_head := 0
var _blocker_bounds_cache: Array = []
var _blocker_bounds_version := -1
var _rebuild_active := false
var _pending_sectors: Array = []
var _pending_points: Array = []
var _pending_points_changed := false


func setup_from_ground(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer
	add_to_group("navigation_manager")
	navigation_polygon = null
	_create_sector_regions()
	set_process(true)


func _process(_delta: float) -> void:
	_process_pending_rebuild()
	_process_component_build()
	_process_path_queue()


func rebuild_navigation(obstacles: Array = [], buildings: Array = []) -> void:
	if _ground_layer == null:
		return
	update_sources(obstacles, buildings)
	for sector_key in _sector_regions:
		_rebuild_sector(sector_key)
	_dirty_sectors.clear()
	_reset_pending_rebuild()
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
	_reset_pending_rebuild()

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


## Debounce elapsed: promote the dirty sets into work queues that `_process`
## drains under a frame budget. Doing it all here made a wall run hitch.
func _rebuild_dirty_sectors() -> void:
	for sector in _dirty_sectors:
		if not _pending_sectors.has(sector):
			_pending_sectors.append(sector)
	_dirty_sectors.clear()
	_pending_points.append_array(_dirty_path_grid_points.keys())
	_dirty_path_grid_points.clear()
	_rebuild_active = true


## A full rebuild supersedes any queued incremental work.
func _reset_pending_rebuild() -> void:
	_pending_sectors.clear()
	_pending_points.clear()
	_pending_points_changed = false
	_rebuild_active = false


func _process_pending_rebuild() -> void:
	if not _rebuild_active:
		return
	var started := Time.get_ticks_usec()

	while not _pending_sectors.is_empty():
		var sector: Vector2i = _pending_sectors.pop_back()
		_rebuild_sector(sector)
		if Time.get_ticks_usec() - started >= REBUILD_BUDGET_USEC:
			return

	if _path_grid_size == Vector2i.ZERO:
		_pending_points.clear()
	while not _pending_points.is_empty():
		var point_id: Vector2i = _pending_points.pop_back()
		var solid := not _is_world_point_walkable(_grid_to_world(point_id))
		if _path_grid.is_point_solid(point_id) != solid:
			_path_grid.set_point_solid(point_id, solid)
			_pending_points_changed = true
		if Time.get_ticks_usec() - started >= REBUILD_BUDGET_USEC:
			return

	_rebuild_active = false
	# Bumping the version drops every cached path, so the whole army repaths at
	# once. Publish only when the update is complete and a cell actually flipped.
	if _pending_points_changed:
		_pending_points_changed = false
		_bump_navigation_version()


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


func get_navigation_path(from_position: Vector2, target_position: Vector2) -> PackedVector2Array:
	var cache_key := _make_path_cache_key(from_position, target_position)
	if _path_cache.has(cache_key):
		return _path_cache[cache_key]

	queue_navigation_path(from_position, target_position)
	return PackedVector2Array()


## Sync path metrics for AI decisions. Uses the path cache when warm; otherwise
## computes immediately and stores the result so later movers share the work.
## `reachable` means the path end lands near the requested target (not merely
## the closest walkable cell outside a wall ring).
func query_path_metrics(from_position: Vector2, target_position: Vector2) -> Dictionary:
	var metrics_key := _make_metrics_cache_key(from_position, target_position)
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _metrics_cache.get(metrics_key, {})
	if (
		not entry.is_empty()
		and int(entry["version"]) == _navigation_version
		and now - int(entry["stamp"]) < METRICS_CACHE_TTL_MSEC
	):
		return entry["metrics"]

	if not _claim_metrics_budget():
		# This frame already spent its pathfinding time. Reuse the previous answer
		# when we have one; otherwise warm the async queue and tell the caller the
		# metrics are not ready, so it keeps its current plan one more scan.
		if not entry.is_empty():
			return entry["metrics"]
		queue_navigation_path(from_position, target_position)
		return {
			"reachable": false,
			"length": INF,
			"end": from_position,
			"path": PackedVector2Array(),
			"unknown": true,
		}

	var metrics := _build_path_metrics(from_position, target_position)
	if _metrics_cache.size() > PATH_CACHE_LIMIT:
		_metrics_cache.clear()
	_metrics_cache[metrics_key] = {
		"stamp": now,
		"version": _navigation_version,
		"metrics": metrics,
	}
	return metrics


## Restart region labelling. The previously published labels stay queryable while
## the new pass runs: they can only be stale for the few frames after a wall
## changed, and a stale answer costs an unnecessary A* at worst.
func _invalidate_components() -> void:
	var total := _path_grid_size.x * _path_grid_size.y
	if total <= 0:
		_components_ready = false
		_component_build_active = false
		return

	_component_scratch.resize(total)
	_component_scratch.fill(COMPONENT_UNVISITED)
	if _component_queue.size() != total:
		_component_queue.resize(total)
	_component_queue_head = 0
	_component_queue_tail = 0
	_component_build_scan = 0
	_component_next_label = 0
	_component_build_active = true


## 8-connected flood fill. A* may move diagonally only when both orthogonals are
## free, so its reachability is a subset of this: regions that come out distinct
## are guaranteed unreachable, which is the only direction we may not get wrong.
func _process_component_build() -> void:
	if not _component_build_active:
		return

	var started := Time.get_ticks_usec()
	var width := _path_grid_size.x
	var height := _path_grid_size.y
	var total := width * height

	while true:
		while _component_queue_head < _component_queue_tail:
			var index := _component_queue[_component_queue_head]
			_component_queue_head += 1
			var label := _component_scratch[index]
			var cx := index % width
			var cy := index / width
			for oy in range(maxi(cy - 1, 0), mini(cy + 2, height)):
				for ox in range(maxi(cx - 1, 0), mini(cx + 2, width)):
					var neighbour := oy * width + ox
					if _component_scratch[neighbour] != COMPONENT_UNVISITED:
						continue
					if _path_grid.is_point_solid(Vector2i(ox, oy)):
						_component_scratch[neighbour] = COMPONENT_NONE
						continue
					_component_scratch[neighbour] = label
					_component_queue[_component_queue_tail] = neighbour
					_component_queue_tail += 1
			if Time.get_ticks_usec() - started >= COMPONENT_BUILD_BUDGET_USEC:
				return

		# Current region drained; seed the next one.
		_component_queue_head = 0
		_component_queue_tail = 0
		while _component_build_scan < total:
			if _component_scratch[_component_build_scan] == COMPONENT_UNVISITED:
				break
			_component_build_scan += 1
		if _component_build_scan >= total:
			break

		var seed_index := _component_build_scan
		var seed_id := Vector2i(seed_index % width, seed_index / width)
		if _path_grid.is_point_solid(seed_id):
			# Solid cells the fill never touched (open water, deep interiors) are
			# retired one per pass, so this branch needs the budget check too.
			_component_scratch[seed_index] = COMPONENT_NONE
			if Time.get_ticks_usec() - started >= COMPONENT_BUILD_BUDGET_USEC:
				return
			continue
		_component_scratch[seed_index] = _component_next_label
		_component_queue[_component_queue_tail] = seed_index
		_component_queue_tail += 1
		_component_next_label += 1

		if Time.get_ticks_usec() - started >= COMPONENT_BUILD_BUDGET_USEC:
			return

	_components = _component_scratch.duplicate()
	_components_ready = true
	_component_build_active = false


func _component_at(point_id: Vector2i) -> int:
	if not _components_ready:
		return COMPONENT_NONE
	var index := point_id.y * _path_grid_size.x + point_id.x
	if index < 0 or index >= _components.size():
		return COMPONENT_NONE
	return _components[index]


## True while the current physics frame may still afford a synchronous path.
func _claim_metrics_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _metrics_budget_frame:
		_metrics_budget_frame = frame
		_metrics_budget_started = Time.get_ticks_usec()
		return true
	return Time.get_ticks_usec() - _metrics_budget_started < METRICS_SYNC_BUDGET_USEC


func _build_path_metrics(from_position: Vector2, target_position: Vector2) -> Dictionary:
	var cache_key := _make_path_cache_key(from_position, target_position)
	var path: PackedVector2Array
	if _path_cache.has(cache_key):
		path = _path_cache[cache_key]
	else:
		path = _compute_navigation_path(from_position, target_position)
		_path_cache[cache_key] = path
		if _path_cache.size() > PATH_CACHE_LIMIT:
			_evict_path_cache()

	if path.is_empty():
		return {
			"reachable": false,
			"length": INF,
			"end": from_position,
			"path": path,
		}

	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var end: Vector2 = path[path.size() - 1]
	# Generous so large building surfaces still count as reached; walls that fully
	# enclose a goal leave the path end clearly farther than this.
	var reach_tol := maxf(PATH_CELL_SIZE.x * 4.0, 96.0)
	var reachable := end.distance_squared_to(target_position) <= reach_tol * reach_tol
	return {
		"reachable": reachable,
		"length": length,
		"end": end,
		"path": path,
	}


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
	var started := Time.get_ticks_usec()
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
		if Time.get_ticks_usec() - started >= PATH_QUEUE_BUDGET_USEC:
			break

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

	# Distinct regions can never be joined by a path, so skip the A* entirely.
	var start_component := _component_at(start_id)
	var target_component := _component_at(target_id)
	if start_component >= 0 and target_component >= 0 and start_component != target_component:
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


## Same idea as the path key but on a deliberately coarse grid, so a pack of
## enemies converging on one goal resolves to a single cached answer. The nav
## version is stored alongside instead of baked in, so a stale entry survives a
## rebuild and can still answer while the frame budget is exhausted.
func _make_metrics_cache_key(from_position: Vector2, target_position: Vector2) -> String:
	var start_id := _world_to_grid(from_position)
	var target_id := _world_to_grid(target_position)
	return "%d_%d_%d_%d" % [
		start_id.x / METRICS_CELL_SPAN,
		start_id.y / METRICS_CELL_SPAN,
		target_id.x / METRICS_CELL_SPAN,
		target_id.y / METRICS_CELL_SPAN,
	]


func _bump_navigation_version() -> void:
	_navigation_version += 1
	_invalidate_components()
	_path_cache.clear()
	# _metrics_cache is deliberately kept: its entries carry their own version and
	# a stale one is a far better answer than stalling the frame on a cold A*.
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

	# Labels from a previous grid size must never be read against the new one.
	_components_ready = false
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
			_cache_blocker(outline)
	for building in _buildings:
		if not is_instance_valid(building) or not (building is Building):
			continue
		var active_building := building as Building
		if not active_building.blocks_navigation:
			continue
		_cache_blocker(active_building.get_nav_block_outline())


## Bake the agent clearance into the outline once per navigation version. The
## per-point alternative (point-in-polygon plus a distance test against every
## edge) ran ~50 edge tests per path-grid point and dominated build hitches.
func _cache_blocker(outline: PackedVector2Array) -> void:
	if outline.size() < 3:
		return
	# Offsetting deflates a clockwise ring, so normalize the winding first.
	var source := outline
	if Geometry2D.is_polygon_clockwise(source):
		source = source.duplicate()
		source.reverse()

	var grown_any := false
	for grown in Geometry2D.offset_polygon(source, AGENT_CLEARANCE, Geometry2D.JOIN_ROUND):
		if grown.size() < 3 or Geometry2D.is_polygon_clockwise(grown):
			# Clockwise rings are holes; an outward offset should not make any.
			continue
		grown_any = true
		_blocker_bounds_cache.append({
			"outline": grown,
			"rect": _outline_bounds(grown),
		})

	if not grown_any:
		# Degenerate outline: keep blocking the raw shape rather than nothing.
		_blocker_bounds_cache.append({
			"outline": source,
			"rect": _outline_bounds(source).grow(AGENT_CLEARANCE),
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
		# Outlines are pre-grown by AGENT_CLEARANCE, so containment is the whole test.
		if Geometry2D.is_point_in_polygon(world_position, blocker["outline"]):
			return false

	return true


## Greedy string-pull: keep the furthest waypoint each anchor can see directly.
## Visibility along a grid A* route is monotonic, so probe with a doubling step
## and binary-search the boundary. Testing every candidate from the far end
## instead made this O(n^2) segment walks, which dominated night-wave frames.
func _smooth_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	if raw_path.size() <= 2:
		return raw_path

	var last_index := raw_path.size() - 1
	var result := PackedVector2Array([raw_path[0]])
	var anchor_index := 0
	while anchor_index < last_index:
		var anchor := raw_path[anchor_index]
		# Straight shot to the goal: the common case for short / open routes.
		if _has_clear_segment(anchor, raw_path[last_index]):
			result.append(raw_path[last_index])
			break

		# Advance while visible, doubling the stride. Never probes last_index,
		# so `high` below always stays a known-blocked bound.
		var visible := anchor_index + 1
		var stride := 1
		while (
			visible + stride < last_index
			and _has_clear_segment(anchor, raw_path[visible + stride])
		):
			visible += stride
			stride *= 2

		var low := visible
		var high := mini(last_index, visible + stride)
		while low + 1 < high:
			var mid := low + (high - low) / 2
			if _has_clear_segment(anchor, raw_path[mid]):
				low = mid
			else:
				high = mid

		result.append(raw_path[low])
		anchor_index = low
	return result


func _has_clear_segment(from_position: Vector2, to_position: Vector2) -> bool:
	var distance := from_position.distance_to(to_position)
	var sample_count := maxi(1, ceili(distance / SEGMENT_SAMPLE_STEP))
	# Sample step is finer than the grid cell, so consecutive samples usually
	# land in the same cell — skip the repeats instead of re-querying.
	var last_id := Vector2i(-0x40000000, -0x40000000)
	for i in range(1, sample_count + 1):
		var point := from_position.lerp(to_position, float(i) / float(sample_count))
		var grid_id := _world_to_grid(point)
		if grid_id == last_id:
			continue
		last_id = grid_id
		if not _is_grid_id_valid(grid_id) or _path_grid.is_point_solid(grid_id):
			return false
	return true
