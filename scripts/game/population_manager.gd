class_name PopulationManager
extends Node

signal population_changed(population: int, population_cap: int)
signal food_upkeep_changed(upkeep_per_second: float)
signal food_shortage(active: bool)

const BASE_POPULATION_CAP := 5
const FOOD_UPKEEP_PER_UNIT := 0.5

var population: int = 0
var population_cap: int = BASE_POPULATION_CAP
var food_shortage_active: bool = false

var _resource_manager: ResourceManager
var _upkeep_accumulator: float = 0.0


func setup(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager


func get_food_upkeep_per_second() -> float:
	return FOOD_UPKEEP_PER_UNIT * float(population)


func get_food_upkeep_label() -> String:
	if population <= 0:
		return "Sin consumo"
	return "%.1f comida/s (%d habitantes × %.1f)" % [
		get_food_upkeep_per_second(),
		population,
		FOOD_UPKEEP_PER_UNIT,
	]


func _process(delta: float) -> void:
	if _resource_manager == null or population <= 0:
		return

	_upkeep_accumulator += FOOD_UPKEEP_PER_UNIT * float(population) * delta
	if _upkeep_accumulator < 1.0:
		return

	var food_cost := int(_upkeep_accumulator)
	_upkeep_accumulator -= float(food_cost)
	if _resource_manager.try_spend_food(food_cost):
		if food_shortage_active:
			food_shortage_active = false
			food_shortage.emit(false)
	elif not food_shortage_active:
		food_shortage_active = true
		food_shortage.emit(true)


func register_unit(_unit: Unit) -> void:
	population += 1
	population_changed.emit(population, population_cap)
	food_upkeep_changed.emit(get_food_upkeep_per_second())


func unregister_unit(_unit: Unit) -> void:
	population = maxi(0, population - 1)
	population_changed.emit(population, population_cap)
	food_upkeep_changed.emit(get_food_upkeep_per_second())


func can_add_population() -> bool:
	return population < population_cap


func recalculate_cap_from_buildings() -> void:
	var cap := BASE_POPULATION_CAP
	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if building.team_id != Team.PLAYER:
			continue
		var def := BuildingDatabase.get_definition(building.building_type_id)
		cap += def.get("housing", 0)
	population_cap = cap
	population_changed.emit(population, population_cap)
