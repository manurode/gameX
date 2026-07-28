class_name OcclusionPropIndex
extends RefCounted

## Spatial hash of "occlusion_props" for unit silhouettes.
## Props rarely move — rebuild every few frames, not per unit.

const CELL_SIZE := 160.0
const REBUILD_INTERVAL_FRAMES := 10
## Covers Ciudadela / large forests; per-prop cull still filters after.
const DEFAULT_QUERY_RADIUS := 420.0

static var _checked_frame := -1
static var _rebuild_frame := -1
static var _hash := SpatialHash2D.new()
static var _query_scratch: Array = []
static var _prop_count := -1


static func _ensure_built(tree: SceneTree) -> void:
	var frame := Engine.get_process_frames()
	# At most one group scan + optional rebuild per rendered frame.
	if frame == _checked_frame:
		return
	_checked_frame = frame

	var props: Array = tree.get_nodes_in_group("occlusion_props") if tree != null else []
	var count := props.size()
	var due := (_rebuild_frame < 0) or ((frame - _rebuild_frame) >= REBUILD_INTERVAL_FRAMES)
	var count_changed := _prop_count >= 0 and absi(count - _prop_count) >= 3
	if not due and not count_changed:
		return

	_rebuild_frame = frame
	_prop_count = count
	_hash.cell_size = CELL_SIZE
	_hash.clear()
	for node in props:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var occluder := node as Node2D
		if not occluder.has_method("get_occlusion_sprites"):
			continue
		_hash.insert(occluder, occluder.global_position)


static func query_nearby(
	tree: SceneTree,
	world_position: Vector2,
	radius: float = DEFAULT_QUERY_RADIUS
) -> Array:
	_ensure_built(tree)
	_hash.query_radius_into(world_position, radius, _query_scratch)
	if _query_scratch.is_empty():
		return []
	return _query_scratch.duplicate()


## Force rebuild on next query (after placing/destroying a building).
static func invalidate() -> void:
	_checked_frame = -1
	_rebuild_frame = -1
	_prop_count = -1
