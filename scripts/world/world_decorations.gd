extends Node2D

const DECORATION_DEFS: Array[Dictionary] = [
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(1, 1),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_pines.png",
		"cell": Vector2i(12, 1),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(13, 4),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_a.png",
		"cell": Vector2i(2, 8),
		"blocks": true,
		"block_half": Vector2(55.0, 30.0),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_b.png",
		"cell": Vector2i(10, 8),
		"blocks": true,
		"block_half": Vector2(55.0, 30.0),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_a.png",
		"cell": Vector2i(0, 5),
		"blocks": true,
		"block_half": Vector2(65.0, 40.0),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_b.png",
		"cell": Vector2i(13, 6),
		"blocks": true,
		"block_half": Vector2(65.0, 40.0),
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_a.png",
		"cell": Vector2i(3, 5),
		"blocks": false,
		"slow_mult": 0.85,
		"slow_radius": 40.0,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_b.png",
		"cell": Vector2i(4, 5),
		"blocks": false,
		"slow_mult": 0.85,
		"slow_radius": 40.0,
	},
]

var _ground_layer: TileMapLayer
var _obstacles: Array[TerrainObstacle] = []


func setup(ground_layer: TileMapLayer) -> void:
	_ground_layer = ground_layer
	y_sort_enabled = true
	_spawn_decorations()


func get_obstacles() -> Array[TerrainObstacle]:
	return _obstacles


func _spawn_decorations() -> void:
	if _ground_layer == null:
		return

	for def in DECORATION_DEFS:
		var texture: Texture2D = load(def.path)
		if texture == null:
			continue

		var obstacle := TerrainObstacle.new()
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		var block_half: Vector2 = def.get("block_half", Vector2(40.0, 25.0))
		obstacle.setup(
			texture,
			_ground_layer.map_to_local(def.cell),
			offset,
			def.get("blocks", false),
			def.get("slow_mult", 1.0),
			def.get("slow_radius", 0.0),
			block_half
		)
		obstacle.add_to_group("terrain_obstacles")
		add_child(obstacle)
		_obstacles.append(obstacle)
