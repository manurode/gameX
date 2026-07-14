extends Node

class_name NightWaveManager

signal wave_warning(direction_name: String)
signal wave_started(enemy_count: int)

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/unit_enemy.tscn")
const EDGE_MARGIN := 48.0

var _day_night: DayNightManager
var _units_container: Node2D
var _ground: TinyTilesMap
var _spawned: Array[EnemyUnit] = []
var _attack_direction: String = "Oeste"


func _ready() -> void:
	add_to_group("night_wave_manager")


func setup(day_night: DayNightManager, units: Node2D, ground: TinyTilesMap) -> void:
	_day_night = day_night
	_units_container = units
	_ground = ground
	_day_night.cycle_changed.connect(_on_cycle_changed)


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	match phase:
		DayNightManager.CyclePhase.DUSK:
			_despawn_all()
			_attack_direction = ["Norte", "Este", "Sur", "Oeste"].pick_random()
			wave_warning.emit(_attack_direction)
		DayNightManager.CyclePhase.NIGHT:
			_spawn_wave()
		DayNightManager.CyclePhase.DAWN:
			_despawn_all()


func _spawn_wave() -> void:
	_despawn_all()
	if _ground == null or _units_container == null:
		return

	var count := _get_wave_size()
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
	wave_started.emit(_spawned.size())


func _get_wave_size() -> int:
	var cycle_bonus := maxi(0, _day_night.cycle_number - 1) * 3
	var military_count := 0
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit and (node as Unit).team_id == Team.PLAYER and not (node as Unit).is_civilian:
			military_count += 1
	return clampi(6 + cycle_bonus + floori(float(military_count) / 3.0), 6, 100)


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
	var directional_cells: Array[Vector2i] = []
	for cell in edge_cells:
		var offset := _ground.map_to_local(cell) - town_position
		var matches := (
			(_attack_direction == "Norte" and offset.y < 0.0 and absf(offset.y) >= absf(offset.x))
			or (_attack_direction == "Sur" and offset.y > 0.0 and absf(offset.y) >= absf(offset.x))
			or (_attack_direction == "Este" and offset.x > 0.0 and absf(offset.x) >= absf(offset.y))
			or (_attack_direction == "Oeste" and offset.x < 0.0 and absf(offset.x) >= absf(offset.y))
		)
		if matches:
			directional_cells.append(cell)
	if directional_cells.is_empty():
		directional_cells = edge_cells
	for i in count:
		var edge_position := _ground.map_to_local(directional_cells[i % directional_cells.size()])
		var inward := edge_position.direction_to(town_position) * EDGE_MARGIN
		points.append(edge_position + inward)
	return points
