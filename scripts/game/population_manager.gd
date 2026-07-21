class_name PopulationManager
extends Node

signal population_changed(population: int, population_cap: int)
signal food_upkeep_changed(upkeep_per_second: float)
signal food_shortage(active: bool)

const BASE_POPULATION_CAP := 5
const UPKEEP_TICK_INTERVAL := 0.25

var population: int = 0
var population_cap: int = BASE_POPULATION_CAP
var reserved_population: int = 0
## Housing granted by run boons (refugees / allied military). Persists for the run.
var boon_population_bonus: int = 0
var food_shortage_active: bool = false

var _resource_manager: ResourceManager
var _upkeep_accumulator: float = 0.0
var _starvation_damage_accumulator: float = 0.0
var _registered_units: Dictionary = {}
var _upkeep_tick_timer := 0.0
var _cached_upkeep := 0.0
var _cached_is_night := false
var _day_night_manager: DayNightManager


func setup(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager


func get_food_upkeep_per_second() -> float:
	return _cached_upkeep


func get_food_upkeep_label() -> String:
	if population <= 0:
		return "Sin consumo"
	var income := 0.0
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		income = (job_manager as JobManager).get_food_income_per_second()
	var net := income - get_food_upkeep_per_second()
	return "%.2f/s · balance %+.2f/s" % [get_food_upkeep_per_second(), net]


func _process(delta: float) -> void:
	if _resource_manager == null or population <= 0:
		return

	_upkeep_tick_timer -= delta
	if _upkeep_tick_timer <= 0.0:
		_upkeep_tick_timer = UPKEEP_TICK_INTERVAL
		_cleanup_invalid_units()
		_recalculate_upkeep()

	_upkeep_accumulator += _cached_upkeep * delta
	if _upkeep_accumulator < 1.0:
		if food_shortage_active:
			_apply_starvation_damage(delta)
		return

	var food_cost := int(_upkeep_accumulator)
	_upkeep_accumulator -= float(food_cost)
	var consumed := _resource_manager.consume_food_up_to(food_cost)
	if consumed >= food_cost:
		if food_shortage_active:
			food_shortage_active = false
			food_shortage.emit(false)
	elif not food_shortage_active:
		food_shortage_active = true
		food_shortage.emit(true)
	if food_shortage_active:
		_apply_starvation_damage(delta)


func register_unit(unit: Unit) -> void:
	_registered_units[unit] = true
	population += 1
	_recalculate_upkeep()
	population_changed.emit(population, population_cap)
	food_upkeep_changed.emit(_cached_upkeep)


func unregister_unit(unit: Unit) -> void:
	_registered_units.erase(unit)
	population = maxi(0, population - 1)
	_recalculate_upkeep()
	population_changed.emit(population, population_cap)
	food_upkeep_changed.emit(_cached_upkeep)


func can_add_population() -> bool:
	return population + reserved_population < population_cap


func can_reserve_population(amount: int) -> bool:
	return population + reserved_population + amount <= population_cap


func reserve_population(amount: int) -> bool:
	if not can_reserve_population(amount):
		return false
	reserved_population += amount
	return true


func release_reserved_population(amount: int) -> void:
	reserved_population = maxi(0, reserved_population - amount)


## Raises the population cap so boon units can always join, even at full housing.
func grant_boon_population(amount: int) -> void:
	if amount <= 0:
		return
	boon_population_bonus += amount
	population_cap += amount
	population_changed.emit(population, population_cap)


func get_civilian_work_multiplier() -> float:
	return BalanceConfig.STARVATION_WORK_MULTIPLIER if food_shortage_active else 1.0


func _get_day_night_manager() -> DayNightManager:
	if _day_night_manager != null and is_instance_valid(_day_night_manager):
		return _day_night_manager
	var manager := get_tree().get_first_node_in_group("day_night_manager")
	if manager is DayNightManager:
		_day_night_manager = manager as DayNightManager
		return _day_night_manager
	return null


func _is_night() -> bool:
	var manager := _get_day_night_manager()
	return manager != null and manager.is_night()


func _get_food_upkeep_multiplier() -> float:
	var manager := _get_day_night_manager()
	if manager != null and manager.is_night() and manager.night_duration_multiplier > 1.0:
		return BalanceConfig.ECLIPSE_FOOD_UPKEEP_MULT
	return 1.0


func _recalculate_upkeep() -> void:
	var civilian_count := 0
	var squad_ids: Dictionary = {}
	var military_without_squad := 0
	var meta_military_count := 0
	for unit in _registered_units.keys():
		if not is_instance_valid(unit) or unit.hp <= 0:
			continue
		if unit.is_civilian:
			civilian_count += 1
		elif unit.get_meta("meta_supplied", false):
			# Meta shop starters only — run boons keep full night upkeep.
			meta_military_count += 1
		else:
			var squad_id: String = unit.get_meta("squad_id", "")
			if squad_id.is_empty():
				military_without_squad += 1
			else:
				squad_ids[squad_id] = true
	var upkeep := float(civilian_count) * BalanceConfig.VILLAGER_FOOD_PER_SECOND
	var is_night := _is_night()
	if is_night:
		var full_rate := BalanceConfig.SQUAD_FOOD_PER_SECOND_AT_NIGHT
		upkeep += float(squad_ids.size() + military_without_squad) * full_rate
		upkeep += (
			float(meta_military_count)
			* full_rate
			* BalanceConfig.META_MILITARY_NIGHT_UPKEEP_MULT
		)
	upkeep *= _get_food_upkeep_multiplier()
	if not is_equal_approx(upkeep, _cached_upkeep) or is_night != _cached_is_night:
		_cached_upkeep = upkeep
		_cached_is_night = is_night
		food_upkeep_changed.emit(_cached_upkeep)


func _apply_starvation_damage(delta: float) -> void:
	_starvation_damage_accumulator += BalanceConfig.STARVATION_DAMAGE_PER_SECOND * delta
	if _starvation_damage_accumulator < 1.0:
		return
	var damage := int(_starvation_damage_accumulator)
	_starvation_damage_accumulator -= float(damage)
	for unit in _registered_units.keys():
		if is_instance_valid(unit) and not unit.is_civilian and unit.hp > 0:
			unit.take_damage(damage)


func _cleanup_invalid_units() -> void:
	var stale: Array = []
	for unit in _registered_units.keys():
		if not is_instance_valid(unit):
			stale.append(unit)
	for unit in stale:
		_registered_units.erase(unit)


func recalculate_cap_from_buildings() -> void:
	var cap := (
		BASE_POPULATION_CAP
		+ MetaProgression.get_extra_villagers()
		+ MetaProgression.get_population_cap_bonus()
		+ boon_population_bonus
	)
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
