extends Node

const MAX_PHYSICS_FRAMES := 720
const DESTINATION_TOLERANCE := 32.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_scene: PackedScene = load("res://scenes/world/game_world.tscn")
	var world := world_scene.instantiate()
	add_child(world)

	for _frame in 12:
		await get_tree().physics_frame

	# Units and buildings share the y-sorted world layer.
	var world_layer: Node2D = world.get_node("YSortWorld")
	assert(world_layer.get_child_count() > 0)

	var building: Building = null
	for child in world_layer.get_children():
		if child is Building:
			building = child as Building
			break
	var navigation_manager := get_tree().get_first_node_in_group("navigation_manager")
	assert(building != null)
	assert(navigation_manager != null)

	# A knight, not a starting villager: the job manager keeps reassigning
	# villagers to gather, which would cancel the move order under test.
	var unit: Unit = UnitDatabase.get_scene("knight").instantiate()
	world_layer.add_child(unit)
	UnitDatabase.apply_definition_to_unit(unit, "knight")
	unit.set_ground_layer(world.get("ground_layer"))

	# A rebuild that actually changes walkability must publish a new version, so
	# every unit drops its cached route. Placing a fresh building does that.
	var initial_version: int = navigation_manager.get_navigation_version()
	var rebuild_started := Time.get_ticks_msec()
	var blocker: Building = load("res://scenes/buildings/building.tscn").instantiate()
	blocker.configure("house_small", Building.BuildingState.ACTIVE, 1.0)
	world_layer.add_child(blocker)
	blocker.place_at(building.global_position + Vector2(0.0, 260.0))
	world.rebuild_navigation(blocker)
	for _frame in 120:
		await get_tree().process_frame
		if navigation_manager.get_navigation_version() > initial_version:
			break
	var rebuild_elapsed := Time.get_ticks_msec() - rebuild_started
	assert(
		navigation_manager.get_navigation_version() > initial_version,
		"The dynamic navigation update did not finish."
	)
	assert(
		rebuild_elapsed < 1000,
		"Dynamic navigation update took %d ms." % rebuild_elapsed
	)

	_assert_agent_clearance(navigation_manager, blocker)

	# Aim through the blocked ground footprint, not the sprite anchor: building art
	# is anchored well above its base, so a line through the anchor is clear.
	var obstacle_center := _outline_center(building.get_nav_block_outline())
	assert(
		not navigation_manager._is_world_point_walkable(obstacle_center),
		"The building footprint is not blocking the path grid."
	)

	# Snap to real ground so the unit can actually stand on the goal.
	var start: Vector2 = navigation_manager.get_closest_walkable_point(
		obstacle_center + Vector2(-240.0, 0.0)
	)
	var destination: Vector2 = navigation_manager.get_closest_walkable_point(
		obstacle_center + Vector2(240.0, 0.0)
	)
	navigation_manager.queue_navigation_path(start, destination)
	var path := PackedVector2Array()
	for _frame in 120:
		await get_tree().process_frame
		path = navigation_manager.get_navigation_path(start, destination)
		if not path.is_empty():
			break
	assert(path.size() >= 3, "The route must bend around the building. Got %s" % path)

	# Smoothing must never cut a corner through a blocked cell.
	for i in range(1, path.size()):
		assert(
			navigation_manager._has_clear_segment(path[i - 1], path[i]),
			"Smoothed leg %d crosses blocked ground: %s -> %s" % [i, path[i - 1], path[i]]
		)

	unit.global_position = start
	unit.reset_navigation()
	unit.move_to(destination)

	var reached := false
	for _frame in MAX_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if unit.global_position.distance_to(destination) <= DESTINATION_TOLERANCE:
			reached = true
			break

	assert(reached, "The unit did not navigate around the building.")

	# A rebuild that changes nothing must NOT invalidate cached paths, otherwise
	# every building placement makes the whole army repath at once.
	var settled_version: int = navigation_manager.get_navigation_version()
	world.rebuild_navigation(blocker)
	for _frame in 30:
		await get_tree().process_frame
	assert(
		navigation_manager.get_navigation_version() == settled_version,
		"A no-op navigation rebuild invalidated the path cache."
	)

	await _assert_region_labels_agree_with_astar(world, navigation_manager)

	print("DYNAMIC_NAV_REBUILD_OK %dms" % rebuild_elapsed)
	print("NAVIGATION_INTEGRATION_OK")
	get_tree().quit(0)


## Region labels let the pathfinder answer "unreachable" without running A*, which
## is only sound in one direction: it may never call a route impossible when A*
## would find one. Seal the town so separate regions actually exist, then
## cross-check both answers over the whole grid.
func _assert_region_labels_agree_with_astar(world: Node, navigation_manager: Node) -> void:
	var ground: TinyTilesMap = world.get("ground_layer")
	var inside: Vector2 = navigation_manager.get_closest_walkable_point(
		ground.map_to_local(ground.get_town_center_cell())
	)
	world.spawn_starter_walls(40)
	await _await_region_labels(navigation_manager)

	# The ring must genuinely cut the interior off, or the check below proves nothing.
	var inside_id: Vector2i = navigation_manager._world_to_grid(inside)
	var inside_label: int = navigation_manager._component_at(inside_id)
	assert(inside_label >= 0, "Town centre cell left unlabelled.")

	var grid_size: Vector2i = navigation_manager._path_grid_size
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	var checked := 0
	var separated := 0
	while checked < 400:
		var from_id := Vector2i(
			rng.randi_range(0, grid_size.x - 1), rng.randi_range(0, grid_size.y - 1)
		)
		var to_id := Vector2i(
			rng.randi_range(0, grid_size.x - 1), rng.randi_range(0, grid_size.y - 1)
		)
		if navigation_manager._path_grid.is_point_solid(from_id):
			continue
		if navigation_manager._path_grid.is_point_solid(to_id):
			continue
		checked += 1

		var from_label: int = navigation_manager._component_at(from_id)
		var to_label: int = navigation_manager._component_at(to_id)
		assert(from_label >= 0 and to_label >= 0, "Open cell left unlabelled.")
		if from_label == to_label:
			continue

		separated += 1
		assert(
			navigation_manager._path_grid.get_id_path(from_id, to_id, false).is_empty(),
			"Labels called %s -> %s unreachable but A* found a route." % [from_id, to_id]
		)

	assert(
		separated > 0,
		"No pair landed in different regions, so the unreachable shortcut is untested."
	)
	print("NAV_REGION_LABELS_OK %d pairs, %d cross-region" % [checked, separated])


func _await_region_labels(navigation_manager: Node) -> void:
	for _frame in 900:
		if navigation_manager._components_ready and not navigation_manager._component_build_active:
			return
		await get_tree().process_frame
	assert(false, "Region labelling never finished.")


## Blocker outlines are pre-grown by AGENT_CLEARANCE instead of running a
## per-edge distance test on every query. Pin that the reach is unchanged: the
## footprint blocks, so does a point just outside it, and open ground does not.
func _assert_agent_clearance(navigation_manager: Node, blocker: Building) -> void:
	var outline := blocker.get_nav_block_outline()
	var center := _outline_center(outline)
	assert(
		not navigation_manager._is_world_point_walkable(center),
		"Building footprint stopped blocking the path grid."
	)

	var clearance: float = navigation_manager.AGENT_CLEARANCE
	# Walk outward along +X from the footprint edge on the centre line.
	var edge_x := center.x
	while not navigation_manager._is_world_point_walkable(Vector2(edge_x, center.y)):
		edge_x += 2.0
		assert(edge_x < center.x + 2000.0, "Never left the blocker going +X.")
	# The first free point must already be past the raw outline by the clearance.
	var distance_to_outline := _distance_to_outline(Vector2(edge_x, center.y), outline)
	assert(
		distance_to_outline >= clearance - 3.0,
		"Agent clearance shrank: first free point is %.1fpx from the outline (want >= %.1f)."
		% [distance_to_outline, clearance]
	)
	assert(
		distance_to_outline <= clearance + 8.0,
		"Agent clearance grew: first free point is %.1fpx from the outline (want ~%.1f)."
		% [distance_to_outline, clearance]
	)


func _distance_to_outline(point: Vector2, outline: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, outline):
		return 0.0
	var best := INF
	for i in outline.size():
		var closest := Geometry2D.get_closest_point_to_segment(
			point, outline[i], outline[(i + 1) % outline.size()]
		)
		best = minf(best, point.distance_to(closest))
	return best


func _outline_center(outline: PackedVector2Array) -> Vector2:
	assert(outline.size() >= 3, "Building has no navigation footprint.")
	var total := Vector2.ZERO
	for point in outline:
		total += point
	return total / float(outline.size())
