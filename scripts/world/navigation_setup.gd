extends NavigationRegion2D

const MAP_SIZE := Vector2(480, 272)

func _ready() -> void:
	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.add_outline(PackedVector2Array([
		Vector2.ZERO,
		Vector2(MAP_SIZE.x, 0.0),
		Vector2(MAP_SIZE),
		Vector2(0.0, MAP_SIZE.y),
	]))
	navigation_polygon.make_polygons_from_outlines()
	self.navigation_polygon = navigation_polygon
