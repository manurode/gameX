extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var day_night: DayNightManager = main.get_node("GameWorld/DayNightManager")
	day_night.automatic_cycle = false
	day_night.advance_time(150.0)
	await process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.NIGHT)
	assert(main.get_tree().get_nodes_in_group("enemies").size() >= 6)
	day_night.advance_time(60.0)
	await process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.DAWN)
	assert(main.get_tree().get_nodes_in_group("enemies").is_empty())
	main.free()
	await process_frame
	print("NIGHT_WAVE_INTEGRATION_OK")
	quit(0)
