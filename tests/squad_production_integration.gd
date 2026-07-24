extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var world := main.get_node("GameWorld")
	var population: PopulationManager = world.get_node("PopulationManager")
	var resources: ResourceManager = world.get_node("ResourceManager")
	var production: ProductionManager = world.get_node("ProductionManager")
	var job_manager: JobManager = world.get_node("JobManager")
	population.population_cap = 10
	resources.add_resources({"food": 120, "gold": 80})

	var building_scene: PackedScene = load("res://scenes/buildings/building.tscn")
	var stable: Building = building_scene.instantiate()
	stable.configure("stable", Building.BuildingState.ACTIVE, 1.0)
	world.get_node("Buildings").add_child(stable)
	var units_root: Node2D = world.get_node("Units")
	stable.global_position = units_root.get_child(0).global_position
	production.register_producer(stable)

	assert(production.enqueue(stable, "knight_squad"))
	assert(population.reserved_population == 0)
	production._advance_queue(stable, BalanceConfig.SQUAD_TRAIN_TIME + 0.1)
	production._process_pending_recruitment()

	var recruit: Unit = null
	for node in units_root.get_children():
		if node is Unit and (node as Unit).recruitment_building == stable:
			recruit = node
			break
	assert(recruit != null)

	# Interrupting recruitment must requeue the pending conversion job.
	recruit.move_to(recruit.global_position + Vector2(80, 0))
	assert(recruit.recruitment_building == null)
	assert(recruit._unit_state == Unit.UnitState.MOVING)
	var pending := production.get_pending_recruitment(stable)
	assert(not pending.is_empty())
	assert(int(pending.get("count", 0)) == 1)

	# Another (preferably idle/near) villager should take the job.
	production._process_pending_recruitment()
	var replacement: Unit = null
	for node in units_root.get_children():
		if node is Unit and (node as Unit).recruitment_building == stable:
			replacement = node
			break
	assert(replacement != null)
	assert(replacement != recruit)

	replacement.global_position = stable.get_approach_point(replacement.global_position)
	replacement._process_recruitment(0.0)
	await process_frame

	var military_count := 0
	for node in units_root.get_children():
		if node is Unit and not (node as Unit).is_civilian:
			military_count += 1
	assert(military_count == 1)
	assert(population.population == 5)
	assert(population.reserved_population == 0)
	assert(production.get_pending_recruitment(stable).is_empty())

	# Selection preference: idle over busy, then nearest to building.
	var civilians: Array[Unit] = []
	for node in units_root.get_children():
		if node is Unit and (node as Unit).is_civilian and not (node as Unit)._is_dying:
			civilians.append(node)
	assert(civilians.size() >= 2)
	var near_idle: Unit = civilians[0]
	var far_idle: Unit = civilians[1]
	near_idle.global_position = stable.global_position + Vector2(20, 0)
	far_idle.global_position = stable.global_position + Vector2(400, 0)
	near_idle._unit_state = Unit.UnitState.IDLE
	far_idle._unit_state = Unit.UnitState.IDLE
	for other in civilians:
		if other == near_idle or other == far_idle:
			continue
		other._unit_state = Unit.UnitState.GATHERING

	var picked := job_manager.collect_civilian_villagers(1, stable)
	assert(picked.size() == 1)
	assert(picked[0] == near_idle)

	# With no idle villagers, pick the closest busy one.
	near_idle._unit_state = Unit.UnitState.GATHERING
	far_idle._unit_state = Unit.UnitState.GATHERING
	picked = job_manager.collect_civilian_villagers(1, stable)
	assert(picked.size() == 1)
	assert(picked[0] == near_idle)

	main.free()
	await process_frame
	print("SQUAD_PRODUCTION_INTEGRATION_OK")
	quit(0)
