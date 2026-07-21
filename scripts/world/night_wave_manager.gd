extends Node

class_name NightWaveManager

signal wave_warning(direction_name: String, modifier_id: int, modifier_name: String)
signal wave_started(enemy_count: int, modifier_id: int)
signal foresight_ready(
	modifier_id: int,
	modifier_name: String,
	direction_name: String,
	enemy_count: int
)

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/unit_enemy.tscn")
const EDGE_MARGIN := 48.0
const FOG_EDGE_MARGIN := 140.0
const CONTINUOUS_SPAWN_INTERVAL := 4.5
const CARDINAL_DIRECTIONS := ["Norte", "Este", "Sur", "Oeste"]

var _day_night: DayNightManager
var _units_container: Node2D
var _ground: TinyTilesMap
var _spawned: Array[EnemyUnit] = []
var _attack_direction: String = "Oeste"
var _secondary_direction: String = ""
var _next_attack_direction: String = "Oeste"
var _next_secondary_direction: String = ""
var _next_enemy_count: int = 0
var _planned_enemy_count: int = 0
var _current_modifier: NightModifier.Id = NightModifier.Id.SWARM
var _next_modifier: NightModifier.Id = NightModifier.Id.SWARM
var _modifier_ready: bool = false
var _continuous_remaining: int = 0
var _continuous_timer: float = 0.0
var _continuous_def: Dictionary = {}
var _used_curfew_bonus: bool = false


func _ready() -> void:
	add_to_group("night_wave_manager")


func setup(day_night: DayNightManager, units: Node2D, ground: TinyTilesMap) -> void:
	_day_night = day_night
	_units_container = units
	_ground = ground
	_pick_next_modifier()
	if not _day_night.cycle_changed.is_connected(_on_cycle_changed):
		_day_night.cycle_changed.connect(_on_cycle_changed)
	_try_emit_foresight()


func get_current_modifier() -> NightModifier.Id:
	return _current_modifier


func get_next_modifier() -> NightModifier.Id:
	return _next_modifier


func get_attack_direction() -> String:
	return _attack_direction


func refresh_foresight() -> void:
	_try_emit_foresight()


func debug_clear_wave() -> void:
	_continuous_remaining = 0
	_despawn_all()


func _process(delta: float) -> void:
	if _continuous_remaining <= 0 or _day_night == null or not _day_night.is_night():
		return
	_continuous_timer -= delta
	if _continuous_timer > 0.0:
		return
	_continuous_timer = CONTINUOUS_SPAWN_INTERVAL
	# Late nights need bigger drip batches or the wave never finishes in time.
	var batch_cap := clampi(3 + _day_night.cycle_number / 4, 3, 12)
	var batch := mini(batch_cap, _continuous_remaining)
	_continuous_remaining -= batch
	_spawn_enemies(batch, _continuous_def)


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	match phase:
		DayNightManager.CyclePhase.DAY:
			_try_emit_foresight()
		DayNightManager.CyclePhase.DUSK:
			_despawn_all()
			if _is_summer_equinox():
				_continuous_remaining = 0
				return
			_activate_modifier_for_night()
			_attack_direction = _next_attack_direction
			_secondary_direction = _next_secondary_direction
			_planned_enemy_count = _next_enemy_count
			_try_free_curfew()
			wave_warning.emit(
				_format_direction_text(_attack_direction, _secondary_direction),
				int(_current_modifier),
				NightModifier.get_display_name(_current_modifier)
			)
		DayNightManager.CyclePhase.NIGHT:
			if _is_summer_equinox():
				_continuous_remaining = 0
				return
			_spawn_wave()
		DayNightManager.CyclePhase.DAWN:
			_continuous_remaining = 0
			_despawn_all()
			_pick_next_modifier()


func _is_summer_equinox() -> bool:
	var boons := get_tree().get_first_node_in_group("run_boon_manager")
	return boons is RunBoonManager and (boons as RunBoonManager).should_keep_daylight()


func _activate_modifier_for_night() -> void:
	_current_modifier = _next_modifier
	_modifier_ready = true
	var def := NightModifier.get_definition(_current_modifier)
	_day_night.use_fog_visuals = bool(def.get("fog", false))
	if def.get("eclipse", false):
		_day_night.night_duration_multiplier = BalanceConfig.ECLIPSE_NIGHT_DURATION_MULT
	else:
		_day_night.night_duration_multiplier = 1.0


func _pick_next_modifier() -> void:
	_next_modifier = NightModifier.pick_random([_current_modifier] if _modifier_ready else [])
	_pick_next_directions()
	_next_enemy_count = _compute_enemy_count(_next_modifier)


func _pick_next_directions() -> void:
	_next_attack_direction = CARDINAL_DIRECTIONS.pick_random()
	_next_secondary_direction = ""
	var def := NightModifier.get_definition(_next_modifier)
	if def.get("dual_direction", false):
		var dirs := CARDINAL_DIRECTIONS.duplicate()
		dirs.erase(_next_attack_direction)
		_next_secondary_direction = dirs.pick_random()


func _format_direction_text(primary: String, secondary: String) -> String:
	if secondary.is_empty():
		return primary
	return "%s y %s" % [primary, secondary]


func _compute_enemy_count(modifier: NightModifier.Id) -> int:
	var def := NightModifier.get_definition(modifier)
	var base_count := _get_wave_size()
	var count := maxi(4, int(round(float(base_count) * float(def.get("count_mult", 1.0)))))
	if modifier == NightModifier.Id.ELITE:
		count += maxi(1, mini(6, 1 + _day_night.cycle_number / 3))
	return count


func _try_emit_foresight() -> void:
	if _is_summer_equinox():
		return
	if MetaProgression.has_foresight():
		foresight_ready.emit(
			int(_next_modifier),
			NightModifier.get_display_name(_next_modifier),
			_format_direction_text(_next_attack_direction, _next_secondary_direction),
			_next_enemy_count
		)


func _try_free_curfew() -> void:
	if _used_curfew_bonus or not MetaProgression.has_free_curfew():
		return
	_used_curfew_bonus = true
	var curfew := get_tree().get_first_node_in_group("curfew_manager")
	if curfew is CurfewManager:
		(curfew as CurfewManager).set_active(true)


func _spawn_wave() -> void:
	_despawn_all()
	if _ground == null or _units_container == null:
		return

	var def := NightModifier.get_definition(_current_modifier)
	var count := _planned_enemy_count
	if count <= 0:
		count = _compute_enemy_count(_current_modifier)

	# Elite nights bake bonus elites into the planned total; peel them off to spawn separately.
	var elite_extras := 0
	if _current_modifier == NightModifier.Id.ELITE:
		elite_extras = maxi(1, mini(6, 1 + _day_night.cycle_number / 3))
		count = maxi(4, count - elite_extras)

	if def.get("continuous_spawn", false):
		var initial := maxi(4, int(count * 0.45))
		_continuous_remaining = count - initial
		_continuous_timer = CONTINUOUS_SPAWN_INTERVAL
		_continuous_def = def
		_spawn_enemies(initial, def)
	else:
		_continuous_remaining = 0
		_spawn_enemies(count, def)

	if elite_extras > 0:
		_spawn_enemies(elite_extras, {
			"composition": [{"kind": "elite", "weight": 1.0}],
			"fog": def.get("fog", false),
		})

	wave_started.emit(_spawned.size() + _continuous_remaining, int(_current_modifier))


func _spawn_enemies(count: int, def: Dictionary) -> void:
	var spawn_points := _get_edge_spawn_points(count, bool(def.get("fog", false)))
	var night_stat_mult := BalanceConfig.get_enemy_night_stat_mult(_day_night.cycle_number)
	for i in spawn_points.size():
		var enemy: EnemyUnit = ENEMY_SCENE.instantiate()
		_units_container.add_child(enemy)
		enemy.global_position = spawn_points[i]
		enemy.set_ground_layer(_ground)
		enemy.reset_navigation()
		enemy.configure_kind(_pick_kind(def))
		_apply_night_stat_scaling(enemy, night_stat_mult)
		if _day_night.is_night():
			enemy.apply_cycle_visuals(true, true)
		_spawned.append(enemy)


func _apply_night_stat_scaling(enemy: EnemyUnit, mult: float) -> void:
	if mult <= 1.001:
		return
	enemy.max_hp = maxi(1, int(round(float(enemy.max_hp) * mult)))
	enemy.hp = enemy.max_hp
	enemy.attack_damage = maxi(1, int(round(float(enemy.attack_damage) * mult)))


func _pick_kind(def: Dictionary) -> String:
	var composition: Array = def.get("composition", [{"kind": "normal", "weight": 1.0}])
	var total := 0.0
	for entry in composition:
		total += float(entry.get("weight", 1.0))
	var roll := randf() * total
	var cursor := 0.0
	for entry in composition:
		cursor += float(entry.get("weight", 1.0))
		if roll <= cursor:
			return str(entry.get("kind", "normal"))
	return "normal"


func _get_wave_size() -> int:
	var military_count := 0
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit and (node as Unit).team_id == Team.PLAYER and not (node as Unit).is_civilian:
			military_count += 1
	# Exponential night climb; army pressure still adds a little pressure on top.
	var count := BalanceConfig.get_wave_base_count(_day_night.cycle_number)
	count += floori(float(military_count) / 3.0)
	return clampi(count, 4, BalanceConfig.WAVE_COUNT_CAP)


func _despawn_all() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()

	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()


func _get_edge_spawn_points(count: int, fog: bool) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var edge_cells := _ground.get_walkable_edge_cells()
	if edge_cells.is_empty():
		return points
	edge_cells.shuffle()
	var town_position := _ground.map_to_local(_ground.get_town_center_cell())
	var margin := FOG_EDGE_MARGIN if fog else EDGE_MARGIN

	var directions: Array[String] = [_attack_direction]
	if not _secondary_direction.is_empty():
		directions.append(_secondary_direction)

	var cells_by_dir: Dictionary = {}
	for direction in directions:
		cells_by_dir[direction] = _filter_directional_cells(edge_cells, town_position, direction)

	for i in count:
		var direction: String = directions[i % directions.size()]
		var directional_cells: Array = cells_by_dir.get(direction, edge_cells)
		if directional_cells.is_empty():
			directional_cells = edge_cells
		var edge_position := _ground.map_to_local(directional_cells[i % directional_cells.size()])
		var inward := edge_position.direction_to(town_position) * margin
		points.append(edge_position + inward)
	return points


func _filter_directional_cells(
	edge_cells: Array,
	town_position: Vector2,
	direction: String
) -> Array[Vector2i]:
	var directional_cells: Array[Vector2i] = []
	for cell in edge_cells:
		var offset := _ground.map_to_local(cell) - town_position
		var matches := (
			(direction == "Norte" and offset.y < 0.0 and absf(offset.y) >= absf(offset.x))
			or (direction == "Sur" and offset.y > 0.0 and absf(offset.y) >= absf(offset.x))
			or (direction == "Este" and offset.x > 0.0 and absf(offset.x) >= absf(offset.y))
			or (direction == "Oeste" and offset.x < 0.0 and absf(offset.x) >= absf(offset.y))
		)
		if matches:
			directional_cells.append(cell)
	return directional_cells
