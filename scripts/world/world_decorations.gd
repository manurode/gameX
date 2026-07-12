extends Node2D

const DECORATION_DEFS: Array[Dictionary] = [
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(1, 1),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_pines.png",
		"cell": Vector2i(12, 1),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(13, 4),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_a.png",
		"cell": Vector2i(2, 8),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_b.png",
		"cell": Vector2i(10, 8),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_a.png",
		"cell": Vector2i(0, 5),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_b.png",
		"cell": Vector2i(13, 6),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_a.png",
		"cell": Vector2i(3, 5),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_b.png",
		"cell": Vector2i(4, 5),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Buildings/House Small/env_buildings_house_small.png",
		"cell": Vector2i(9, 2),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Mill/env_buildings_mill.png",
		"cell": Vector2i(11, 9),
	},
]

var _ground_layer: TileMapLayer


func setup(ground_layer: TileMapLayer) -> void:
	_ground_layer = ground_layer
	y_sort_enabled = true
	_spawn_decorations()


func _spawn_decorations() -> void:
	if _ground_layer == null:
		return

	for def in DECORATION_DEFS:
		var texture: Texture2D = load(def.path)
		if texture == null:
			continue

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = _ground_layer.map_to_local(def.cell)
		sprite.offset = Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		sprite.y_sort_enabled = true
		add_child(sprite)
