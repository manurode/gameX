extends NavigationRegion2D

var _ground_layer: TinyTilesMap


func setup_from_ground(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer


func rebuild_navigation(obstacles: Array = [], buildings: Array = []) -> void:
	if _ground_layer == null:
		return

	var bounds := _ground_layer.get_map_bounds()
	var padding := Vector2(64.0, 64.0)
	var expanded := bounds.grow_individual(padding.x, padding.y, padding.x, padding.y)

	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.add_outline(PackedVector2Array([
		expanded.position,
		Vector2(expanded.end.x, expanded.position.y),
		expanded.end,
		Vector2(expanded.position.x, expanded.end.y),
	]))

	for cell in _ground_layer.get_water_cells():
		navigation_polygon.add_outline(_cell_block_outline(cell))

	for obstacle in obstacles:
		if obstacle is TerrainObstacle and (obstacle as TerrainObstacle).blocks_movement:
			var outline: PackedVector2Array = (obstacle as TerrainObstacle).get_nav_block_outline()
			if outline.size() >= 3:
				navigation_polygon.add_outline(outline)

	for building in buildings:
		if building is Building:
			var built := building as Building
			if built.blocks_navigation and built.building_state == Building.BuildingState.ACTIVE:
				var outline: PackedVector2Array = built.get_nav_block_outline()
				if outline.size() >= 3:
					navigation_polygon.add_outline(outline)

	navigation_polygon.make_polygons_from_outlines()
	self.navigation_polygon = navigation_polygon


func _cell_block_outline(cell: Vector2i) -> PackedVector2Array:
	var center := _ground_layer.map_to_local(cell)
	var half := Vector2(90.0, 50.0)
	return PackedVector2Array([
		center + Vector2(-half.x, 0.0),
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
	])
