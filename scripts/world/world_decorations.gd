extends Node2D

const TREE_PATHS: Array[String] = [
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_oaks.png",
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Trees/env_trees_pines.png",
]
const STONE_PATHS: Array[String] = [
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_a.png",
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Mountains/env_mountains_b.png",
]
const HILL_PATHS: Array[String] = [
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_a.png",
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Hills/env_hills_b.png",
]
const WHEAT_PATHS: Array[String] = [
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_a.png",
	"res://assets/tilesets/tiny_tiles/Environment/Terrain/Wheat/env_wheat_b.png",
]

var _ground_layer: TileMapLayer
var _obstacles: Array[TerrainObstacle] = []
var _resource_nodes: Array[ResourceNode] = []


func setup(ground_layer: TinyTilesMap) -> void:
	_clear_generated_content()
	_ground_layer = ground_layer
	y_sort_enabled = true
	_spawn_resources(ground_layer.get_resource_placements())
	_spawn_decorations(ground_layer.get_decoration_placements())


func get_obstacles() -> Array[TerrainObstacle]:
	return _obstacles


func get_resource_nodes() -> Array[ResourceNode]:
	return _resource_nodes


func _spawn_resources(placements: Array[Dictionary]) -> void:
	if _ground_layer == null:
		return

	for placement in placements:
		var kind: String = placement.get("kind", "")
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var world_pos := _ground_layer.map_to_local(cell)
		if kind == "food":
			_spawn_crop_field(placement, world_pos)
			continue

		var paths := TREE_PATHS if kind == "wood" else STONE_PATHS
		var variant := clampi(placement.get("variant", 0), 0, paths.size() - 1)
		var texture: Texture2D = load(paths[variant])
		if texture == null:
			continue
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		var node := ResourceNode.new()
		var resource_kind := (
			ResourceNode.ResourceKind.WOOD
			if kind == "wood"
			else ResourceNode.ResourceKind.STONE
		)
		node.setup(texture, world_pos, resource_kind, placement.get("amount", 100), offset)
		add_child(node)
		_resource_nodes.append(node)


func _spawn_crop_field(placement: Dictionary, world_pos: Vector2) -> void:
	var textures: Array[Texture2D] = []
	for path in WHEAT_PATHS:
		textures.append(load(path))
	var node := ResourceNode.new()
	node.setup_crop_field(
		world_pos,
		textures,
		placement.get("columns", 3),
		placement.get("rows", 2),
		placement.get("amount", 200)
	)
	add_child(node)
	_resource_nodes.append(node)


func _spawn_decorations(placements: Array[Dictionary]) -> void:
	if _ground_layer == null:
		return
	for placement in placements:
		var variant := clampi(placement.get("variant", 0), 0, HILL_PATHS.size() - 1)
		var texture: Texture2D = load(HILL_PATHS[variant])
		if texture == null:
			continue
		var world_pos := _ground_layer.map_to_local(placement.get("cell", Vector2i.ZERO))
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		var obstacle := TerrainObstacle.new()
		obstacle.setup(
			texture,
			world_pos,
			offset,
			placement.get("blocks", true),
			1.0,
			0.0,
			Vector2(55.0, 30.0)
		)
		obstacle.add_to_group("terrain_obstacles")
		add_child(obstacle)
		_obstacles.append(obstacle)


func _clear_generated_content() -> void:
	_obstacles.clear()
	_resource_nodes.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
