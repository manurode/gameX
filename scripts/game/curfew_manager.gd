class_name CurfewManager
extends Node

signal curfew_changed(active: bool)

const RECHECK_INTERVAL := 0.5

var is_active: bool = false

var _job_manager: JobManager
var _recheck_timer := 0.0


func _ready() -> void:
	add_to_group("curfew_manager")


func setup(job_manager: JobManager) -> void:
	_job_manager = job_manager


func toggle() -> void:
	set_active(not is_active)


func set_active(active: bool) -> void:
	if is_active == active:
		return
	is_active = active
	curfew_changed.emit(is_active)
	if is_active:
		_enforce_curfew()
	else:
		_release_curfew()


func find_nearest_shelter(villager: Unit) -> Building:
	var candidates: Array[Building] = []
	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER:
			continue
		if not building.can_enter_garrison(villager):
			continue
		candidates.append(building)

	if candidates.is_empty():
		return null

	var villager_pos := villager.global_position
	candidates.sort_custom(func(a: Building, b: Building) -> bool:
		return villager_pos.distance_squared_to(a.global_position) < villager_pos.distance_squared_to(b.global_position)
	)
	return candidates[0]


func send_villager_to_shelter(villager: Unit) -> void:
	if not _is_villager(villager) or villager.garrisoned_building != null:
		return
	if villager._unit_state == Unit.UnitState.RECRUITING:
		return

	var building := find_nearest_shelter(villager)
	if building == null:
		return

	if villager.garrison_approach_target == building:
		return

	villager.approach_garrison(building)


func _process(delta: float) -> void:
	if not is_active:
		return
	_recheck_timer -= delta
	if _recheck_timer > 0.0:
		return
	_recheck_timer = RECHECK_INTERVAL
	_enforce_curfew()


func _enforce_curfew() -> void:
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		send_villager_to_shelter(node as Unit)


func _release_curfew() -> void:
	var buildings: Array[Building] = []
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if not _is_villager(unit) or unit.garrisoned_building == null:
			continue
		var building := unit.garrisoned_building
		if not buildings.has(building):
			buildings.append(building)
	for building in buildings:
		if is_instance_valid(building):
			building.exit_all_garrison()

	if _job_manager == null:
		return
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if _is_villager(unit) and not unit.is_busy():
			_job_manager.try_assign_idle_villager(unit)


func _is_villager(unit: Unit) -> bool:
	return (
		unit.is_civilian
		and unit.team_id == Team.PLAYER
		and not unit._is_dying
		and unit.hp > 0
	)
