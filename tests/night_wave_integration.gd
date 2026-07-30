extends Node

## Run as a scene so autoloads (GameSettings / MetaProgression) are live:
##   godot --headless --path . tests/night_wave_integration.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Beginner halves wave size down to the floor of 2; use the baseline difficulty
	# so the batched spawn is exercised with a real wave.
	GameSettings.difficulty = GameSettingsData.Difficulty.ADVANCED

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	get_tree().root.add_child(main)

	var day_night: DayNightManager = null
	for _i in 600:
		await get_tree().process_frame
		day_night = get_tree().get_first_node_in_group("day_night_manager")
		if day_night != null:
			break
	assert(day_night != null)
	day_night.automatic_cycle = false

	# Blitz: day 55 + dusk 12 = 67s to reach night.
	day_night.advance_time(70.0)
	await get_tree().process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.NIGHT)

	var waves: NightWaveManager = get_tree().get_first_node_in_group("night_wave_manager")
	assert(waves != null)

	# The wave instantiates over several frames; every planned enemy must arrive.
	var planned: int = waves._spawned.size() + waves._pending_spawn_count()
	assert(planned >= 4, "Expected a real wave, planned=%d" % planned)
	for _i in 120:
		await get_tree().process_frame
		if waves._pending_spawn_count() <= 0:
			break
	assert(
		waves._pending_spawn_count() == 0,
		"Wave spawn queue never drained (%d left)." % waves._pending_spawn_count()
	)
	var live := get_tree().get_nodes_in_group("enemies").size()
	assert(
		live == planned,
		"Batched spawn lost enemies: planned %d, live %d." % [planned, live]
	)

	day_night.advance_time(BalanceConfig.PHASE_DURATIONS.night + 1.0)
	await get_tree().process_frame
	assert(day_night.current_phase == DayNightManager.CyclePhase.DAWN)
	assert(get_tree().get_nodes_in_group("enemies").is_empty())
	assert(waves._pending_spawn_count() == 0, "Dawn must drop queued spawns.")
	assert(day_night.nights_survived == 1)

	print("NIGHT_WAVE_SPAWN_OK planned=%d" % planned)
	print("NIGHT_WAVE_INTEGRATION_OK")
	get_tree().quit(0)
