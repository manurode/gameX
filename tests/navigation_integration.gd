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

	var buildings: Node2D = world.get_node("Buildings")
	var units: Node2D = world.get_node("Units")
	assert(buildings.get_child_count() > 0)
	assert(units.get_child_count() > 0)

	var building := buildings.get_child(0) as Building
	var unit := units.get_child(0) as Unit
	var navigation_manager := get_tree().get_first_node_in_group("navigation_manager")
	assert(building != null)
	assert(unit != null)
	assert(navigation_manager != null)

	var initial_version: int = navigation_manager.get_navigation_version()
	var rebuild_started := Time.get_ticks_msec()
	world.rebuild_navigation(building)
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

	var start := building.global_position + Vector2(-240.0, 0.0)
	var destination := building.global_position + Vector2(240.0, 0.0)
	navigation_manager.queue_navigation_path(start, destination)
	var path := PackedVector2Array()
	for _frame in 120:
		await get_tree().process_frame
		path = navigation_manager.get_navigation_path(start, destination)
		if not path.is_empty():
			break
	assert(path.size() >= 3, "The route must bend around the building.")

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
	print("DYNAMIC_NAV_REBUILD_OK %dms" % rebuild_elapsed)
	print("NAVIGATION_INTEGRATION_OK")
	get_tree().quit(0)
