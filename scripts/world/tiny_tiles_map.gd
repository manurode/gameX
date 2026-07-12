extends TileMapLayer

class_name TinyTilesMap

enum GroundTile {
	GRASS_A,
	GRASS_B,
	GRASS_C,
	GRASS_D,
	WATER,
	MAIN,
}

const TILE_SIZE := Vector2i(256, 128)
const MAP_SIZE := Vector2i(14, 12)

const GROUND_LAYOUT: Array[String] = [
	"aaaaaaaaaaaaaa",
	"aaabbbaaaaabaa",
	"aaabbwwwwbbbaa",
	"aaaabwwwwbbbaa",
	"aaaaaabbbbbaaa",
	"aaacccaaaabbba",
	"aaacccaaaabbba",
	"aaaaaaaddddaaa",
	"aaaaaaaddddaaa",
	"aaaaaaaaaaaaaa",
	"aaaaaaaaaaaaaa",
	"aaaaaaaaaaaaaa",
]

const WATER_CELLS: Array[Vector2i] = [
	Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
	Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3),
]

var _pressed_cells: Dictionary = {}


func _ready() -> void:
	tile_set = _build_tileset()
	y_sort_enabled = false
	_paint_ground()
	call_deferred("_notify_world_ready")


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tileset.tile_size = TILE_SIZE
	tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT

	var grass_paths: Array[String] = [
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Grass/env_grass_a.png",
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Grass/env_grass_b.png",
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Grass/env_grass_c.png",
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Grass/env_grass_d.png",
	]
	var extra_paths: Array[String] = [
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Main/env_terrain_water.png",
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Main/env_terrain_main.png",
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


func _paint_ground() -> void:
	for y in GROUND_LAYOUT.size():
		var row := GROUND_LAYOUT[y]
		for x in row.length():
			var symbol: String = row[x]
			var source_id := _symbol_to_source(symbol)
			if source_id >= 0:
				set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func _symbol_to_source(symbol: String) -> int:
	match symbol:
		"a":
			return GroundTile.GRASS_A
		"b":
			return GroundTile.GRASS_B
		"c":
			return GroundTile.GRASS_C
		"d":
			return GroundTile.GRASS_D
		"w":
			return GroundTile.WATER
		"m":
			return GroundTile.MAIN
		_:
			return -1


func get_map_bounds() -> Rect2:
	var used := get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2(MAP_SIZE) * Vector2(TILE_SIZE) * 0.5)

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
	var source_id := get_cell_source_id(cell)
	if source_id == GroundTile.WATER:
		return GroundTile.WATER
	return GroundTile.GRASS_A


func is_water_at(world_pos: Vector2) -> bool:
	return get_cell_source_id(get_cell_at_world(world_pos)) == GroundTile.WATER


func press_grass_at(world_pos: Vector2, duration: float = 0.35) -> void:
	var cell := get_cell_at_world(world_pos)
	if get_cell_source_id(cell) == GroundTile.WATER:
		return
	if cell in _pressed_cells:
		return

	var original_source := get_cell_source_id(cell)
	set_cell(cell, GroundTile.GRASS_D, Vector2i.ZERO)
	_pressed_cells[cell] = original_source

	var timer := get_tree().create_timer(duration)
	var captured_cell := cell
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		if captured_cell in _pressed_cells:
			set_cell(captured_cell, _pressed_cells[captured_cell], Vector2i.ZERO)
			_pressed_cells.erase(captured_cell)
	)


func get_water_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in WATER_CELLS:
		if get_cell_source_id(cell) == GroundTile.WATER:
			cells.append(cell)
	return cells


func _notify_world_ready() -> void:
	var node: Node = self
	while node != null:
		if node.has_method("on_ground_ready"):
			node.call("on_ground_ready", self)
			return
		node = node.get_parent()
