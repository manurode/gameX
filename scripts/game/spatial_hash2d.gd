class_name SpatialHash2D
extends RefCounted

## Uniform grid for nearby-entity queries. Rebuild once per tick, then query cells.

var cell_size: float = 64.0
var _cells: Dictionary = {}  # Vector2i -> Array


func clear() -> void:
	_cells.clear()


func insert(item: Variant, world_position: Vector2) -> void:
	var key := cell_key(world_position)
	var bucket: Array = _cells.get(key, [])
	if bucket.is_empty():
		_cells[key] = bucket
	bucket.append(item)


func cell_key(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size),
		floori(world_position.y / cell_size)
	)


func query_radius(world_position: Vector2, radius: float) -> Array:
	var result: Array = []
	if radius <= 0.0:
		return result
	var cell_radius := ceili(radius / cell_size)
	var center := cell_key(world_position)
	for y in range(center.y - cell_radius, center.y + cell_radius + 1):
		for x in range(center.x - cell_radius, center.x + cell_radius + 1):
			var bucket: Array = _cells.get(Vector2i(x, y), [])
			if not bucket.is_empty():
				result.append_array(bucket)
	return result


func query_radius_into(world_position: Vector2, radius: float, out: Array) -> void:
	out.clear()
	if radius <= 0.0:
		return
	var cell_radius := ceili(radius / cell_size)
	var center := cell_key(world_position)
	for y in range(center.y - cell_radius, center.y + cell_radius + 1):
		for x in range(center.x - cell_radius, center.x + cell_radius + 1):
			var bucket: Array = _cells.get(Vector2i(x, y), [])
			for item in bucket:
				out.append(item)
