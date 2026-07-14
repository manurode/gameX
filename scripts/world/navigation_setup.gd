extends NavigationRegion2D

const SECTOR_SIZE := 16
const REBUILD_DEBOUNCE := 0.12

var _ground_layer: TinyTilesMap
var _sector_regions: Dictionary = {}
var _dirty_sectors: Dictionary = {}
var _obstacles: Array = []
var _buildings: Array = []
var _rebuild_timer: Timer


func setup_from_ground(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer
	navigation_polygon = null
	_create_sector_regions()


func rebuild_navigation(obstacles: Array = [], buildings: Array = []) -> void:
	if _ground_layer == null:
		return
	update_sources(obstacles, buildings)
	for sector_key in _sector_regions:
		_rebuild_sector(sector_key)
	_dirty_sectors.clear()


func update_sources(obstacles: Array, buildings: Array) -> void:
	_obstacles = obstacles.duplicate()
	_buildings = buildings.duplicate()


func request_rebuild_at(world_position: Vector2) -> void:
	if _ground_layer == null:
		return
	var cell := _ground_layer.get_cell_at_world(world_position)
	var sector := Vector2i(
		floori(float(cell.x) / float(SECTOR_SIZE)),
		floori(float(cell.y) / float(SECTOR_SIZE))
	)
	for y in range(sector.y - 1, sector.y + 2):
		for x in range(sector.x - 1, sector.x + 2):
			var key := Vector2i(x, y)
			if key in _sector_regions:
				_dirty_sectors[key] = true
	_ensure_rebuild_timer()
	_rebuild_timer.start(REBUILD_DEBOUNCE)


func _create_sector_regions() -> void:
	for region in _sector_regions.values():
		if is_instance_valid(region):
			region.queue_free()
	_sector_regions.clear()
	_dirty_sectors.clear()

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
			_mark_outline_cells(
				(obstacle as TerrainObstacle).get_nav_block_outline(),
				cell_rect,
				blocked
			)
	# Buildings use tight physical collision only; coarse nav cells created false dead zones.
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
