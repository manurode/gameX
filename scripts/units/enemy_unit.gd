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
const RAID_PRIORITY_BUILDING_TYPES: Array[String] = [
	"mill",
	"lumber_camp",
	"mine",
	"town_center",
	"house_small",
	"house_big",
]

var enemy_kind: String = "normal"
var wall_damage_bonus: float = 1.0
var steals_resources: bool = false


func _ready() -> void:
	team_id = Team.ENEMY
	super._ready()
	remove_from_group("selectable_units")
	add_to_group("enemies")

	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night != null and day_night.has_method("is_night") and day_night.call("is_night"):
		apply_cycle_visuals(true)


func configure_kind(kind: String) -> void:
	enemy_kind = kind
	wall_damage_bonus = 1.0
	steals_resources = false
	scale = Vector2.ONE
	modulate = Color.WHITE

	match kind:
		"swarm":
			max_hp = 22
			hp = max_hp
			attack_damage = 4
			move_speed = 115.0
			attack_cooldown = 1.0
			scale = Vector2(0.78, 0.78)
			modulate = Color(0.75, 1.0, 0.7)
		"siege":
			max_hp = 140
			hp = max_hp
			attack_damage = 16
			move_speed = 48.0
			attack_cooldown = 1.5
			wall_damage_bonus = 2.5
			scale = Vector2(1.35, 1.35)
			modulate = Color(0.85, 0.7, 0.55)
		"elite":
			max_hp = 220
			hp = max_hp
			attack_damage = 24
			move_speed = 70.0
			attack_cooldown = 1.1
			scale = Vector2(1.55, 1.55)
			modulate = Color(1.0, 0.45, 0.45)
		"raider":
			max_hp = 50
			hp = max_hp
			attack_damage = 7
			move_speed = 100.0
			attack_cooldown = 1.0
			steals_resources = true
			modulate = Color(1.0, 0.85, 0.4)
		_:
			enemy_kind = "normal"
			max_hp = 40
			hp = max_hp
			attack_damage = 8
			move_speed = 80.0
			attack_cooldown = 1.2


func get_attack_damage() -> int:
	var base := super.get_attack_damage()
	if (
		attack_target_building != null
		and is_instance_valid(attack_target_building)
		and attack_target_building.building_type_id == "wall"
		and wall_damage_bonus > 1.0
	):
		return int(round(float(base) * wall_damage_bonus))
	return base


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
	var priorities := RAID_PRIORITY_BUILDING_TYPES if steals_resources else PRIORITY_BUILDING_TYPES

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
		var type_index := priorities.find(building.building_type_id)
		if type_index >= 0:
			priority_bonus = -300.0 - float(type_index) * 50.0
		if enemy_kind == "siege" and building.building_type_id == "wall":
			priority_bonus -= 200.0

		var score := distance + priority_bonus
		if score < best_score:
			best_score = score
			best_building = building

	return best_building


func notify_building_hit(building: Building) -> void:
	if not steals_resources or building == null:
		return
	if not BuildingDatabase.is_gather_building(building.building_type_id):
		return
	var resources := get_tree().get_first_node_in_group("resource_manager")
	if resources is ResourceManager:
		var stolen := {"wood": 0, "gold": 0, "food": 0}
		match BuildingDatabase.get_gather_type(building.building_type_id):
			"wood":
				stolen.wood = mini(4, (resources as ResourceManager).wood)
			"gold":
				stolen.gold = mini(3, (resources as ResourceManager).gold)
			"food":
				stolen.food = mini(3, (resources as ResourceManager).food)
		if stolen.wood > 0 or stolen.gold > 0 or stolen.food > 0:
			(resources as ResourceManager).spend(stolen)
