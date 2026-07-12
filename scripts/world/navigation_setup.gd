extends NavigationRegion2D

var _ground_layer: TinyTilesMap


func setup_from_ground(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer
	var bounds := ground_layer.get_map_bounds()
	var padding := Vector2(64.0, 64.0)
	var expanded := bounds.grow_individual(padding.x, padding.y, padding.x, padding.y)

	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.add_outline(PackedVector2Array([
		expanded.position,
		Vector2(expanded.end.x, expanded.position.y),
		expanded.end,
		Vector2(expanded.position.x, expanded.end.y),
	]))
	navigation_polygon.make_polygons_from_outlines()
	self.navigation_polygon = navigation_polygon
