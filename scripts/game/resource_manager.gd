class_name ResourceManager
extends Node

signal resources_changed(wood: int, gold: int, food: int)

var wood: int = BalanceConfig.INITIAL_WOOD
var gold: int = BalanceConfig.INITIAL_GOLD
var food: int = BalanceConfig.INITIAL_FOOD


func _ready() -> void:
	_emit_changed()


const RESOURCE_KEYS: Array[String] = ["wood", "gold", "food"]


func can_afford(cost: Dictionary) -> bool:
	return get_affordable_fraction(cost) >= 1.0


func get_affordable_fraction(cost: Dictionary) -> float:
	var fraction := 1.0
	var has_cost := false
	for key in RESOURCE_KEYS:
		var needed: int = cost.get(key, 0)
		if needed <= 0:
			continue
		has_cost = true
		var available := _get_resource(key)
		fraction = minf(fraction, float(available) / float(needed))
	if not has_cost:
		return 1.0
	return clampf(fraction, 0.0, 1.0)


func get_partial_cost(cost: Dictionary) -> Dictionary:
	var fraction := get_affordable_fraction(cost)
	if fraction <= 0.0:
		return {"wood": 0, "gold": 0, "food": 0}
	if fraction >= 1.0:
		return cost.duplicate()
	var partial := {}
	for key in RESOURCE_KEYS:
		partial[key] = int(floor(float(cost.get(key, 0)) * fraction))
	return partial


func has_any_cost(cost: Dictionary) -> bool:
	for key in RESOURCE_KEYS:
		if cost.get(key, 0) > 0:
			return true
	return false


func _get_resource(key: String) -> int:
	match key:
		"wood":
			return wood
		"gold":
			return gold
		"food":
			return food
		_:
			return 0


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	wood -= cost.get("wood", 0)
	gold -= cost.get("gold", 0)
	food -= cost.get("food", 0)
	_emit_changed()
	return true


func add_resources(amounts: Dictionary) -> void:
	wood += amounts.get("wood", 0)
	gold += amounts.get("gold", 0)
	food += amounts.get("food", 0)
	_emit_changed()


func try_spend_food(amount: int) -> bool:
	if food < amount:
		return false
	food -= amount
	_emit_changed()
	return true


func consume_food_up_to(amount: int) -> int:
	var consumed := mini(maxi(amount, 0), food)
	if consumed <= 0:
		return 0
	food -= consumed
	_emit_changed()
	return consumed


func _emit_changed() -> void:
	resources_changed.emit(wood, gold, food)


func refresh() -> void:
	_emit_changed()
