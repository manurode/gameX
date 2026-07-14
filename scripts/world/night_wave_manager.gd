extends Node

class_name NightWaveManager

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/unit_enemy.tscn")
const MIN_ENEMIES := 6
const MAX_ENEMIES := 20
const EDGE_MARGIN := 48.0

var _day_night: DayNightManager
var _units_container: Node2D
var _ground: TinyTilesMap
var _spawned: Array[EnemyUnit] = []


func setup(day_night: DayNightManager, units: Node2D, ground: TinyTilesMap) -> void:
	_day_night = day_night
	_units_container = units
	_ground = ground
	_day_night.cycle_changed.connect(_on_cycle_changed)


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	if phase == DayNightManager.CyclePhase.NIGHT:
		_spawn_wave()
	else:
		_despawn_all()


func _spawn_wave() -> void:
	_despawn_all()
	if _ground == null or _units_container == null:
		return

	var count := randi_range(MIN_ENEMIES, MAX_ENEMIES)
	var spawn_points := _get_edge_spawn_points(count)
	for point in spawn_points:
		var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
		_units_container.add_child(enemy)
		enemy.global_position = point
		enemy.set_ground_layer(_ground)
		enemy.reset_navigation()
		if _day_night.is_night():
			enemy.apply_cycle_visuals(true)
		_spawned.append(enemy)


func _despawn_all() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()

	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()


func _get_edge_spawn_points(count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var edge_cells := _ground.get_walkable_edge_cells()
	if edge_cells.is_empty():
		return points
	edge_cells.shuffle()
	var town_position := _ground.map_to_local(_ground.get_town_center_cell())
	for i in count:
		var edge_position := _ground.map_to_local(edge_cells[i % edge_cells.size()])
		var inward := edge_position.direction_to(town_position) * EDGE_MARGIN
		points.append(edge_position + inward)
	return points
