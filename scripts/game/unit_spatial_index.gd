class_name UnitSpatialIndex
extends RefCounted

## Rebuilds once per physics frame from the "units" group for O(neighbors) queries.

const CELL_SIZE := 64.0

static var _physics_frame := -1
static var _hash := SpatialHash2D.new()
static var _query_scratch: Array = []
static var _foreach_pool: Array = []
static var _foreach_depth := 0


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
		# Freed refs must be checked before `is` (Godot errors otherwise).
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var unit := node as Unit
		if unit._is_dying or unit.hp <= 0 or unit.garrisoned_building != null:
			continue
		_hash.insert(unit, unit.global_position)


static func query_nearby(tree: SceneTree, world_position: Vector2, radius: float) -> Array:
	_ensure_built(tree)
	_hash.query_radius_into(world_position, radius, _query_scratch)
	_compact_valid_units(_query_scratch)
	# Copy so nested queries (e.g. damage -> ally alert) cannot invalidate iteration.
	if _query_scratch.is_empty():
		return []
	return _query_scratch.duplicate()


## Zero-copy neighbor walk. Nested calls are safe via a depth-pooled scratch buffer.
static func for_each_nearby(
	tree: SceneTree,
	world_position: Vector2,
	radius: float,
	callback: Callable
) -> void:
	_ensure_built(tree)
	if radius <= 0.0:
		return
	if _foreach_depth >= _foreach_pool.size():
		_foreach_pool.append([])
	var scratch: Array = _foreach_pool[_foreach_depth]
	_foreach_depth += 1
	_hash.query_radius_into(world_position, radius, scratch)
	_compact_valid_units(scratch)
	for item in scratch:
		callback.call(item)
	_foreach_depth -= 1


static func _compact_valid_units(items: Array) -> void:
	var write := 0
	for item in items:
		if is_instance_valid(item) and item is Unit:
			items[write] = item
			write += 1
	items.resize(write)
