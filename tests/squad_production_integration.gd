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
	population.population_cap = 10
	resources.add_resources({"food": 120, "gold": 40})

	var building_scene: PackedScene = load("res://scenes/buildings/building.tscn")
	var stable: Building = building_scene.instantiate()
	stable.configure("stable", Building.BuildingState.ACTIVE, 1.0)
	world.get_node("Buildings").add_child(stable)
	stable.global_position = world.get_node("Units").get_child(0).global_position
	production.register_producer(stable)

	assert(production.enqueue(stable, "knight_squad"))
	assert(population.reserved_population == 0)
	production._advance_queue(stable, BalanceConfig.SQUAD_TRAIN_TIME + 0.1)
	production._process_pending_recruitment()

	var recruit: Unit = null
	for node in world.get_node("Units").get_children():
		if node is Unit and (node as Unit).recruitment_building == stable:
			recruit = node
			break
	assert(recruit != null)
	recruit.global_position = stable.get_approach_point(recruit.global_position)
	recruit._process_recruitment(0.0)
	await process_frame

	var military_count := 0
	for node in world.get_node("Units").get_children():
		if node is Unit and not (node as Unit).is_civilian:
			military_count += 1
	assert(military_count == 1)
	assert(population.population == 5)
	assert(population.reserved_population == 0)
	main.free()
	await process_frame
	print("SQUAD_PRODUCTION_INTEGRATION_OK")
	quit(0)
