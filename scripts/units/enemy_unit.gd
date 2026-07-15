class_name EnemyUnit
extends Unit

const UNIT_AGGRO_RANGE := 180.0
const PRIORITY_BUILDING_TYPES: Array[String] = [
	"town_center",
	"mill",
	"lumber_camp",
	"mine",
	"house_small",
	"house_big",
]

func _ready() -> void:
	team_id = Team.ENEMY
	super._ready()
	remove_from_group("selectable_units")
	add_to_group("enemies")

	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night != null and day_night.has_method("is_night") and day_night.call("is_night"):
		apply_cycle_visuals(true)


func _physics_process(delta: float) -> void:
	if not _is_dying and hp > 0 and garrisoned_building == null:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = TARGET_SCAN_INTERVAL
			_evaluate_combat_target()

	super._physics_process(delta)


func _evaluate_combat_target() -> void:
	var nearby_player := _find_nearest_player_unit(UNIT_AGGRO_RANGE)
	if nearby_player != null:
		if attack_target != nearby_player:
			attack_target_unit(nearby_player)
		return

	if _has_valid_combat_target():
		return

	_acquire_target()


func _has_valid_combat_target() -> bool:
	if attack_target != null and is_instance_valid(attack_target):
		if (
			attack_target.hp > 0
			and not attack_target._is_dying
			and attack_target.garrisoned_building == null
		):
			return true
		attack_target = null

	if attack_target_building != null and is_instance_valid(attack_target_building):
		if attack_target_building.can_be_damaged():
			return true
		attack_target_building = null

	return false


func _acquire_target() -> void:
	var nearby_player := _find_nearest_player_unit(UNIT_AGGRO_RANGE)
	if nearby_player != null:
		attack_target_unit(nearby_player)
		return

	var target_building := _find_best_player_building()
	if target_building != null:
		attack_target_building_node(target_building)


func _find_nearest_player_unit(max_range: float) -> Unit:
	var best_unit: Unit = null
	var best_distance := max_range

	for node in get_tree().get_nodes_in_group("selectable_units"):
		if not node is Unit:
			continue
		var player_unit := node as Unit
		if player_unit._is_dying or player_unit.hp <= 0:
			continue
		if player_unit.garrisoned_building != null:
			continue
		var distance := global_position.distance_to(player_unit.global_position)
		if distance < best_distance:
			best_distance = distance
			best_unit = player_unit

	return best_unit


func _find_best_player_building() -> Building:
	var best_building: Building = null
	var best_score := INF

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER or not building.can_be_damaged():
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue

		var distance := global_position.distance_to(building.global_position)
		var priority_bonus := 0.0
		var type_index := PRIORITY_BUILDING_TYPES.find(building.building_type_id)
		if type_index >= 0:
			priority_bonus = -300.0 - float(type_index) * 50.0

		var score := distance + priority_bonus
		if score < best_score:
			best_score = score
			best_building = building

	return best_building
