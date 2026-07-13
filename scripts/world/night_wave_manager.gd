extends Node

class_name NightWaveManager

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/unit_enemy.tscn")
const MIN_ENEMIES := 6
const MAX_ENEMIES := 8
const EDGE_MARGIN := 48.0
const WALKABLE_SEARCH_RADIUS := 96.0

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
	var bounds := _ground.get_map_bounds()
	var sides: Array[String] = ["top", "bottom", "left", "right"]
	var points: Array[Vector2] = []

	for i in count:
		var side: String = sides[i % sides.size()]
		var edge_point := _point_on_edge(bounds, side)
		points.append(_find_walkable_near(edge_point))

	return points


func _point_on_edge(bounds: Rect2, side: String) -> Vector2:
	var center := bounds.get_center()
	var jitter := randf_range(-bounds.size.x * 0.2, bounds.size.x * 0.2)

	match side:
		"top":
			return Vector2(center.x + jitter, bounds.position.y + EDGE_MARGIN)
		"bottom":
			return Vector2(center.x + jitter, bounds.end.y - EDGE_MARGIN)
		"left":
			return Vector2(bounds.position.x + EDGE_MARGIN, center.y + jitter)
		"right":
			return Vector2(bounds.end.x - EDGE_MARGIN, center.y + jitter)
		_:
			return center


func _find_walkable_near(origin: Vector2) -> Vector2:
	if _ground != null and not _ground.is_water_at(origin):
		return origin

	for radius in range(16, int(WALKABLE_SEARCH_RADIUS), 16):
		for angle_idx in 8:
			var angle := TAU * float(angle_idx) / 8.0
			var candidate := origin + Vector2(cos(angle), sin(angle)) * float(radius)
			if _ground != null and not _ground.is_water_at(candidate):
				return candidate

	return origin
