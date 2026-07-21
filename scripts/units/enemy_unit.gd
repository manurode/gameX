class_name EnemyUnit
extends Unit

const UNIT_AGGRO_RANGE := 180.0
const VISIBILITY_LINGER := 0.4
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

const KIND_VISUAL := {
	"ember": "ember",
	"mire": "mire",
	"hexwing": "hexwing",
}

var enemy_kind: String = "normal"
var wall_damage_bonus: float = 1.0
var steals_resources: bool = false
## Hexala prioritizes military units over buildings when no nearby threat.
var hunts_military: bool = false

var _player_visible: bool = true
var _visibility_linger: float = 0.0
var _visibility_check_timer: float = 0.0


func _ready() -> void:
	team_id = Team.ENEMY
	super._ready()
	remove_from_group("selectable_units")
	add_to_group("enemies")
	# Offset enemy scans so wave units do not all evaluate on the same tick.
	_scan_timer = randf() * TARGET_SCAN_INTERVAL
	_visibility_check_timer = randf() * TARGET_SCAN_INTERVAL

	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night != null and day_night.has_method("is_night") and day_night.call("is_night"):
		apply_cycle_visuals(true, true)
		# Hide immediately to avoid a one-frame flash before the first light check.
		if not _has_enemy_night_vision():
			_set_player_visible(false)
	call_deferred("_force_visibility_refresh")


func configure_kind(kind: String) -> void:
	enemy_kind = kind
	wall_damage_bonus = 1.0
	steals_resources = false
	hunts_military = false
	uses_fireball = false
	combat_style = CombatStyle.MELEE
	attack_range_min = 90.0
	attack_range_max = 210.0
	scale = Vector2.ONE
	modulate = Color.WHITE

	var visual_id := str(KIND_VISUAL.get(kind, "enemy"))
	UnitDatabase.apply_sheets_to_unit(self, visual_id)

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
		"ember":
			# Fast fragile fire imp — rushes units and burns through lines.
			max_hp = 28
			hp = max_hp
			attack_damage = 6
			move_speed = 130.0
			attack_cooldown = 0.85
			melee_range = 50.0
			scale = Vector2(0.85, 0.85)
		"mire":
			# Slow toad-golem tank — shreds walls and absorbs damage.
			max_hp = 160
			hp = max_hp
			attack_damage = 14
			move_speed = 42.0
			attack_cooldown = 1.6
			wall_damage_bonus = 2.2
			melee_range = 70.0
			scale = Vector2(1.4, 1.4)
		"hexwing":
			# Flying hex-bat — ranged fireball attacker that hunts military.
			max_hp = 50
			hp = max_hp
			attack_damage = 12
			move_speed = 105.0
			attack_cooldown = 1.35
			combat_style = CombatStyle.RANGED
			uses_fireball = true
			attack_range_min = 95.0
			attack_range_max = 230.0
			melee_range = 58.0
			hunts_military = true
			scale = Vector2(1.05, 1.05)
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


func apply_cycle_visuals(is_night: bool, instant: bool = false) -> void:
	super.apply_cycle_visuals(is_night, instant)
	_force_visibility_refresh()


func should_show_health_bar() -> bool:
	if not _player_visible:
		return false
	return super.should_show_health_bar()


func is_player_visible() -> bool:
	return _player_visible


func _die() -> void:
	_set_player_visible(true)
	super._die()


func _physics_process(delta: float) -> void:
	if not _is_dying and hp > 0 and garrisoned_building == null:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = TARGET_SCAN_INTERVAL
			_evaluate_combat_target()

	_update_player_visibility(delta)
	super._physics_process(delta)


func _force_visibility_refresh() -> void:
	_visibility_check_timer = 0.0
	_update_player_visibility(0.0)


func _update_player_visibility(delta: float) -> void:
	if _is_dying or hp <= 0:
		_set_player_visible(true)
		return

	var day_night := get_tree().get_first_node_in_group("day_night_manager") as DayNightManager
	if day_night == null or not day_night.is_night():
		_set_player_visible(true)
		return

	if _has_enemy_night_vision():
		_set_player_visible(true)
		return

	_visibility_check_timer -= delta
	if _visibility_check_timer <= 0.0:
		_visibility_check_timer = TARGET_SCAN_INTERVAL
		if _is_lit_by_allies():
			_visibility_linger = VISIBILITY_LINGER

	if _visibility_linger > 0.0:
		_visibility_linger = maxf(0.0, _visibility_linger - delta)
		_set_player_visible(true)
	else:
		_set_player_visible(false)


func _has_enemy_night_vision() -> bool:
	var boons := get_tree().get_first_node_in_group("run_boon_manager")
	return boons is RunBoonManager and (boons as RunBoonManager).has_enemy_night_vision()


func _is_lit_by_allies() -> bool:
	var origin := global_position
	for node in get_tree().get_nodes_in_group("selectable_units"):
		if not node is Unit:
			continue
		var ally := node as Unit
		if ally.team_id != Team.PLAYER or not ally.is_night_light_active():
			continue
		var radius := ally.get_night_light_radius()
		if radius <= 0.0:
			continue
		if origin.distance_squared_to(ally.get_night_light_origin()) <= radius * radius:
			return true

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER or not building.is_night_light_active():
			continue
		var radius := building.get_night_light_radius()
		if radius <= 0.0:
			continue
		if origin.distance_squared_to(building.get_night_light_origin()) <= radius * radius:
			return true

	return false


func _set_player_visible(visible: bool) -> void:
	if _player_visible == visible:
		return
	_player_visible = visible
	if animated_sprite != null:
		animated_sprite.visible = visible
	if shadow_sprite != null:
		shadow_sprite.visible = visible
	if _occlusion_silhouette != null:
		_occlusion_silhouette.set_active(visible)
	if health_bar != null and health_bar.has_method("notify_selection_changed"):
		health_bar.notify_selection_changed()


func _evaluate_combat_target() -> void:
	var aggro_range := _get_aggro_range()
	var nearby_player := _find_nearest_player_unit(aggro_range)
	if nearby_player != null:
		if attack_target != nearby_player:
			attack_target_unit(nearby_player)
		return

	if _has_valid_combat_target():
		return

	_acquire_target()


func _get_aggro_range() -> float:
	if combat_style == CombatStyle.RANGED:
		return maxf(UNIT_AGGRO_RANGE, attack_range_max)
	return UNIT_AGGRO_RANGE


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
	var nearby_player := _find_nearest_player_unit(_get_aggro_range())
	if nearby_player != null:
		attack_target_unit(nearby_player)
		return

	if hunts_military:
		var hunt_range := 420.0
		if combat_style == CombatStyle.RANGED:
			hunt_range = maxf(hunt_range, attack_range_max * 1.6)
		var military := _find_nearest_player_unit(hunt_range, true)
		if military != null:
			attack_target_unit(military)
			return

	var target_building := _find_best_player_building()
	if target_building != null:
		attack_target_building_node(target_building)


func _find_nearest_player_unit(max_range: float, military_only: bool = false) -> Unit:
	var best_unit: Unit = null
	var best_distance_sq := max_range * max_range
	var origin := global_position

	for item in UnitSpatialIndex.query_nearby(get_tree(), origin, max_range):
		if not item is Unit:
			continue
		var player_unit := item as Unit
		if player_unit.team_id != Team.PLAYER:
			continue
		if player_unit._is_dying or player_unit.hp <= 0:
			continue
		if player_unit.garrisoned_building != null:
			continue
		if military_only and player_unit.is_civilian:
			continue
		var distance_sq := origin.distance_squared_to(player_unit.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_unit = player_unit

	return best_unit


func _find_best_player_building() -> Building:
	var best_building: Building = null
	var best_score := INF
	var priorities := RAID_PRIORITY_BUILDING_TYPES if steals_resources else PRIORITY_BUILDING_TYPES
	var origin := global_position

	for node in get_tree().get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER or not building.can_be_damaged():
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue

		var distance := origin.distance_to(building.global_position)
		var priority_bonus := 0.0
		var type_index := priorities.find(building.building_type_id)
		if type_index >= 0:
			priority_bonus = -300.0 - float(type_index) * 50.0
		if (enemy_kind == "siege" or enemy_kind == "mire") and building.building_type_id == "wall":
			priority_bonus -= 200.0
		if enemy_kind == "hexwing" and building.building_type_id in ["barracks", "stable", "arcanum", "tower"]:
			priority_bonus -= 180.0

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
