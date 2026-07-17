extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var day_night: DayNightManager = main.get_tree().get_first_node_in_group("day_night_manager")
	assert(day_night != null)
	day_night.automatic_cycle = false

	# Blitz: day 55 + dusk 12 = 67s to reach night.
	day_night.advance_time(70.0)
	await process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.NIGHT)
	assert(main.get_tree().get_nodes_in_group("enemies").size() >= 4)

	day_night.advance_time(BalanceConfig.PHASE_DURATIONS.night + 1.0)
	await process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.DAWN)
	assert(main.get_tree().get_nodes_in_group("enemies").is_empty())
	assert(day_night.nights_survived == 1)

	main.free()
	await process_frame
	print("NIGHT_WAVE_INTEGRATION_OK")
	quit(0)
