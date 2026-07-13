class_name ResourceManager
extends Node

signal resources_changed(wood: int, stone: int, food: int)

var wood: int = 10000
var stone: int = 10000
var food: int = 10000


func _ready() -> void:
	_emit_changed()


func can_afford(cost: Dictionary) -> bool:
	return (
		wood >= cost.get("wood", 0)
		and stone >= cost.get("stone", 0)
		and food >= cost.get("food", 0)
	)


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	wood -= cost.get("wood", 0)
	stone -= cost.get("stone", 0)
	food -= cost.get("food", 0)
	_emit_changed()
	return true


func add_resources(amounts: Dictionary) -> void:
	wood += amounts.get("wood", 0)
	stone += amounts.get("stone", 0)
	food += amounts.get("food", 0)
	_emit_changed()


func try_spend_food(amount: int) -> bool:
	if food < amount:
		return false
	food -= amount
	_emit_changed()
	return true


func _emit_changed() -> void:
	resources_changed.emit(wood, stone, food)
