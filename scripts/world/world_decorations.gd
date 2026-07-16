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
const FOREST_SLOW_MULTIPLIER := 0.62
const FOREST_SLOW_RADIUS := 260.0
const FOREST_BLOCK_HALF := Vector2(210.0, 130.0)
const FOREST_PICK_RADIUS := 240.0
const FOREST_VISUAL_SCALE := 1.22
const MOUNTAIN_PICK_RADIUS := 220.0
const MOUNTAIN_VISUAL_SCALE := 1.32
const GOLD_VEIN_VISUAL_SCALE := 1.15
## Ground-plane factors: block only the rocky/ore base, not tall sprite AABB corners.
const MOUNTAIN_GROUND_WIDTH_FACTOR := 0.20
const MOUNTAIN_GROUND_HEIGHT_FACTOR := 0.10
const GOLD_GROUND_WIDTH_FACTOR := 0.22
const GOLD_GROUND_HEIGHT_FACTOR := 0.14
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
		node.setup(texture, world_pos, resource_kind, placement.get("amount", 100), offset, visual_scale)
		if kind == "wood":
			node.pick_radius = FOREST_PICK_RADIUS
		elif kind == "gold_mountain":
			node.pick_radius = MOUNTAIN_PICK_RADIUS
		_entity_parent.add_child(node)
		_resource_nodes.append(node)
		_spawn_resource_terrain(kind, texture, world_pos, offset, visual_scale)


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


func _spawn_resource_terrain(
	kind: String,
	texture: Texture2D,
	world_pos: Vector2,
	offset: Vector2,
	visual_scale: float = 1.0
) -> void:
	if _entity_parent == null:
		return
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
		obstacle.setup(
			texture,
			world_pos,
			offset,
			true,
			1.0,
			0.0,
			_ground_block_half_for_kind(kind, texture, visual_scale),
			false,
			visual_scale
		)
	obstacle.add_to_group("terrain_obstacles")
	_entity_parent.add_child(obstacle)
	_obstacles.append(obstacle)


func _ground_block_half_for_kind(kind: String, texture: Texture2D, visual_scale: float) -> Vector2:
	if texture == null:
		return Vector2(40.0, 25.0)
	var size := texture.get_size() * visual_scale
	match kind:
		"gold":
			return Vector2(
				size.x * GOLD_GROUND_WIDTH_FACTOR,
				size.y * GOLD_GROUND_HEIGHT_FACTOR
			)
		"gold_mountain":
			return Vector2(
				size.x * MOUNTAIN_GROUND_WIDTH_FACTOR,
				size.y * MOUNTAIN_GROUND_HEIGHT_FACTOR
			)
		_:
			return Vector2(
				size.x * MOUNTAIN_GROUND_WIDTH_FACTOR,
				size.y * MOUNTAIN_GROUND_HEIGHT_FACTOR
			)


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
		var obstacle := TerrainObstacle.new()
		obstacle.setup(
			texture,
			world_pos,
			offset,
			placement.get("blocks", true),
			1.0,
			0.0,
			_ground_block_half_for_kind("gold_mountain", texture, MOUNTAIN_VISUAL_SCALE),
			true,
			MOUNTAIN_VISUAL_SCALE
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
