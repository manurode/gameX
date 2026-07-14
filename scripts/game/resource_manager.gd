class_name ResourceManager
extends Node

signal resources_changed(wood: int, gold: int, food: int)

var wood: int = BalanceConfig.INITIAL_WOOD
var gold: int = BalanceConfig.INITIAL_GOLD
var food: int = BalanceConfig.INITIAL_FOOD


func _ready() -> void:
	_emit_changed()


func can_afford(cost: Dictionary) -> bool:
	return (
		wood >= cost.get("wood", 0)
		and gold >= cost.get("gold", 0)
		and food >= cost.get("food", 0)
	)


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
