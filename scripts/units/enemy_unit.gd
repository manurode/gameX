class_name EnemyUnit
extends Unit

const NightLightIndex = preload("res://scripts/game/night_light_index.gd")
const PlayerBuildingIndex = preload("res://scripts/game/player_building_index.gd")

const UNIT_AGGRO_RANGE := 180.0
const VISIBILITY_LINGER := 0.4
## Walk around fortifications when the real path is at most this × straight-line.
const DETOUR_RATIO_DEFAULT := 1.55
const DETOUR_RATIO_SIEGE := 1.28
## Absolute slack so short / open walls are walked around (straight through a
## muralla is tiny, the real walk around the end is not — don't treat that as
## "too expensive").
const DETOUR_MIN_SLACK := 220.0
## Abort an in-progress wall chop / squeeze into a packed hole within this range.
const GAP_ABORT_RANGE := 115.0
## Enemies closer than this to the hole count against its capacity.
const GAP_CROWD_RADIUS := 95.0
const GAP_CAPACITY_DEFAULT := 4
const GAP_CAPACITY_SIEGE_LANE := 2
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
## Non-wall raid / chase goal kept while chopping a muralla so we can repath.
var _assault_goal_building: Building = null

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
		apply_cycle_visuals(1.0, true)
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
		and attack_target_building.is_wall_segment()
		and wall_damage_bonus > 1.0
	):
		return int(round(float(base) * wall_damage_bonus))
	return base


func apply_cycle_visuals(light_factor: float = 0.0, instant: bool = false) -> void:
	super.apply_cycle_visuals(light_factor, instant)
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
	return NightLightIndex.is_position_lit(get_tree(), global_position)


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


func attack_target_building_node(target: Building) -> void:
	if (
		target != null
		and is_instance_valid(target)
		and not target.is_wall_segment()
	):
		_assault_goal_building = target
	super.attack_target_building_node(target)


func attack_target_unit(target: Unit) -> void:
	_assault_goal_building = null
	super.attack_target_unit(target)


func _evaluate_combat_target() -> void:
	_clear_open_gate_breach_target()

	var aggro_range := _get_aggro_range()
	var nearby_player := _find_nearest_player_unit(aggro_range)
	if nearby_player != null:
		var barrier := _find_breach_barrier_toward(nearby_player.global_position)
		if barrier != null:
			if attack_target_building != barrier:
				attack_target_building_node(barrier)
			return
		if _is_breaching_barrier():
			attack_target_unit(nearby_player)
			return
		if attack_target != nearby_player:
			attack_target_unit(nearby_player)
		return

	if _has_valid_combat_target():
		var goal := _get_breach_goal_position()
		if goal != Vector2.INF:
			var barrier := _find_breach_barrier_toward(goal)
			if barrier != null:
				if attack_target_building != barrier:
					attack_target_building_node(barrier)
				return
			if _is_breaching_barrier():
				_retarget_assault_goal()
				return
		elif _is_breaching_barrier():
			# Wall was picked as a primary goal (legacy / proximity). Force a real
			# raid target, then decide whether that still needs a breach.
			_acquire_target()
			var refreshed_goal := _get_breach_goal_position()
			if refreshed_goal != Vector2.INF:
				var barrier := _find_breach_barrier_toward(refreshed_goal)
				if barrier != null:
					attack_target_building_node(barrier)
			return
		return

	_acquire_target()
	var acquired_goal := _get_breach_goal_position()
	if acquired_goal != Vector2.INF:
		var barrier := _find_breach_barrier_toward(acquired_goal)
		if barrier != null:
			attack_target_building_node(barrier)


func _retarget_assault_goal() -> void:
	if (
		_assault_goal_building != null
		and is_instance_valid(_assault_goal_building)
		and _assault_goal_building.can_be_damaged()
	):
		attack_target_building_node(_assault_goal_building)
		return
	_assault_goal_building = null
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


func _clear_open_gate_breach_target() -> void:
	if (
		attack_target_building != null
		and is_instance_valid(attack_target_building)
		and attack_target_building.building_type_id == "gate"
		and attack_target_building.is_gate_open()
	):
		_set_attack_target_building(null)


## Untyped on purpose: a typed `Building` param crashes if the ref was freed
## before Godot can enter the function body.
func _is_breachable_barrier(building: Variant) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if not (building is Building):
		return false
	var b := building as Building
	if not b.can_be_damaged() or not b.is_wall_segment():
		return false
	if b.building_type_id == "gate" and b.is_gate_open():
		return false
	return true


func _is_breaching_barrier() -> bool:
	# Freed refs compare equal to null in GDScript, but still fail typed calls —
	# assign null explicitly to drop the dangling Object.
	if not is_instance_valid(attack_target_building):
		attack_target_building = null
		return false
	return _is_breachable_barrier(attack_target_building)


func _get_breach_goal_position() -> Vector2:
	if attack_target != null and is_instance_valid(attack_target):
		return attack_target.global_position
	if attack_target_building != null and is_instance_valid(attack_target_building):
		if not attack_target_building.is_wall_segment():
			_assault_goal_building = attack_target_building
			return attack_target_building.get_closest_surface_point(global_position)
	if (
		_assault_goal_building != null
		and is_instance_valid(_assault_goal_building)
		and _assault_goal_building.can_be_damaged()
	):
		return _assault_goal_building.get_closest_surface_point(global_position)
	_assault_goal_building = null
	return Vector2.INF


func _get_detour_ratio() -> float:
	if enemy_kind == "siege" or enemy_kind == "mire":
		return DETOUR_RATIO_SIEGE
	return DETOUR_RATIO_DEFAULT


func _get_gap_capacity() -> int:
	if enemy_kind == "siege" or enemy_kind == "mire":
		# Siege prefers opening its own lane instead of joining a packed hole.
		return GAP_CAPACITY_SIEGE_LANE
	return GAP_CAPACITY_DEFAULT


func _query_goal_path_metrics(goal: Vector2) -> Dictionary:
	var navigation_manager := _get_navigation_manager()
	if navigation_manager == null or not navigation_manager.has_method("query_path_metrics"):
		return {"reachable": false, "length": INF, "end": global_position, "path": PackedVector2Array()}
	return navigation_manager.call("query_path_metrics", global_position, goal)


func _is_detour_acceptable(metrics: Dictionary, goal: Vector2) -> bool:
	if not bool(metrics.get("reachable", false)):
		return false
	var path_length := float(metrics.get("length", INF))
	if not is_finite(path_length):
		return false
	var straight := global_position.distance_to(goal)
	var budget := maxf(straight * _get_detour_ratio(), straight + DETOUR_MIN_SLACK)
	return path_length <= budget


## Prefer the closed gate / muralla blocking the assault — but only when the
## real detour is too expensive, or when an existing hole is overcrowded.
func _find_breach_barrier_toward(goal: Vector2) -> Building:
	if _can_attack_through_walls():
		return null

	var local_barrier := _get_local_barrier_toward(goal)
	var currently_breaching := _is_breaching_barrier()
	if local_barrier == null and not currently_breaching:
		return null

	var metrics := _query_goal_path_metrics(goal)
	if bool(metrics.get("unknown", false)):
		# Path metrics were not affordable this frame. Hold the current plan and
		# decide on the next scan rather than committing on missing information.
		return attack_target_building if currently_breaching else null

	if not _is_detour_acceptable(metrics, goal):
		# No usable path around — open / keep a breach.
		if local_barrier != null:
			return local_barrier
		if currently_breaching:
			return attack_target_building
		return null

	# Path around / through is cheap enough. Do NOT smash just because a wall is
	# closer than the gap (that trapped units on open wall ends). Only open a
	# second lane when the existing hole is actually overcrowded.
	var path: PackedVector2Array = metrics.get("path", PackedVector2Array())
	var gap_point := _estimate_opening_point(path, goal)
	var dist_to_gap := global_position.distance_to(gap_point)
	var gap_full := _count_gap_users(gap_point) >= _get_gap_capacity()

	if not gap_full:
		return null

	# Packed hole but we are already at its mouth — keep funneling in.
	if dist_to_gap <= GAP_ABORT_RANGE:
		return null

	# Packed hole and we are standing on a muralla → carve another lane.
	var barrier_for_lane: Building = local_barrier
	if currently_breaching and _is_breachable_barrier(attack_target_building):
		barrier_for_lane = attack_target_building
	if barrier_for_lane == null:
		return null

	var wall_pt := barrier_for_lane.get_closest_surface_point(global_position)
	if global_position.distance_to(wall_pt) <= melee_range * 2.25:
		return barrier_for_lane

	return null


func _get_local_barrier_toward(goal: Vector2) -> Building:
	var ignore: Building = null
	if (
		attack_target_building != null
		and is_instance_valid(attack_target_building)
		and not attack_target_building.is_wall_segment()
	):
		ignore = attack_target_building
	elif (
		_assault_goal_building != null
		and is_instance_valid(_assault_goal_building)
	):
		ignore = _assault_goal_building

	# Prefer the muralla actually sitting on the line to the goal.
	var blocker := _get_blocking_wall_building(global_position, goal, ignore)
	if _is_breachable_barrier(blocker):
		return blocker

	# Bump assist only — do not grab a side wall that we can already walk past.
	var reach := melee_range * 1.15
	var nearby := _find_nearest_breachable_wall(reach)
	if nearby == null:
		return null
	var wall_pt := nearby.get_closest_surface_point(global_position)
	if (goal - global_position).dot(wall_pt - global_position) <= 0.0:
		return null
	return nearby


## Path point that skims nearest remaining muralla — proxy for the breach gap.
func _estimate_opening_point(path: PackedVector2Array, goal: Vector2) -> Vector2:
	if path.is_empty():
		return goal
	var early_index := mini(path.size() - 1, maxi(1, int(path.size() / 3.0)))
	var best_pt: Vector2 = path[early_index]
	var best_wall_dist := INF
	var limit := maxi(1, int(ceil(float(path.size()) * 0.85)))
	var step := maxi(1, int(ceil(float(limit) / 12.0)))
	var i := 0
	while i < limit:
		var point: Vector2 = path[i]
		var wall_dist := _distance_to_nearest_wall_surface(point)
		if wall_dist < best_wall_dist:
			best_wall_dist = wall_dist
			best_pt = point
		i += step
	# No fortification near the route (open field) — use an early waypoint.
	if best_wall_dist > 140.0:
		return path[early_index]
	return best_pt


func _distance_to_nearest_wall_surface(origin: Vector2) -> float:
	var best := INF
	for building in PlayerBuildingIndex.get_targets(get_tree()):
		if not _is_breachable_barrier(building):
			continue
		var surface := building.get_closest_surface_point(origin)
		var dist := origin.distance_to(surface)
		if dist < best:
			best = dist
	return best


func _count_gap_users(gap_point: Vector2) -> int:
	var count := 0
	for item in UnitSpatialIndex.query_nearby(get_tree(), gap_point, GAP_CROWD_RADIUS):
		if not item is EnemyUnit:
			continue
		var other := item as EnemyUnit
		if other == self or other.hp <= 0 or other._is_dying:
			continue
		# Units still chopping a distant muralla are opening other lanes.
		if other._is_breaching_barrier():
			continue
		count += 1
	return count


func _find_nearest_breachable_wall(max_range: float) -> Building:
	var best: Building = null
	var best_dist_sq := max_range * max_range
	var origin := global_position
	for building in PlayerBuildingIndex.get_targets(get_tree()):
		if not _is_breachable_barrier(building):
			continue
		var surface := building.get_closest_surface_point(origin)
		var dist_sq := origin.distance_squared_to(surface)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = building
	return best


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
		if not is_instance_valid(item) or not (item is Unit):
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

	for building in PlayerBuildingIndex.get_targets(get_tree()):
		if not is_instance_valid(building) or not building.can_be_damaged():
			continue
		# Murallas / puertas are never raid goals — only temporary breach targets.
		if building.is_wall_segment():
			continue

		var distance := origin.distance_to(building.global_position)
		var priority_bonus := 0.0
		var type_index := priorities.find(building.building_type_id)
		if type_index >= 0:
			priority_bonus = -300.0 - float(type_index) * 50.0
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
