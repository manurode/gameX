class_name JobManager
extends Node

const GATHER_CARRY_AMOUNT := 10
const GATHER_TIME_AT_NODE := 2.5
const AUTO_BUILD_RADIUS := 450.0

var _resource_manager: ResourceManager
var _population_manager: PopulationManager
var _ground_layer: TinyTilesMap

var _building_workers: Dictionary = {}
var _unit_jobs: Dictionary = {}
var _return_buildings: Dictionary = {}


func setup(
	resource_manager: ResourceManager,
	population_manager: PopulationManager,
	ground_layer: TinyTilesMap
) -> void:
	_resource_manager = resource_manager
	_population_manager = population_manager
	_ground_layer = ground_layer


func on_building_completed(building: Building) -> void:
	if not BuildingDatabase.is_gather_building(building.building_type_id):
		return
	register_gather_building(building)
	if _population_manager != null:
		_population_manager.recalculate_cap_from_buildings()


func on_building_destroyed(building: Building) -> void:
	_release_building_workers(building)


func on_villager_spawned(villager: Unit) -> void:
	try_assign_idle_villager(villager)


func register_gather_building(building: Building) -> void:
	if not _building_workers.has(building):
		_building_workers[building] = []
	_fill_building_workers(building)


func try_assign_idle_villager(villager: Unit) -> void:
	if not is_instance_valid(villager) or not villager.is_civilian:
		return
	if villager.is_busy():
		return
	if _population_manager != null and _population_manager.food_shortage_active:
		return

	if _return_buildings.has(villager):
		var remembered: Building = _return_buildings[villager]
		_return_buildings.erase(villager)
		if is_instance_valid(remembered) and _can_assign_to_building(villager, remembered):
			_assign_villager_to_building(villager, remembered)
			return

	if _try_assign_nearby_construction(villager):
		return

	var best_building := _find_best_gather_building_for_villager(villager)
	if best_building != null:
		_assign_villager_to_building(villager, best_building)


func on_villager_manual_move(unit: Unit) -> void:
	if not unit.is_civilian:
		return
	if _unit_jobs.has(unit):
		var building: Building = _unit_jobs[unit].get("building")
		if building != null:
			_return_buildings[unit] = building
		release_unit_job(unit)


func on_villager_move_completed(unit: Unit) -> void:
	if not unit.is_civilian or unit.is_busy():
		return
	try_assign_idle_villager(unit)


func assign_villagers_to_resource(villagers: Array, resource_node: ResourceNode) -> bool:
	if resource_node == null or not resource_node.has_resources():
		return false

	var building := find_gather_building_for_resource(resource_node)
	if building == null:
		return false

	var assigned := false
	for unit in villagers:
		if not unit is Unit:
			continue
		var villager := unit as Unit
		if not villager.is_civilian or not villager.can_gather:
			continue
		if not _can_assign_to_building(villager, building):
			continue
		_return_buildings.erase(villager)
		_assign_villager_to_resource(villager, building, resource_node)
		assigned = true
	return assigned


func find_gather_building_for_resource(resource_node: ResourceNode) -> Building:
	var gather_type := resource_node.get_resource_key()
	if gather_type.is_empty():
		return null

	var best_building: Building = null
	var best_dist := INF

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if BuildingDatabase.get_gather_type(building.building_type_id) != gather_type:
			continue
		if not _building_covers_resource(building, resource_node):
			continue
		var dist := building.global_position.distance_squared_to(resource_node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_building = building

	return best_building


func collect_civilian_villagers(count: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var candidates: Array[Unit] = []

	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if not unit.is_civilian or unit._is_dying or unit.hp <= 0:
			continue
		if unit._unit_state == Unit.UnitState.RECRUITING:
			continue
		if unit.garrisoned_building != null:
			continue
		candidates.append(unit)

	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.is_busy() and not b.is_busy()
	)

	for unit in candidates:
		if result.size() >= count:
			break
		release_unit_job(unit)
		result.append(unit)
	return result


func get_worker_building(unit: Unit) -> Building:
	if not _unit_jobs.has(unit):
		return null
	return _unit_jobs[unit].get("building")


func release_unit_job(unit: Unit) -> void:
	if not _unit_jobs.has(unit):
		return
	var job: Dictionary = _unit_jobs[unit]
	var building: Building = job.get("building")
	if building != null and _building_workers.has(building):
		var workers: Array = _building_workers[building]
		workers.erase(unit)
	_unit_jobs.erase(unit)
	if is_instance_valid(unit):
		unit.clear_gather_job()


func on_unit_reached_deposit_building(unit: Unit, building: Building) -> void:
	if not _unit_jobs.has(unit):
		return
	if _population_manager != null and _population_manager.food_shortage_active:
		return

	var job: Dictionary = _unit_jobs[unit]
	var node: ResourceNode = job.get("node")
	if node == null or not node.has_resources():
		_reassign_unit_from_job(unit)
		return

	var gather_type: String = BuildingDatabase.get_gather_type(building.building_type_id)
	var gathered := node.harvest(GATHER_CARRY_AMOUNT)
	if gathered > 0 and _resource_manager != null:
		var amounts := {"wood": 0, "stone": 0, "food": 0}
		amounts[gather_type] = gathered
		_resource_manager.add_resources(amounts)

	if not node.has_resources():
		_reassign_building_workers(building)
		return

	job.phase = "travel_to_node"
	unit.assign_gather_at_node(node)


func on_construction_finished(unit: Unit) -> void:
	release_unit_job(unit)
	try_assign_idle_villager(unit)


func alert_nearby_builders(site: Building) -> void:
	if site == null or not is_instance_valid(site):
		return
	if site.building_state != Building.BuildingState.CONSTRUCTING:
		return

	var radius_sq := AUTO_BUILD_RADIUS * AUTO_BUILD_RADIUS
	var site_pos := site.global_position

	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue

		var villager := node as Unit
		if villager.global_position.distance_squared_to(site_pos) > radius_sq:
			continue
		if not _can_auto_build(villager):
			continue

		villager.assign_construction(site)


func _can_auto_build(villager: Unit) -> bool:
	if not villager.can_build or not villager.is_civilian:
		return false
	if villager.team_id != Team.PLAYER:
		return false
	if villager.is_busy():
		return false
	if villager._is_dying or villager.hp <= 0:
		return false
	if villager.garrisoned_building != null or villager.garrison_approach_target != null:
		return false
	if villager.construction_target != null:
		return false
	return true


func _try_assign_nearby_construction(villager: Unit) -> bool:
	if not _can_auto_build(villager):
		return false

	var radius_sq := AUTO_BUILD_RADIUS * AUTO_BUILD_RADIUS
	var villager_pos := villager.global_position
	var best_site: Building = null
	var best_dist := INF

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.building_state != Building.BuildingState.CONSTRUCTING:
			continue
		var dist_sq := villager_pos.distance_squared_to(building.global_position)
		if dist_sq > radius_sq:
			continue
		if dist_sq < best_dist:
			best_dist = dist_sq
			best_site = building

	if best_site == null:
		return false

	release_unit_job(villager)
	villager.assign_construction(best_site)
	return true


func _can_assign_to_building(villager: Unit, building: Building) -> bool:
	if not is_instance_valid(building) or building.building_state != Building.BuildingState.ACTIVE:
		return false
	var workers: Array = _building_workers.get(building, [])
	var def := BuildingDatabase.get_definition(building.building_type_id)
	return workers.size() < def.get("max_workers", 0)


func _assign_villager_to_resource(villager: Unit, building: Building, resource_node: ResourceNode) -> void:
	if not _building_workers.has(building):
		_building_workers[building] = []

	var workers: Array = _building_workers[building]
	if not workers.has(villager):
		workers.append(villager)

	release_unit_job(villager)
	_unit_jobs[villager] = {
		"building": building,
		"node": resource_node,
		"phase": "travel_to_node",
	}
	villager.assign_gather_at_node(resource_node)


func _fill_building_workers(building: Building) -> void:
	var def := BuildingDatabase.get_definition(building.building_type_id)
	var max_workers: int = def.get("max_workers", 0)
	if max_workers <= 0:
		return

	var workers: Array = _building_workers.get(building, [])
	while workers.size() < max_workers:
		var villager := _find_idle_civilian()
		if villager == null:
			break
		var node := _find_nearest_resource_node(building)
		if node == null:
			break
		_assign_villager_to_resource(villager, building, node)


func _assign_villager_to_building(villager: Unit, building: Building) -> void:
	var node := _find_nearest_resource_node(building)
	if node == null:
		return
	_assign_villager_to_resource(villager, building, node)


func _find_idle_civilian() -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		if not node is Unit:
			continue
		var unit := node as Unit
		if unit.is_civilian and not unit.is_busy() and not unit._is_dying and unit.hp > 0:
			return unit
	return null


func _find_best_gather_building_for_villager(_villager: Unit) -> Building:
	var best_building: Building = null
	var best_score := INF

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if not BuildingDatabase.is_gather_building(building.building_type_id):
			continue

		var workers: Array = _building_workers.get(building, [])
		var def := BuildingDatabase.get_definition(building.building_type_id)
		if workers.size() >= def.get("max_workers", 0):
			continue
		if _find_nearest_resource_node(building) == null:
			continue

		var score := float(workers.size()) * 1000.0
		if score < best_score:
			best_score = score
			best_building = building

	return best_building


func _building_covers_resource(building: Building, resource_node: ResourceNode) -> bool:
	if _ground_layer == null:
		return false
	var gather_type: String = BuildingDatabase.get_gather_type(building.building_type_id)
	if gather_type != resource_node.get_resource_key():
		return false
	var def := BuildingDatabase.get_definition(building.building_type_id)
	var radius_cells: int = def.get("gather_radius_cells", 3)
	var cell := _ground_layer.local_to_map(building.global_position)
	var node_cell := _ground_layer.local_to_map(resource_node.global_position)
	return Vector2(cell - node_cell).length() <= float(radius_cells)


func _find_nearest_resource_node(building: Building) -> ResourceNode:
	var gather_type: String = BuildingDatabase.get_gather_type(building.building_type_id)
	if gather_type.is_empty() or _ground_layer == null:
		return null

	var def := BuildingDatabase.get_definition(building.building_type_id)
	var radius_cells: int = def.get("gather_radius_cells", 3)
	var cell := _ground_layer.local_to_map(building.global_position)
	var best_node: ResourceNode = null
	var best_dist := INF

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not node is ResourceNode:
			continue
		var resource_node := node as ResourceNode
		if not resource_node.has_resources():
			continue
		if resource_node.get_resource_key() != gather_type:
			continue

		var node_cell := _ground_layer.local_to_map(resource_node.global_position)
		var dist := Vector2(cell - node_cell).length()
		if dist > float(radius_cells):
			continue
		if dist < best_dist:
			best_dist = dist
			best_node = resource_node

	return best_node


func _reassign_unit_from_job(unit: Unit) -> void:
	var old_job: Dictionary = _unit_jobs.get(unit, {})
	var building: Building = old_job.get("building")
	release_unit_job(unit)
	if building != null and is_instance_valid(building):
		_fill_building_workers(building)
	else:
		try_assign_idle_villager(unit)


func _reassign_building_workers(building: Building) -> void:
	var workers: Array = _building_workers.get(building, []).duplicate()
	for worker in workers:
		if worker is Unit:
			release_unit_job(worker)
	_building_workers[building] = []
	_fill_building_workers(building)


func _release_building_workers(building: Building) -> void:
	var workers: Array = _building_workers.get(building, []).duplicate()
	for worker in workers:
		if worker is Unit:
			_return_buildings.erase(worker)
			release_unit_job(worker)
			try_assign_idle_villager(worker)
	_building_workers.erase(building)
