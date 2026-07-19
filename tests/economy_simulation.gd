extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cycle()
	_test_victory()
	_test_balance_data()
	_simulate_ten_cycles()
	print("BALANCE_TESTS_OK")
	quit(0)


func _cycle_length() -> float:
	return (
		BalanceConfig.PHASE_DURATIONS.day
		+ BalanceConfig.PHASE_DURATIONS.dusk
		+ BalanceConfig.PHASE_DURATIONS.night
		+ BalanceConfig.PHASE_DURATIONS.dawn
	)


func _test_cycle() -> void:
	var manager := DayNightManager.new()
	root.add_child(manager)
	manager.automatic_cycle = false
	manager.setup(null)
	assert(manager.current_phase == DayNightManager.CyclePhase.DAY)
	manager.advance_time(BalanceConfig.PHASE_DURATIONS.day)
	assert(manager.current_phase == DayNightManager.CyclePhase.DUSK)
	manager.advance_time(BalanceConfig.PHASE_DURATIONS.dusk)
	assert(manager.current_phase == DayNightManager.CyclePhase.NIGHT)
	assert(not manager.is_construction_allowed())
	manager.advance_time(BalanceConfig.PHASE_DURATIONS.night)
	assert(manager.current_phase == DayNightManager.CyclePhase.DAWN)
	assert(manager.nights_survived == 1)
	manager.advance_time(BalanceConfig.PHASE_DURATIONS.dawn)
	assert(manager.current_phase == DayNightManager.CyclePhase.DAY)
	assert(manager.cycle_number == 2)
	manager.free()


func _test_victory() -> void:
	var manager := DayNightManager.new()
	root.add_child(manager)
	manager.automatic_cycle = false
	manager.setup(null)
	var won := false
	manager.victory_reached.connect(func() -> void: won = true)
	# Survive 5 nights, then complete the final dawn.
	for _i in BalanceConfig.WIN_NIGHTS:
		manager.advance_time(
			BalanceConfig.PHASE_DURATIONS.day
			+ BalanceConfig.PHASE_DURATIONS.dusk
			+ BalanceConfig.PHASE_DURATIONS.night
			+ BalanceConfig.PHASE_DURATIONS.dawn
		)
	assert(manager.nights_survived == BalanceConfig.WIN_NIGHTS)
	assert(won)
	assert(manager.is_run_finished())
	manager.free()


func _test_balance_data() -> void:
	assert(is_equal_approx(_cycle_length(), 122.0))
	assert(BalanceConfig.WIN_NIGHTS == 5)
	assert(BalanceConfig.TREE_CAPACITY == 2400)
	assert(BalanceConfig.GOLD_VEIN_CAPACITY / BalanceConfig.SQUAD_GOLD_COST == 22)
	assert(BalanceConfig.GOLD_MOUNTAIN_CAPACITY == BalanceConfig.GOLD_VEIN_CAPACITY * 5)
	assert(BuildingDatabase.get_definition("house_small").housing == 5)
	assert(BuildingDatabase.get_definition("wall").build_time == 3.0)
	assert(BuildingDatabase.get_definition("tower").automatic_defense)
	assert(EquipmentDatabase.get_definition("knight_squad").squad_size == 1)
	assert(EquipmentDatabase.get_definition("archer_squad").squad_size == 1)
	# Opening must afford both gather buildings + a house without waiting on income.
	var open_wood := (
		int(BuildingDatabase.get_definition("lumber_camp").wood)
		+ int(BuildingDatabase.get_definition("mill").wood)
		+ int(BuildingDatabase.get_definition("house_small").wood)
	)
	assert(open_wood <= BalanceConfig.INITIAL_WOOD)
	assert(BalanceConfig.INITIAL_WOOD - open_wood >= 15)
	var population_manager := PopulationManager.new()
	population_manager.population = 5
	population_manager.population_cap = 10
	assert(population_manager.reserve_population(4))
	assert(not population_manager.reserve_population(2))
	population_manager.release_reserved_population(4)
	population_manager.free()


func _simulate_ten_cycles() -> void:
	var food := float(BalanceConfig.INITIAL_FOOD)
	var wood := float(BalanceConfig.INITIAL_WOOD)
	var gold := float(BalanceConfig.INITIAL_GOLD)
	var villagers := 5
	var squads := 0
	var cycle_len := _cycle_length()
	var night_len: float = BalanceConfig.PHASE_DURATIONS.night
	for cycle in range(1, 11):
		var farmers := mini(3, villagers)
		var miners := 1 if villagers > farmers else 0
		var lumberjacks := maxi(0, villagers - farmers - miners)
		food += float(farmers) * BalanceConfig.FOOD_PER_SECOND * cycle_len
		wood += float(lumberjacks) * BalanceConfig.WOOD_PER_SECOND * cycle_len
		gold += float(miners) * BalanceConfig.GOLD_PER_SECOND * cycle_len
		food -= float(villagers) * BalanceConfig.VILLAGER_FOOD_PER_SECOND * cycle_len
		food -= float(squads) * BalanceConfig.SQUAD_FOOD_PER_SECOND_AT_NIGHT * night_len
		if cycle >= 3 and food >= BalanceConfig.SQUAD_FOOD_COST and gold >= BalanceConfig.SQUAD_GOLD_COST:
			food -= BalanceConfig.SQUAD_FOOD_COST
			gold -= BalanceConfig.SQUAD_GOLD_COST
			squads += 1
		print("Ciclo %d: madera=%d oro=%d comida=%d aldeanos=%d escuadras=%d" % [
			cycle, floori(wood), floori(gold), floori(food), villagers, squads
		])
	assert(food > 0.0)
