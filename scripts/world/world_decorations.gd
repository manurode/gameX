extends Node

const TREE_PATHS: Array[String] = [
	"res://assets/tilesets/mediterranean/Decor/forest_a.png",
	"res://assets/tilesets/mediterranean/Decor/forest_b.png",
	"res://assets/tilesets/mediterranean/Decor/forest_c.png",
]
const GOLD_VEIN_PATHS: Array[String] = [
	"res://assets/tilesets/mediterranean/Decor/rocks.png",
	"res://assets/tilesets/mediterranean/Decor/rocks.png",
]
const HILL_PATHS: Array[String] = [
	"res://assets/tilesets/mediterranean/Decor/mountain_a.png",
	"res://assets/tilesets/mediterranean/Decor/mountain_b.png",
	"res://assets/tilesets/mediterranean/Decor/mountain_c.png",
]
const LAKE_PATHS: Array[String] = [
	"res://assets/tilesets/mediterranean/Decor/lake_a.png",
	"res://assets/tilesets/mediterranean/Decor/lake_b.png",
	"res://assets/tilesets/mediterranean/Decor/lake_c.png",
]
const FOREST_SLOW_MULTIPLIER := 0.62
const FOREST_SLOW_RADIUS := 260.0
const FOREST_BLOCK_HALF := Vector2(260.0, 120.0)
const FOREST_PICK_RADIUS := 240.0
## One large forest sprite covering many cells (same idea as mountains).
const FOREST_VISUAL_SCALE := 1.28
## Pull tall props north in Y-sort so edge canopy/cliffs don't cover buildings in front.
const FOREST_Y_SORT_BIAS := 140.0
const MOUNTAIN_Y_SORT_BIAS := 160.0
const MOUNTAIN_PICK_RADIUS := 220.0
const MOUNTAIN_VISUAL_SCALE := 1.32
const GOLD_VEIN_VISUAL_SCALE := 1.15
## Organic lake bodies (same oversized-sprite pattern as forests/mountains).
const LAKE_VISUAL_SCALE := 1.30
const LAKE_Y_SORT_BIAS := 100.0
## Bottom fraction of the sprite used as solid footprint (peaks stay walkable behind).
const MOUNTAIN_FOOTPRINT_BAND := 0.55
const GOLD_FOOTPRINT_BAND := 0.65
## Fallback diamond if alpha polygon extraction fails.
const MOUNTAIN_FALLBACK_HALF := Vector2(260.0, 120.0)
const GOLD_FALLBACK_HALF := Vector2(70.0, 42.0)
const LAKE_FALLBACK_HALF := Vector2(280.0, 130.0)
## Farm plot is painted into mill.png; gather zone sits on that front plot.
const MILL_FARM_OFFSET := Vector2(0.0, 22.0)
const MILL_FARM_HALF_SIZE := Vector2(44.0, 26.0)
var _ground_layer: TileMapLayer
var _entity_parent: Node2D
var _obstacles: Array[TerrainObstacle] = []
var _resource_nodes: Array[ResourceNode] = []


func setup(ground_layer: TinyTilesMap, entity_parent: Node2D) -> void:
	add_to_group("world_decorations")
	_clear_generated_content()
	_ground_layer = ground_layer
	_entity_parent = entity_parent
	if _entity_parent != null:
		_entity_parent.y_sort_enabled = true
	_spawn_lakes(ground_layer.get_lake_placements())
	_spawn_resources(ground_layer.get_resource_placements())
	_spawn_decorations(ground_layer.get_decoration_placements())


func get_obstacles() -> Array[TerrainObstacle]:
	return _obstacles


func get_resource_nodes() -> Array[ResourceNode]:
	return _resource_nodes


func spawn_mill_wheat_for_building(building: Building) -> ResourceNode:
	if building == null or not is_instance_valid(building) or _entity_parent == null:
		return null
	if building.has_meta("mill_wheat_node"):
		var existing = building.get_meta("mill_wheat_node")
		if existing is ResourceNode and is_instance_valid(existing):
			return existing

	var def := BuildingDatabase.get_definition(building.building_type_id)
	var farm_offset: Vector2 = def.get("farm_offset", MILL_FARM_OFFSET)
	var farm_half: Vector2 = def.get("farm_half_size", MILL_FARM_HALF_SIZE)
	var world_pos := building.global_position + farm_offset
	var node := ResourceNode.new()
	node.setup_mill_farm_zone(world_pos, farm_half)
	_entity_parent.add_child(node)
	_resource_nodes.append(node)
	building.set_meta("mill_wheat_node", node)
	return node


func remove_mill_wheat_for_building(building: Building) -> void:
	if building == null or not building.has_meta("mill_wheat_node"):
		return
	var node = building.get_meta("mill_wheat_node")
	if not node is ResourceNode or not is_instance_valid(node):
		building.remove_meta("mill_wheat_node")
		return
	_resource_nodes.erase(node)
	node.queue_free()
	building.remove_meta("mill_wheat_node")


func _spawn_resources(placements: Array[Dictionary]) -> void:
	if _ground_layer == null or _entity_parent == null:
		return

	for placement in placements:
		var kind: String = placement.get("kind", "")
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var world_pos := _ground_layer.map_to_local(cell)

		var paths := _paths_for_kind(kind)
		if paths.is_empty():
			continue
		var variant := clampi(placement.get("variant", 0), 0, paths.size() - 1)
		var texture: Texture2D = load(paths[variant])
		if texture == null:
			continue
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		var visual_scale := _visual_scale_for_kind(kind)
		var node := ResourceNode.new()
		var resource_kind := (
			ResourceNode.ResourceKind.WOOD
			if kind == "wood"
			else ResourceNode.ResourceKind.GOLD
		)
		var sort_bias := _sort_bias_for_kind(kind)
		node.setup(
			texture,
			world_pos,
			resource_kind,
			placement.get("amount", 100),
			offset,
			visual_scale,
			sort_bias
		)
		if kind == "wood":
			node.pick_radius = FOREST_PICK_RADIUS
		elif kind == "gold_mountain":
			node.pick_radius = MOUNTAIN_PICK_RADIUS
		_entity_parent.add_child(node)
		_resource_nodes.append(node)
		var obstacle := _spawn_resource_terrain(kind, texture, world_pos, offset, visual_scale)
		if obstacle != null:
			node.set_terrain_obstacle(obstacle)


func _paths_for_kind(kind: String) -> Array[String]:
	match kind:
		"wood":
			return TREE_PATHS
		"gold":
			return GOLD_VEIN_PATHS
		"gold_mountain":
			return HILL_PATHS
		_:
			var empty: Array[String] = []
			return empty


func _visual_scale_for_kind(kind: String) -> float:
	match kind:
		"wood":
			return FOREST_VISUAL_SCALE
		"gold_mountain":
			return MOUNTAIN_VISUAL_SCALE
		"gold":
			return GOLD_VEIN_VISUAL_SCALE
		_:
			return 1.0


func _sort_bias_for_kind(kind: String) -> float:
	match kind:
		"wood":
			return FOREST_Y_SORT_BIAS
		"gold_mountain":
			return MOUNTAIN_Y_SORT_BIAS
		_:
			return 0.0


func _spawn_resource_terrain(
	kind: String,
	texture: Texture2D,
	world_pos: Vector2,
	offset: Vector2,
	visual_scale: float = 1.0
) -> TerrainObstacle:
	if _entity_parent == null:
		return null
	var obstacle := TerrainObstacle.new()
	if kind == "wood":
		obstacle.setup(
			texture,
			world_pos,
			offset,
			false,
			FOREST_SLOW_MULTIPLIER,
			FOREST_SLOW_RADIUS,
			FOREST_BLOCK_HALF,
			false,
			visual_scale
		)
	else:
		var band := GOLD_FOOTPRINT_BAND if kind == "gold" else MOUNTAIN_FOOTPRINT_BAND
		var fallback := GOLD_FALLBACK_HALF if kind == "gold" else MOUNTAIN_FALLBACK_HALF
		obstacle.setup(
			texture,
			world_pos,
			offset,
			true,
			1.0,
			0.0,
			fallback,
			false,
			visual_scale,
			band
		)
	obstacle.add_to_group("terrain_obstacles")
	_entity_parent.add_child(obstacle)
	_obstacles.append(obstacle)
	return obstacle


func _spawn_lakes(placements: Array[Dictionary]) -> void:
	if _ground_layer == null or _entity_parent == null:
		return
	for placement in placements:
		var variant := clampi(placement.get("variant", 0), 0, LAKE_PATHS.size() - 1)
		var texture: Texture2D = load(LAKE_PATHS[variant])
		if texture == null:
			continue
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var world_pos := _ground_layer.map_to_local(cell)
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		# Same sort bias as mountains; water body blocks like TerrainObstacle mountains.
		var sort_dy := 64.0 * LAKE_VISUAL_SCALE - LAKE_Y_SORT_BIAS
		var draw_offset := offset - Vector2(0.0, sort_dy / LAKE_VISUAL_SCALE)
		var lake := TerrainObstacle.new()
		lake.name = "Lake"
		lake.setup(
			texture,
			world_pos + Vector2(0.0, sort_dy),
			draw_offset,
			true,
			1.0,
			0.0,
			LAKE_FALLBACK_HALF,
			true,
			LAKE_VISUAL_SCALE,
			0.0,
			false,
			true
		)
		lake.add_to_group("terrain_obstacles")
		_entity_parent.add_child(lake)
		_obstacles.append(lake)


func _spawn_decorations(placements: Array[Dictionary]) -> void:
	if _ground_layer == null or _entity_parent == null:
		return
	for placement in placements:
		var variant := clampi(placement.get("variant", 0), 0, HILL_PATHS.size() - 1)
		var texture: Texture2D = load(HILL_PATHS[variant])
		if texture == null:
			continue
		var world_pos := _ground_layer.map_to_local(placement.get("cell", Vector2i.ZERO))
		var offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
		# Same sort bias as gold_mountain resources (no Node2D y_sort_origin).
		var sort_dy := 64.0 * MOUNTAIN_VISUAL_SCALE - MOUNTAIN_Y_SORT_BIAS
		var draw_offset := offset - Vector2(0.0, sort_dy / MOUNTAIN_VISUAL_SCALE)
		var obstacle := TerrainObstacle.new()
		obstacle.setup(
			texture,
			world_pos + Vector2(0.0, sort_dy),
			draw_offset,
			placement.get("blocks", true),
			1.0,
			0.0,
			MOUNTAIN_FALLBACK_HALF,
			true,
			MOUNTAIN_VISUAL_SCALE,
			MOUNTAIN_FOOTPRINT_BAND
		)
		obstacle.add_to_group("terrain_obstacles")
		_entity_parent.add_child(obstacle)
		_obstacles.append(obstacle)


func _clear_generated_content() -> void:
	for obstacle in _obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	for node in _resource_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_obstacles.clear()
	_resource_nodes.clear()
