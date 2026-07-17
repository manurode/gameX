class_name UnitSpatialIndex
extends RefCounted

## Rebuilds once per physics frame from the "units" group for O(neighbors) queries.

const CELL_SIZE := 64.0

static var _physics_frame := -1
static var _hash := SpatialHash2D.new()
static var _query_scratch: Array = []


static func _ensure_built(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _physics_frame:
		return
	_physics_frame = frame
	_hash.cell_size = CELL_SIZE
	_hash.clear()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if unit._is_dying or unit.hp <= 0 or unit.garrisoned_building != null:
			continue
		_hash.insert(unit, unit.global_position)


static func query_nearby(tree: SceneTree, world_position: Vector2, radius: float) -> Array:
	_ensure_built(tree)
	_hash.query_radius_into(world_position, radius, _query_scratch)
	# Return a copy so nested queries (e.g. ally alerts) cannot invalidate iteration.
	return _query_scratch.duplicate()
