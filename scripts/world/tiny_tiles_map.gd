extends TileMapLayer

class_name TinyTilesMap

signal terrain_generated(seed: int)

enum GroundTile {
	GRASS_A,
	WATER,
	MAIN,
}

## Atlas source IDs: 0..11 floor variants, 12 press, 13 water, 14 main.
const GRASS_VARIANT_COUNT := 12
const GRASS_PRESS := 12
const TILE_SIZE := Vector2i(256, 128)

@export var fixed_seed: int = 0

var _pressed_cells: Dictionary = {}
var _map_size := ProceduralMapGenerator.DEFAULT_MAP_SIZE
var _world_seed := 0
var _town_center_cell := Vector2i.ZERO
var _ground_tiles: Array[int] = []
var _water_cells: Array[Vector2i] = []
var _water_set: Dictionary = {}
var _resource_placements: Array[Dictionary] = []
var _decoration_placements: Array[Dictionary] = []


func _ready() -> void:
	material = null
	tile_set = _build_tileset()
	y_sort_enabled = false
	regenerate(fixed_seed)
	call_deferred("_notify_world_ready")


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tileset.tile_size = TILE_SIZE
	tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT

	# Painterly floor variants (tone-matched, shared edge band) + press + water.
	var grass_paths: Array[String] = []
	for i in GRASS_VARIANT_COUNT:
		grass_paths.append(_resolve_grass_path("grass_%02d" % i))
	grass_paths.append(_resolve_grass_path("grass_press"))
	var extra_paths: Array[String] = [
		"res://assets/tilesets/mediterranean/Terrain/water.png",
		"res://assets/tilesets/mediterranean/Terrain/main.png",
	]

	var all_paths: Array[String] = []
	all_paths.assign(grass_paths)
	all_paths.append_array(extra_paths)

	for path_idx in all_paths.size():
		var path: String = all_paths[path_idx]
		var texture: Texture2D = load(path)
		if texture == null:
			continue

		var source := TileSetAtlasSource.new()
		source.texture = texture
		source.texture_region_size = TILE_SIZE
		source.create_tile(Vector2i.ZERO)
		tileset.add_source(source, path_idx)

	return tileset


func _resolve_grass_path(stem: String) -> String:
	var field_path := "res://assets/tilesets/mediterranean/Terrain/%s_field.png" % stem
	if ResourceLoader.exists(field_path):
		return field_path
	return "res://assets/tilesets/mediterranean/Terrain/%s.png" % stem


func regenerate(seed_override: int = 0) -> void:
	var generator := ProceduralMapGenerator.new()
	generator.map_size = GameSettings.get_map_size()
	var result := generator.generate(seed_override)
	_map_size = result["map_size"]
	_world_seed = result["seed"]
	_town_center_cell = result["town_center_cell"]
	_ground_tiles.assign(result["ground_tiles"])
	_water_cells.assign(result["water_cells"])
	_water_set = result["water_set"].duplicate()
	_resource_placements.assign(result["resource_placements"])
	_decoration_placements.assign(result["decoration_placements"])
	_pressed_cells.clear()
	clear()
	_paint_generated_ground()
	terrain_generated.emit(_world_seed)


func _paint_generated_ground() -> void:
	for y in _map_size.y:
		for x in _map_size.x:
			var cell := Vector2i(x, y)
			var source_id := _ground_tiles[_cell_index(cell)]
			set_cell(cell, source_id, Vector2i.ZERO)


func get_map_bounds() -> Rect2:
	var used := get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2(_map_size) * Vector2(TILE_SIZE) * 0.5)

	var corners: Array[Vector2] = [
		map_to_local(used.position),
		map_to_local(used.position + Vector2i(used.size.x, 0)),
		map_to_local(used.position + Vector2i(0, used.size.y)),
		map_to_local(used.position + used.size),
	]
	var min_pos: Vector2 = corners[0]
	var max_pos: Vector2 = corners[0]
	for corner in corners:
		min_pos = min_pos.min(corner)
		max_pos = max_pos.max(corner)

	return Rect2(min_pos, max_pos - min_pos)


func get_cell_at_world(world_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(world_pos))


func get_ground_type_at(world_pos: Vector2) -> GroundTile:
	var cell := get_cell_at_world(world_pos)
	if cell in _water_set:
		return GroundTile.WATER
	return GroundTile.GRASS_A


func is_water_at(world_pos: Vector2) -> bool:
	return get_cell_at_world(world_pos) in _water_set


func is_walkable_cell(cell: Vector2i) -> bool:
	return is_cell_in_bounds(cell) and cell not in _water_set


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y


func press_grass_at(world_pos: Vector2) -> void:
	var cell := get_cell_at_world(world_pos)
	if not is_walkable_cell(cell):
		return

	if cell in _pressed_cells:
		_pressed_cells[cell]["refs"] += 1
		return

	var original_source := get_cell_source_id(cell)
	if original_source == GRASS_PRESS:
		_pressed_cells[cell] = {"source": original_source, "refs": 1}
		return

	set_cell(cell, GRASS_PRESS, Vector2i.ZERO)
	_pressed_cells[cell] = {"source": original_source, "refs": 1}


func release_grass_at_cell(cell: Vector2i) -> void:
	if cell not in _pressed_cells:
		return

	_pressed_cells[cell]["refs"] -= 1
	if _pressed_cells[cell]["refs"] > 0:
		return

	var original_source: int = _pressed_cells[cell]["source"]
	_pressed_cells.erase(cell)
	if original_source != GRASS_PRESS:
		set_cell(cell, original_source, Vector2i.ZERO)


func get_water_cells() -> Array[Vector2i]:
	return _water_cells.duplicate()


func get_map_size() -> Vector2i:
	return _map_size


func get_world_seed() -> int:
	return _world_seed


func get_town_center_cell() -> Vector2i:
	return _town_center_cell


func get_resource_placements() -> Array[Dictionary]:
	return _resource_placements.duplicate(true)


func get_decoration_placements() -> Array[Dictionary]:
	return _decoration_placements.duplicate(true)


func get_walkable_edge_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in _map_size.x:
		var top := Vector2i(x, 0)
		var bottom := Vector2i(x, _map_size.y - 1)
		if is_walkable_cell(top):
			cells.append(top)
		if bottom != top and is_walkable_cell(bottom):
			cells.append(bottom)
	for y in range(1, _map_size.y - 1):
		var left := Vector2i(0, y)
		var right := Vector2i(_map_size.x - 1, y)
		if is_walkable_cell(left):
			cells.append(left)
		if right != left and is_walkable_cell(right):
			cells.append(right)
	return cells


func _cell_index(cell: Vector2i) -> int:
	return cell.y * _map_size.x + cell.x


func _notify_world_ready() -> void:
	var node: Node = self
	while node != null:
		if node.has_method("on_ground_ready"):
			node.call("on_ground_ready", self)
			return
		node = node.get_parent()
