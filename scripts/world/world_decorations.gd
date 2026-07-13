extends Node2D

const DECORATION_DEFS: Array[Dictionary] = [
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(1, 1),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
		"resource_type": "wood",
		"resource_amount": 100,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_pines.png",
		"cell": Vector2i(12, 1),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
		"resource_type": "wood",
		"resource_amount": 100,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(13, 4),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
		"resource_type": "wood",
		"resource_amount": 100,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
		"cell": Vector2i(2, 2),
		"blocks": false,
		"slow_mult": 0.5,
		"slow_radius": 90.0,
		"resource_type": "wood",
		"resource_amount": 100,
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
		"resource_type": "stone",
		"resource_amount": 120,
	},
	{
		"path": "res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_b.png",
		"cell": Vector2i(13, 6),
		"blocks": true,
		"block_half": Vector2(65.0, 40.0),
		"resource_type": "stone",
		"resource_amount": 120,
	},
]

const CROP_FIELDS: Array[Dictionary] = [
	{
		"origin_cell": Vector2i(2, 4),
		"columns": 4,
		"rows": 3,
		"amount": 240,
	},
	{
		"origin_cell": Vector2i(5, 5),
		"columns": 3,
		"rows": 2,
		"amount": 160,
	},
]

var _ground_layer: TileMapLayer
var _obstacles: Array[TerrainObstacle] = []
var _resource_nodes: Array[ResourceNode] = []


func setup(ground_layer: TileMapLayer) -> void:
	_ground_layer = ground_layer
	y_sort_enabled = true
	_spawn_crop_fields()
	_spawn_decorations()


func get_obstacles() -> Array[TerrainObstacle]:
	return _obstacles


func get_resource_nodes() -> Array[ResourceNode]:
	return _resource_nodes


func _spawn_crop_fields() -> void:
	if _ground_layer == null:
		return

	var wheat_a: Texture2D = load(
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_a.png"
	)
	var wheat_b: Texture2D = load(
		"res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_b.png"
	)
	var textures: Array[Texture2D] = [wheat_a, wheat_b]

	for field_def in CROP_FIELDS:
		var origin_cell: Vector2i = field_def.origin_cell
		var columns: int = field_def.columns
		var rows: int = field_def.rows
		var center_cell := origin_cell + Vector2i(columns / 2, rows / 2)
		var center_pos := _ground_layer.map_to_local(center_cell)

		var node := ResourceNode.new()
		node.setup_crop_field(center_pos, textures, columns, rows, field_def.get("amount", 200))
		add_child(node)
		_resource_nodes.append(node)


func _spawn_decorations() -> void:
	if _ground_layer == null:
		return

	for def in DECORATION_DEFS:
		var texture: Texture2D = load(def.path)
		if texture == null:
			continue

		var world_pos := _ground_layer.map_to_local(def.cell)
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)

		if def.has("resource_type"):
			var node := ResourceNode.new()
			var kind := ResourceNode.ResourceKind.WOOD
			match def.resource_type:
				"food":
					kind = ResourceNode.ResourceKind.FOOD
				"stone":
					kind = ResourceNode.ResourceKind.STONE
			node.setup(texture, world_pos, kind, def.get("resource_amount", 100), offset)
			add_child(node)
			_resource_nodes.append(node)
			continue

		if def.get("blocks", false) or def.get("slow_mult", 1.0) < 1.0:
			var obstacle := TerrainObstacle.new()
			var block_half: Vector2 = def.get("block_half", Vector2(40.0, 25.0))
			obstacle.setup(
				texture,
				world_pos,
				offset,
				def.get("blocks", false),
				def.get("slow_mult", 1.0),
				def.get("slow_radius", 0.0),
				block_half
			)
			obstacle.add_to_group("terrain_obstacles")
			add_child(obstacle)
			_obstacles.append(obstacle)
