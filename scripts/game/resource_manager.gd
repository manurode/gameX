class_name ResourceManager
extends Node

signal resources_changed(wood: int, stone: int, wheat: int)

var wood: int = 500
var stone: int = 350
var wheat: int = 150


func _ready() -> void:
	_emit_changed()


func can_afford(cost: Dictionary) -> bool:
	return (
		wood >= cost.get("wood", 0)
		and stone >= cost.get("stone", 0)
		and wheat >= cost.get("wheat", 0)
	)


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	wood -= cost.get("wood", 0)
	stone -= cost.get("stone", 0)
	wheat -= cost.get("wheat", 0)
	_emit_changed()
	return true


func add_resources(amounts: Dictionary) -> void:
	wood += amounts.get("wood", 0)
	stone += amounts.get("stone", 0)
	wheat += amounts.get("wheat", 0)
	_emit_changed()


func _emit_changed() -> void:
	resources_changed.emit(wood, stone, wheat)
