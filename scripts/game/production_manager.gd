class_name ProductionManager
extends Node

signal queue_changed(building: Building)
signal production_completed(building: Building, item_id: String)

const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/unit_villager.tscn")

var _resource_manager: ResourceManager
var _population_manager: PopulationManager
var _job_manager: JobManager
var _units_container: Node2D
var _ground_layer: TinyTilesMap

# building -> Array of queue entries
var _queues: Dictionary = {}
# building -> Array of { item_id, transforms_to } waiting for idle villagers
var _pending_recruitment: Dictionary = {}


func setup(
	resource_manager: ResourceManager,
	population_manager: PopulationManager,
	job_manager: JobManager,
	units_container: Node2D,
	ground_layer: TinyTilesMap
) -> void:
	_resource_manager = resource_manager
	_population_manager = population_manager
	_job_manager = job_manager
	_units_container = units_container
	_ground_layer = ground_layer
	if _population_manager != null:
		_population_manager.population_changed.connect(_on_population_changed)


func _process(delta: float) -> void:
	if _queues.is_empty() and _pending_recruitment.is_empty():
		return
	for building in _queues.keys():
		if not is_instance_valid(building):
			_queues.erase(building)
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		_advance_queue(building, delta)

	_process_pending_recruitment()


func register_producer(building: Building) -> void:
	if not _queues.has(building):
		_queues[building] = []


func unregister_producer(building: Building) -> void:
	if _population_manager != null:
		for entry in _queues.get(building, []):
			_population_manager.release_reserved_population(entry.get("reserved_population", 0))
		for entry in _pending_recruitment.get(building, []):
			_population_manager.release_reserved_population(entry.get("reserved_population", 0))
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit and (node as Unit).recruitment_building == building:
			(node as Unit).cancel_recruitment()
	_queues.erase(building)
	_pending_recruitment.erase(building)


func get_production_availability(
	building: Building,
	item_id: String,
	output_count: int = 1
) -> Dictionary:
	var result := {
		"can_produce": true,
		"missing_resources": false,
		"missing_population": false,
		"other_block": "",
	}
	if not is_instance_valid(building) or building.building_state != Building.BuildingState.ACTIVE:
		result.can_produce = false
		result.other_block = "El edificio no está activo"
		return result
	if not EquipmentDatabase.can_produce_at(building.building_type_id, item_id):
		result.can_produce = false
		result.other_block = "No se puede producir aquí"
		return result
	var def := EquipmentDatabase.get_definition(item_id)
	if def.is_empty():
		result.can_produce = false
		result.other_block = "Unidad desconocida"
		return result

	var cost: Dictionary = def.get("cost", {})
	if _resource_manager == null or not _resource_manager.can_afford(cost):
		result.missing_resources = true
		result.can_produce = false

	var transforms_to: String = def.get("transforms_to", "")
	if transforms_to.is_empty():
		if _population_manager != null \
				and not _population_manager.can_reserve_population(maxi(1, output_count)):
			result.missing_population = true
			result.can_produce = false
	else:
		var squad_size: int = def.get("squad_size", 1)
		var reserved_needed := maxi(0, squad_size - 1) * output_count
		if reserved_needed > 0:
			if _population_manager == null:
				result.can_produce = false
				result.other_block = "No hay gestor de población"
				return result
			if not _population_manager.can_reserve_population(reserved_needed):
				result.missing_population = true
				result.can_produce = false

	return result


func get_enqueue_block_reason(building: Building, item_id: String, output_count: int = 1) -> String:
	var availability := get_production_availability(building, item_id, output_count)
	if not availability.other_block.is_empty():
		return availability.other_block
	if availability.missing_resources and availability.missing_population:
		return "Faltan recursos y espacio de población"
	if availability.missing_resources:
		return "Recursos insuficientes"
	if availability.missing_population:
		return "Falta espacio de población — construye casas"
	return ""


func enqueue(building: Building, item_id: String, batch_count: int = 1) -> bool:
	if not get_production_availability(building, item_id, batch_count).can_produce:
		return false

	var def := EquipmentDatabase.get_definition(item_id)
	var cost: Dictionary = def.get("cost", {})
	var squad_size: int = def.get("squad_size", 1)
	var reserved_per_item := maxi(0, squad_size - 1)
	var total_reserved := reserved_per_item * batch_count
	if total_reserved > 0 and not _population_manager.reserve_population(total_reserved):
		return false
	register_producer(building)
	var queue: Array = _queues[building]
	for _i in batch_count:
		queue.append({
			"item_id": item_id,
			"progress": 0.0,
			"time_total": def.get("train_time", 10.0),
			"cost": cost.duplicate(),
			"paid": false,
			"reserved_population": reserved_per_item,
		})
	queue_changed.emit(building)
	return true


func get_queue_size(building: Building) -> int:
	return get_queue(building).size()


func get_queue(building: Building) -> Array:
	if not _queues.has(building):
		return []
	return _queues[building]


func get_pending_recruitment(building: Building) -> Dictionary:
	var queue: Array = _pending_recruitment.get(building, [])
	if queue.is_empty():
		return {}
	return {
		"count": queue.size(),
		"item_id": queue[0].get("item_id", ""),
	}


func get_queue_counts(building: Building) -> Dictionary:
	var counts: Dictionary = {}
	for entry in get_queue(building):
		var item_id: String = entry.get("item_id", "")
		counts[item_id] = counts.get(item_id, 0) + 1
	return counts


func _on_population_changed(_population: int, _population_cap: int) -> void:
	for building in _queues.keys():
		if is_instance_valid(building):
			queue_changed.emit(building)


func _advance_queue(building: Building, delta: float) -> void:
	var queue: Array = _queues.get(building, [])
	if queue.is_empty():
		return

	var current: Dictionary = queue[0]
	if not current.get("paid", false):
		var cost: Dictionary = current.get("cost", {})
		if not _resource_manager.can_afford(cost):
			return
		if not _resource_manager.spend(cost):
			return
		current.paid = true
		queue_changed.emit(building)

	current.progress = current.get("progress", 0.0) + delta
	if current.progress < current.get("time_total", 10.0):
		return

	var item_id: String = current.get("item_id", "")
	var def := EquipmentDatabase.get_definition(item_id)
	if def.get("transforms_to", "").is_empty():
		if _population_manager != null and not _population_manager.can_add_population():
			return

	queue.remove_at(0)
	queue_changed.emit(building)
	_on_item_completed(building, item_id, current.get("reserved_population", 0))
	production_completed.emit(building, item_id)


func _on_item_completed(building: Building, item_id: String, reserved_population: int = 0) -> void:
	var def := EquipmentDatabase.get_definition(item_id)
	var transforms_to: String = def.get("transforms_to", "")
	var output_count := _get_production_output_count()
	if transforms_to.is_empty():
		for _i in output_count:
			_spawn_villager(building)
		return

	if not _pending_recruitment.has(building):
		_pending_recruitment[building] = []
	var pending_queue: Array = _pending_recruitment[building]
	for i in output_count:
		pending_queue.append({
			"item_id": item_id,
			"transforms_to": transforms_to,
			"squad_size": def.get("squad_size", 1),
			"reserved_population": reserved_population if i == 0 else 0,
			"squad_id": "%d-%d-%d" % [building.get_instance_id(), Time.get_ticks_msec(), randi()],
		})
	queue_changed.emit(building)


func _get_production_output_count() -> int:
	var boons := get_tree().get_first_node_in_group("run_boon_manager")
	if boons is RunBoonManager:
		return (boons as RunBoonManager).get_production_output_count()
	return 1


func _process_pending_recruitment() -> void:
	if _job_manager == null:
		return

	for building in _pending_recruitment.keys():
		if not is_instance_valid(building):
			if _population_manager != null:
				for entry in _pending_recruitment.get(building, []):
					_population_manager.release_reserved_population(entry.get("reserved_population", 0))
			_pending_recruitment.erase(building)
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			unregister_producer(building)
			continue

		var pending_queue: Array = _pending_recruitment[building]
		var changed := false
		while not pending_queue.is_empty():
			var entry: Dictionary = pending_queue[0]
			var villagers := _job_manager.collect_civilian_villagers(1)
			if villagers.is_empty():
				break
			var villager: Unit = villagers[0]
			if not is_instance_valid(villager):
				break
			villager.begin_recruitment(
				building,
				entry.get("transforms_to", ""),
				entry.get("squad_size", 1),
				entry.get("squad_id", "")
			)
			pending_queue.remove_at(0)
			changed = true

		if pending_queue.is_empty():
			_pending_recruitment.erase(building)
		if changed:
			queue_changed.emit(building)


func _spawn_villager(building: Building) -> void:
	if _population_manager != null and not _population_manager.can_add_population():
		return
	if _units_container == null or VILLAGER_SCENE == null:
		return

	var spawn_pos := building.get_exit_position()
	var villager: Unit = VILLAGER_SCENE.instantiate()
	_units_container.add_child(villager)
	villager.global_position = spawn_pos
	if _ground_layer != null:
		villager.set_ground_layer(_ground_layer)
	villager.reset_navigation()
	if _population_manager != null:
		_population_manager.register_unit(villager)
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("register_player_unit"):
		world.register_player_unit(villager)
	if _job_manager != null:
		_job_manager.on_villager_spawned(villager)
