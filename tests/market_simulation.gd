extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(BalanceConfig.MARKET_FEE >= 0.35)
	assert(BalanceConfig.MARKET_TRADES_PER_CYCLE <= 3)
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

	assert(market.get_offers().size() == 6)

	var wood_to_food := market.get_offer("wood", "food")
	var food_to_wood := market.get_offer("food", "wood")
	assert(int(wood_to_food.pay) == 50)
	assert(int(wood_to_food.receive) == 12)
	assert(int(food_to_wood.pay) == 30)
	assert(int(food_to_wood.receive) == 45)

	var wood_to_gold := market.get_offer("wood", "gold")
	assert(int(wood_to_gold.receive) == 8)
	assert(int(market.get_offer("food", "gold").receive) == 12)
	assert(int(market.get_offer("gold", "wood").receive) == 52)
	assert(int(market.get_offer("gold", "food").receive) == 21)

	# Round-trip recovers less than half.
	var recovered := int(floor(float(wood_to_food.receive) * float(food_to_wood.receive) / float(food_to_wood.pay)))
	assert(recovered < int(wood_to_food.pay) / 2)

	assert(market.try_exchange("wood", "food"))
	assert(resources.wood == 450)
	assert(resources.food == 212)
	assert(market.try_exchange("wood", "gold"))
	assert(market.try_exchange("food", "wood"))
	assert(market.get_trades_remaining() == 0)
	assert(not market.try_exchange("gold", "food"))

	var trades_for_squad := int(ceili(float(BalanceConfig.SQUAD_GOLD_COST) / float(wood_to_gold.receive)))
	assert(trades_for_squad > BalanceConfig.MARKET_TRADES_PER_CYCLE)

	print("MARKET_TESTS_OK")
	print("Rates: 50w→%df, 50w→%dg, 30f→%dw, 30f→%dg, 25g→%dw, 25g→%df" % [
		int(wood_to_food.receive),
		int(wood_to_gold.receive),
		int(food_to_wood.receive),
		int(market.get_offer("food", "gold").receive),
		int(market.get_offer("gold", "wood").receive),
		int(market.get_offer("gold", "food").receive),
	])
	quit(0)
