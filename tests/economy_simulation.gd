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
	# Survive WIN_NIGHTS, then complete the final dawn.
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
	assert(BalanceConfig.WIN_NIGHTS == 20)
	assert(BalanceConfig.META_FRAGMENT_TARGET_VICTORY == 50)
	assert(BalanceConfig.meta_fragments_for_nights(2) == 0)
	assert(BalanceConfig.meta_fragments_for_nights(20) == 50)
	assert(BalanceConfig.TREE_CAPACITY == 2400)
	assert(BalanceConfig.GOLD_VEIN_CAPACITY / BalanceConfig.SQUAD_GOLD_COST == 22)
	assert(BalanceConfig.GOLD_MOUNTAIN_CAPACITY == BalanceConfig.GOLD_VEIN_CAPACITY * 5)
	assert(BuildingDatabase.get_definition("house_small").housing == 5)
	assert(BuildingDatabase.get_definition("wall").build_time == 3.0)
	assert(BuildingDatabase.get_definition("tower").automatic_defense)
	assert(EquipmentDatabase.get_definition("knight_squad").squad_size == 1)
	assert(EquipmentDatabase.get_definition("archer_squad").squad_size == 1)
	assert(int(EquipmentDatabase.get_definition("knight_squad").cost.get("food", 0)) == 0)
	assert(int(EquipmentDatabase.get_definition("archer_squad").cost.get("food", 0)) == 0)
	assert(int(EquipmentDatabase.get_definition("mage_squad").cost.get("food", 0)) == 0)
	assert(not str(EquipmentDatabase.get_definition("knight_squad").get("transforms_to", "")).is_empty())
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
	_test_market_economy()


func _test_market_economy() -> void:
	# Fee must bite hard enough that round-trips never profit.
	assert(BalanceConfig.MARKET_FEE >= 0.35)
	assert(BalanceConfig.MARKET_TRADES_PER_CYCLE <= 3)
	# Gold stays the most valuable resource so wood-only play cannot fund armies cheaply.
	assert(BalanceConfig.MARKET_RESOURCE_VALUE.gold > BalanceConfig.MARKET_RESOURCE_VALUE.food)
	assert(BalanceConfig.MARKET_RESOURCE_VALUE.food > BalanceConfig.MARKET_RESOURCE_VALUE.wood)

	var resources := ResourceManager.new()
	root.add_child(resources)
	resources.wood = 500
	resources.gold = 200
	resources.food = 200
	var market := MarketManager.new()
	root.add_child(market)
	market.setup(resources, null)

	var offers := market.get_offers()
	assert(offers.size() == 6)

	# Round-trip wood → food → wood loses most of the stock.
	var wood_to_food := market.get_offer("wood", "food")
	var food_to_wood := market.get_offer("food", "wood")
	assert(int(wood_to_food.receive) < int(wood_to_food.pay))
	var recovered_wood := int(
		floor(
			float(wood_to_food.receive)
			* float(food_to_wood.receive)
			/ float(food_to_wood.pay)
		)
	)
	assert(recovered_wood < int(wood_to_food.pay) / 2)

	# Daily cap: only N successful trades, then blocked until next cycle.
	assert(market.try_exchange("wood", "food"))
	assert(market.try_exchange("wood", "gold"))
	assert(market.try_exchange("food", "wood"))
	assert(market.get_trades_remaining() == 0)
	assert(not market.try_exchange("gold", "food"))
	assert(not market.get_exchange_block_reason("gold", "food").is_empty())

	# Converting wood into a full squad gold cost needs more than one day's trades.
	var wood_to_gold := market.get_offer("wood", "gold")
	var gold_per_trade: int = int(wood_to_gold.receive)
	var trades_for_squad := int(ceili(float(BalanceConfig.SQUAD_GOLD_COST) / float(gold_per_trade)))
	assert(trades_for_squad > BalanceConfig.MARKET_TRADES_PER_CYCLE)

	market.free()
	resources.free()


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
		# Military eats outside night (day + dusk + dawn).
		food -= float(squads) * BalanceConfig.SQUAD_FOOD_PER_SECOND_BY_DAY * (cycle_len - night_len)
		if cycle >= 3 and villagers > 1 and gold >= BalanceConfig.SQUAD_GOLD_COST:
			gold -= BalanceConfig.SQUAD_GOLD_COST
			villagers -= 1
			squads += 1
		print("Ciclo %d: madera=%d oro=%d comida=%d aldeanos=%d escuadras=%d" % [
			cycle, floori(wood), floori(gold), floori(food), villagers, squads
		])
	assert(food > 0.0)
