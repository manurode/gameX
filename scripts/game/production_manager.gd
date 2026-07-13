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
# building -> pending recruitment { item_id, count, transforms_to }
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


func _process(delta: float) -> void:
	for building in _queues.keys():
		if not is_instance_valid(building):
			_queues.erase(building)
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if _population_manager != null and _population_manager.food_shortage_active:
			continue
		_advance_queue(building, delta)

	_process_pending_recruitment()


func register_producer(building: Building) -> void:
	if not _queues.has(building):
		_queues[building] = []


func unregister_producer(building: Building) -> void:
	_queues.erase(building)
	_pending_recruitment.erase(building)


func enqueue(building: Building, item_id: String, batch_count: int = 1) -> bool:
	if not is_instance_valid(building) or building.building_state != Building.BuildingState.ACTIVE:
		return false
	if not EquipmentDatabase.can_produce_at(building.building_type_id, item_id):
		return false

	var def := EquipmentDatabase.get_definition(item_id)
	var cost: Dictionary = def.get("cost", {})
	register_producer(building)
	var queue: Array = _queues[building]
	for _i in batch_count:
		queue.append({
			"item_id": item_id,
			"progress": 0.0,
			"time_total": def.get("train_time", 10.0),
			"cost": cost.duplicate(),
			"paid": false,
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
	return _pending_recruitment.get(building, {})


func _advance_queue(building: Building, delta: float) -> void:
	var queue: Array = _queues.get(building, [])
	if queue.is_empty():
		return

	var current: Dictionary = queue[0]
	if not current.get("paid", false):
		var cost: Dictionary = current.get("cost", {})
		if not _resource_manager.can_afford(cost):
			queue_changed.emit(building)
			return
		if not _resource_manager.spend(cost):
			queue_changed.emit(building)
			return
		current.paid = true

	current.progress = current.get("progress", 0.0) + delta
	if current.progress < current.get("time_total", 10.0):
		queue_changed.emit(building)
		return

	var item_id: String = current.get("item_id", "")
	queue.remove_at(0)
	queue_changed.emit(building)
	_on_item_completed(building, item_id)
	production_completed.emit(building, item_id)


func _on_item_completed(building: Building, item_id: String) -> void:
	var def := EquipmentDatabase.get_definition(item_id)
	var transforms_to: String = def.get("transforms_to", "")
	if transforms_to.is_empty():
		_spawn_villager(building)
		return

	var batch_size: int = def.get("batch_size", 1)
	if _pending_recruitment.has(building):
		var pending: Dictionary = _pending_recruitment[building]
		if pending.get("item_id", "") == item_id:
			pending.count += batch_size
		else:
			_pending_recruitment[building] = {"item_id": item_id, "count": batch_size, "transforms_to": transforms_to}
	else:
		_pending_recruitment[building] = {"item_id": item_id, "count": batch_size, "transforms_to": transforms_to}


func _process_pending_recruitment() -> void:
	for building in _pending_recruitment.keys():
		if not is_instance_valid(building):
			_pending_recruitment.erase(building)
			continue
		var pending: Dictionary = _pending_recruitment[building]
		var needed: int = pending.get("count", 0)
		if needed <= 0:
			_pending_recruitment.erase(building)
			continue

		if _job_manager == null:
			continue

		var villagers := _job_manager.collect_civilian_villagers(needed)
		for villager in villagers:
			if needed <= 0:
				break
			if not is_instance_valid(villager):
				continue
			villager.begin_recruitment(building, pending.get("transforms_to", ""))
			needed -= 1

		if needed <= 0:
			_pending_recruitment.erase(building)
		else:
			pending.count = needed


func _spawn_villager(building: Building) -> void:
	if _population_manager != null and not _population_manager.can_add_population():
		return
	if _units_container == null or VILLAGER_SCENE == null:
		return

	var villager: Unit = VILLAGER_SCENE.instantiate()
	_units_container.add_child(villager)
	villager.global_position = building.global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 10.0))
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
