class_name Building
extends StaticBody2D

enum BuildingState { CONSTRUCTING, ACTIVE, DESTROYED }

signal health_changed(current_hp: int, max_hp: int)
signal destroyed
signal construction_completed
signal garrison_changed
signal upgraded(new_level: int, weapon_type: String)

const HEALTH_BAR_VISIBLE_MS := 4000
const CONSTRUCTION_ALPHA := 0.55
const ENTRY_RANGE := 42.0
const GARRISON_ATTACK_RANGE := 220.0
const COLLISION_BODY_SHRINK := Vector2(0.82, 0.38)
const COLLISION_BODY_CENTER_Y := 0.62
const WALL_COLLISION_SHRINK := Vector2(0.94, 0.48)
const WALL_COLLISION_CENTER_Y := 0.42

@export var building_type_id: String = "house_small"
@export var team_id: int = Team.PLAYER

var hp: int = 0
var max_hp: int = 100
var building_state: BuildingState = BuildingState.ACTIVE
var construction_progress: float = 1.0
var build_time_total: float = 10.0
var garrison_capacity: int = 3
var garrison_attack_multiplier: float = 1.5
var garrison_weapon: String = "stone"
var upgrade_level: int = 0
var repair_in_progress: bool = false
var repair_paid: bool = false
var can_garrison: bool = true
var blocks_navigation: bool = true
var pick_half_size := Vector2(55.0, 50.0)
var sprite_offset := Vector2(0.0, -40.0)
var is_selected: bool = false

var garrisoned_units: Array[Unit] = []
var garrison_attack_target: Unit = null
var garrison_attack_target_building: Building = null
var _garrison_attack_cooldown: float = 0.0
var _last_damage_time: int = 0
var _definition: Dictionary = {}
var _footprint := Vector2(70.0, 45.0)
var _wall_vertical: bool = false
var _repair_start_hp: int = 0
var _repair_progress: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var damage_overlay: Sprite2D = $DamageOverlay
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var selection_indicator: Line2D = $SelectionIndicator
@onready var health_bar: Node2D = $HealthBar
@onready var progress_bar: Node2D = $ProgressBar


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("selectable_buildings")
	_apply_definition()
	_update_visual_damage()
	_update_construction_visual()
	_setup_selection_indicator()
	selection_indicator.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if building_state != BuildingState.ACTIVE:
		return
	if _definition.get("automatic_defense", false):
		_process_automatic_defense(delta)
	elif is_garrison_occupied():
		_process_garrison_combat(delta)


func configure(type_id: String, state: BuildingState = BuildingState.ACTIVE, progress: float = 1.0) -> void:
	building_type_id = type_id
	building_state = state
	construction_progress = progress
	_wall_vertical = false
	_apply_definition()
	_update_visual_damage()
	_update_construction_visual()


func set_wall_vertical(vertical: bool) -> void:
	if building_type_id != "wall":
		return
	_wall_vertical = vertical
	_apply_wall_orientation()


func _apply_definition() -> void:
	_definition = BuildingDatabase.get_definition(building_type_id)
	if _definition.is_empty():
		return

	max_hp = _definition.get("max_hp", 100)
	if building_state == BuildingState.ACTIVE:
		hp = max_hp
	elif building_state == BuildingState.CONSTRUCTING:
		hp = maxi(1, int(max_hp * 0.15))

	build_time_total = _definition.get("build_time", 10.0)
	garrison_capacity = _definition.get("garrison_capacity", 0)
	garrison_attack_multiplier = _definition.get("garrison_attack_multiplier", 1.0)
	garrison_weapon = _definition.get("garrison_weapon", "stone")
	can_garrison = _definition.get("can_garrison", true)
	blocks_navigation = _definition.get("blocks_nav", true)
	_footprint = _definition.get("footprint", Vector2(70.0, 45.0))
	pick_half_size = _definition.get("pick_half_size", Vector2(55.0, 50.0))
	_apply_upgrade_weapon()

	_setup_texture()
	_setup_collision()
	health_changed.emit(hp, max_hp)


func _setup_texture() -> void:
	if sprite == null:
		return

	if _definition.get("procedural", false):
		sprite.texture = WallTexture.get_texture()
		_apply_wall_orientation()
	else:
		var texture_path: String = _definition.get("texture", "")
		if not texture_path.is_empty():
			sprite.texture = load(texture_path)

	if sprite.texture != null:
		sprite.offset = Vector2(0.0, -sprite.texture.get_height() * 0.5 + 64.0)
		sprite_offset = sprite.offset
		sprite.modulate = _definition.get("tint", Color.WHITE)
		if damage_overlay != null:
			damage_overlay.texture = sprite.texture
			damage_overlay.offset = sprite.offset


func _apply_wall_orientation() -> void:
	if building_type_id != "wall" or sprite == null:
		return
	if _wall_vertical:
		sprite.rotation_degrees = 90.0
		_footprint = Vector2(30.0, 80.0)
		pick_half_size = Vector2(25.0, 50.0)
	else:
		sprite.rotation_degrees = 0.0
		_footprint = Vector2(80.0, 30.0)
		pick_half_size = Vector2(50.0, 25.0)
	if damage_overlay != null:
		damage_overlay.rotation_degrees = sprite.rotation_degrees
	_setup_collision()


func _wall_base_rotation() -> float:
	return 90.0 if _wall_vertical else 0.0


func _setup_collision() -> void:
	if collision_shape == null:
		return
	var shape := RectangleShape2D.new()
	var body_size := _get_collision_body_size()
	shape.size = body_size
	collision_shape.shape = shape
	collision_shape.position = get_collision_center() - global_position
	# Under construction: no physical collision so builders can reach the site
	set_collision_layer_value(1, building_state == BuildingState.ACTIVE)


func _get_collision_body_size() -> Vector2:
	if building_type_id == "wall":
		return Vector2(
			_footprint.x * WALL_COLLISION_SHRINK.x,
			_footprint.y * WALL_COLLISION_SHRINK.y
		)
	return Vector2(
		_footprint.x * COLLISION_BODY_SHRINK.x,
		_footprint.y * COLLISION_BODY_SHRINK.y
	)


func _get_collision_center_y_factor() -> float:
	if building_type_id == "wall":
		return WALL_COLLISION_CENTER_Y
	return COLLISION_BODY_CENTER_Y


func _apply_upgrade_weapon() -> void:
	var path: Array = BuildingDatabase.get_upgrade_path(building_type_id)
	if upgrade_level < path.size():
		var tier: Dictionary = path[upgrade_level]
		garrison_weapon = tier.get("weapon", garrison_weapon)


func get_weapon_stats() -> Dictionary:
	return BuildingDatabase.get_weapon_stats(garrison_weapon)


func is_garrison_occupied() -> bool:
	return get_garrison_count() > 0


func get_garrison_count() -> int:
	var count := 0
	for unit in garrisoned_units:
		if is_instance_valid(unit):
			count += 1
	return count


func get_garrison_combat_weight() -> float:
	var weight := 0.0
	for unit in garrisoned_units:
		if not is_instance_valid(unit) or unit._is_dying:
			continue
		if unit.can_attack:
			weight += BalanceConfig.GARRISON_SOLDIER_DAMAGE_WEIGHT
		elif unit.is_civilian:
			weight += BalanceConfig.GARRISON_CIVILIAN_DAMAGE_WEIGHT
	return weight


func get_garrison_attack_damage() -> int:
	var combat_weight := get_garrison_combat_weight()
	if combat_weight <= 0.0:
		return 0
	var weapon_stats: Dictionary = get_weapon_stats()
	var base: int = weapon_stats.get("damage", 4)
	return maxi(1, int(round(float(base) * garrison_attack_multiplier * combat_weight)))


func get_garrison_attack_range() -> float:
	var weapon_stats: Dictionary = get_weapon_stats()
	return weapon_stats.get("range_max", GARRISON_ATTACK_RANGE)


func order_garrison_attack_unit(target: Unit) -> void:
	if target == null or not is_instance_valid(target):
		return
	garrison_attack_target = target
	garrison_attack_target_building = null
	_garrison_attack_cooldown = 0.0
	_sync_garrison_unit_targets()


func order_garrison_attack_building(target: Building) -> void:
	if target == null or not is_instance_valid(target):
		return
	garrison_attack_target = null
	garrison_attack_target_building = target
	_garrison_attack_cooldown = 0.0
	_sync_garrison_unit_targets()


func clear_garrison_attack() -> void:
	garrison_attack_target = null
	garrison_attack_target_building = null
	_sync_garrison_unit_targets()


func _sync_garrison_unit_targets() -> void:
	for unit in garrisoned_units:
		if not is_instance_valid(unit):
			continue
		unit.attack_target = garrison_attack_target
		unit.attack_target_building = garrison_attack_target_building


func _process_garrison_combat(delta: float) -> void:
	_garrison_attack_cooldown = maxf(0.0, _garrison_attack_cooldown - delta)
	_validate_garrison_attack_targets()

	if garrison_attack_target == null and garrison_attack_target_building == null:
		return
	if not _is_garrison_in_attack_range():
		return
	if _garrison_attack_cooldown > 0.0:
		return

	var shooter := _get_garrison_shooter_unit()
	if shooter == null:
		return

	shooter.fire_garrison_shot()
	var weapon_stats: Dictionary = get_weapon_stats()
	var cooldown_mult: float = weapon_stats.get("cooldown_mult", 1.0)
	_garrison_attack_cooldown = maxf(0.45, _get_garrison_shooter_cooldown(shooter) * cooldown_mult)


func _process_automatic_defense(delta: float) -> void:
	_garrison_attack_cooldown = maxf(0.0, _garrison_attack_cooldown - delta)
	if _garrison_attack_cooldown > 0.0:
		return
	var nearest: Unit = null
	var nearest_distance := INF
	var attack_range := get_garrison_attack_range()
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Unit:
			continue
		var enemy := node as Unit
		if enemy._is_dying or enemy.hp <= 0:
			continue
		var distance := get_attack_point().distance_to(enemy.get_sprite_center())
		if distance <= attack_range and distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		return
	var weapon_stats := get_weapon_stats()
	nearest.take_damage(weapon_stats.get("damage", 14))
	CombatEffects.spawn_ranged_impact(get_parent(), nearest.get_sprite_center())
	_garrison_attack_cooldown = maxf(0.45, weapon_stats.get("cooldown_mult", 1.0))


func _validate_garrison_attack_targets() -> void:
	if garrison_attack_target != null and (
		not is_instance_valid(garrison_attack_target)
		or garrison_attack_target.hp <= 0
		or garrison_attack_target._is_dying
	):
		garrison_attack_target = null
		_sync_garrison_unit_targets()

	if garrison_attack_target_building != null and (
		not is_instance_valid(garrison_attack_target_building)
		or not garrison_attack_target_building.can_be_damaged()
	):
		garrison_attack_target_building = null
		_sync_garrison_unit_targets()


func _is_garrison_in_attack_range() -> bool:
	var origin := get_attack_point()
	var range_max := get_garrison_attack_range()

	if garrison_attack_target != null and is_instance_valid(garrison_attack_target):
		var dist := origin.distance_to(garrison_attack_target.get_sprite_center())
		return dist <= range_max

	if garrison_attack_target_building != null and is_instance_valid(garrison_attack_target_building):
		var dist := origin.distance_to(garrison_attack_target_building.get_attack_point())
		return dist <= range_max

	return false


func _get_garrison_shooter_unit() -> Unit:
	var civilian_shooter: Unit = null
	for unit in garrisoned_units:
		if not is_instance_valid(unit) or unit._is_dying:
			continue
		if unit.can_attack:
			return unit
		if unit.is_civilian and civilian_shooter == null:
			civilian_shooter = unit
	return civilian_shooter


func _get_garrison_shooter_cooldown(shooter: Unit) -> float:
	if shooter.is_civilian and not shooter.can_attack:
		return BalanceConfig.GARRISON_CIVILIAN_ATTACK_COOLDOWN
	return shooter.attack_cooldown


func has_enemy_garrison(unit: Unit) -> bool:
	for garrisoned in garrisoned_units:
		if is_instance_valid(garrisoned) and Team.are_hostile(garrisoned.team_id, unit.team_id):
			return true
	return false


func is_hostile_to(unit: Unit) -> bool:
	if unit == null:
		return false
	return Team.are_hostile(team_id, unit.team_id)


func can_be_damaged() -> bool:
	return building_state != BuildingState.DESTROYED and hp > 0


func can_be_upgraded() -> bool:
	return (
		building_state == BuildingState.ACTIVE
		and BuildingDatabase.can_upgrade(building_type_id, upgrade_level)
	)


func needs_repair() -> bool:
	return building_state == BuildingState.ACTIVE and hp < max_hp


func can_be_repaired() -> bool:
	return needs_repair() and team_id == Team.PLAYER


func get_repair_cost() -> Dictionary:
	return BuildingDatabase.get_repair_cost(building_type_id, hp, max_hp)


func get_repair_work_duration() -> float:
	if not needs_repair():
		return 0.0
	var missing_hp := max_hp - hp
	if repair_in_progress:
		missing_hp = max_hp - _repair_start_hp
	return build_time_total * (float(maxi(1, missing_hp)) / float(maxi(1, max_hp)))


func try_start_repair(resource_manager: ResourceManager) -> bool:
	if not can_be_repaired() or resource_manager == null:
		return false
	if repair_paid:
		return true

	var cost := get_repair_cost()
	if not resource_manager.can_afford(cost):
		return false
	if not resource_manager.spend(cost):
		return false

	repair_paid = true
	repair_in_progress = true
	_repair_start_hp = hp
	_repair_progress = 0.0
	return true


func add_repair_progress(amount: float) -> void:
	if not repair_in_progress or not needs_repair():
		return

	var missing_hp := max_hp - _repair_start_hp
	if missing_hp <= 0:
		_complete_repair()
		return

	_repair_progress = clampf(_repair_progress + amount, 0.0, 1.0)
	hp = _repair_start_hp + int(_repair_progress * float(missing_hp))
	hp = mini(hp, max_hp)
	health_changed.emit(hp, max_hp)
	_update_visual_damage()

	if _repair_progress >= 1.0 or hp >= max_hp:
		_complete_repair()


func _complete_repair() -> void:
	hp = max_hp
	repair_in_progress = false
	repair_paid = false
	_repair_start_hp = 0
	_repair_progress = 0.0
	health_changed.emit(hp, max_hp)
	_update_visual_damage()


func get_upgrade_cost() -> Dictionary:
	return BuildingDatabase.get_upgrade_cost(building_type_id, upgrade_level)


func try_upgrade(resource_manager: ResourceManager) -> bool:
	if not can_be_upgraded() or resource_manager == null:
		return false
	var cost := get_upgrade_cost()
	if not resource_manager.spend(cost):
		return false

	var path: Array = BuildingDatabase.get_upgrade_path(building_type_id)
	upgrade_level += 1
	if upgrade_level < path.size():
		var tier: Dictionary = path[upgrade_level]
		garrison_weapon = tier.get("weapon", garrison_weapon)
		var hp_bonus: int = tier.get("hp_bonus", 0)
		max_hp += hp_bonus
		hp = mini(hp + hp_bonus, max_hp)
		health_changed.emit(hp, max_hp)
		_update_visual_damage()

	upgraded.emit(upgrade_level, garrison_weapon)
	_apply_upgrade_visual()
	return true


func _apply_upgrade_visual() -> void:
	if sprite == null or building_state != BuildingState.ACTIVE:
		return
	match garrison_weapon:
		"crossbow":
			sprite.modulate = Color(1.05, 1.02, 0.95, 1.0)
		"ballista":
			sprite.modulate = Color(1.08, 1.05, 0.92, 1.0)
		_:
			sprite.modulate = Color.WHITE


func get_collision_center() -> Vector2:
	return global_position + Vector2(0.0, -_footprint.y * _get_collision_center_y_factor())


func get_collision_half_size() -> Vector2:
	return _get_collision_body_size() * 0.5


func get_approach_point(from_position: Vector2, margin: float = 2.0) -> Vector2:
	var center := get_collision_center()
	var direction := from_position.direction_to(center)
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	var reach := _reach_along_collision_rect(direction) + margin
	return center - direction * reach


func get_combat_approach_point(from_position: Vector2) -> Vector2:
	return get_approach_point(from_position, 0.0)


func get_entry_approach_point(from_position: Vector2) -> Vector2:
	return get_approach_point(from_position, 2.0)


func _reach_along_collision_rect(direction: Vector2) -> float:
	var half := get_collision_half_size()
	var abs_dir := direction.abs()
	if abs_dir.x < 0.001 and abs_dir.y < 0.001:
		return maxf(half.x, half.y)
	var tx := INF if abs_dir.x < 0.001 else half.x / abs_dir.x
	var ty := INF if abs_dir.y < 0.001 else half.y / abs_dir.y
	return minf(tx, ty)


func _setup_selection_indicator() -> void:
	if selection_indicator == null:
		return
	var points := PackedVector2Array()
	const SEGMENTS := 48
	var radius_x := pick_half_size.x * 0.85
	var radius_y := pick_half_size.y * 0.45
	for i in SEGMENTS + 1:
		var angle := float(i) / float(SEGMENTS) * TAU
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	selection_indicator.points = points
	selection_indicator.closed = true


func get_sprite_center() -> Vector2:
	return global_position + sprite_offset


func get_base_center() -> Vector2:
	return global_position + Vector2(0.0, -_footprint.y * 0.2)


func get_melee_attack_point() -> Vector2:
	return get_base_center()


func get_attack_point() -> Vector2:
	return get_sprite_center()


func get_selection_rect() -> Rect2:
	return Rect2(get_sprite_center() - pick_half_size, pick_half_size * 2.0)


func contains_world_point(world_point: Vector2) -> bool:
	return get_selection_rect().has_point(world_point)


func contains_command_point(world_point: Vector2) -> bool:
	var half := _footprint * 0.42
	var base_center := global_position + Vector2(0.0, -_footprint.y * 0.2)
	return Rect2(base_center - half, half * 2.0).has_point(world_point)


func should_show_health_bar() -> bool:
	if building_state == BuildingState.DESTROYED or hp <= 0:
		return false
	if building_state == BuildingState.CONSTRUCTING:
		return true
	if is_selected:
		return true
	if is_being_attacked():
		return true
	return Time.get_ticks_msec() - _last_damage_time < HEALTH_BAR_VISIBLE_MS


func is_being_attacked() -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Unit:
			var enemy := node as Unit
			if enemy.attack_target_building == self and enemy.hp > 0 and not enemy._is_dying:
				return true
	return false


func select() -> void:
	is_selected = true
	if selection_indicator != null:
		selection_indicator.visible = true


func deselect() -> void:
	is_selected = false
	if selection_indicator != null:
		selection_indicator.visible = false


func get_garrison_space() -> int:
	return maxi(0, garrison_capacity - garrisoned_units.size())


func can_enter_garrison(unit: Unit) -> bool:
	return (
		building_state == BuildingState.ACTIVE
		and can_garrison
		and get_garrison_space() > 0
		and unit != null
		and is_instance_valid(unit)
		and (unit.can_attack or unit.is_civilian)
		and not garrisoned_units.has(unit)
	)


func enter_garrison(unit: Unit) -> bool:
	if not can_enter_garrison(unit):
		return false
	garrisoned_units.append(unit)
	unit.on_entered_garrison(self)
	garrison_changed.emit()
	if team_id == Team.PLAYER and unit.team_id == Team.PLAYER:
		_select_for_player()
	return true


func _select_for_player() -> void:
	var selection_manager := get_node_or_null("/root/Main/GameWorld/SelectionManager")
	if selection_manager != null and selection_manager.has_method("select_building"):
		selection_manager.select_building(self)


func exit_garrison(unit: Unit) -> void:
	if not garrisoned_units.has(unit):
		return
	garrisoned_units.erase(unit)
	unit.on_exited_garrison(_find_exit_position())
	garrison_changed.emit()
	if garrisoned_units.is_empty():
		clear_garrison_attack()


func exit_all_garrison() -> void:
	var units := garrisoned_units.duplicate()
	for unit in units:
		if is_instance_valid(unit):
			exit_garrison(unit)


func _find_exit_position() -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2(_footprint.x * 0.8, 0.0),
		Vector2(-_footprint.x * 0.8, 0.0),
		Vector2(0.0, _footprint.y * 0.6),
		Vector2(0.0, -_footprint.y * 0.3),
	]
	for offset in offsets:
		var candidate := global_position + offset
		if _is_position_walkable(candidate):
			return candidate
	return global_position + Vector2(_footprint.x, 0.0)


func _is_position_walkable(world_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collision_mask = 1
	params.collide_with_bodies = true
	var hits := space_state.intersect_point(params, 8)
	return hits.is_empty()


func add_construction_progress(amount: float) -> void:
	if building_state != BuildingState.CONSTRUCTING:
		return
	construction_progress = clampf(construction_progress + amount, 0.0, 1.0)
	_update_construction_visual()
	if construction_progress >= 1.0:
		_complete_construction()


func get_display_name() -> String:
	return _definition.get("name", building_type_id)


func is_core_building() -> bool:
	return _definition.get("is_core", false) or building_type_id == "town_center"


func get_production_items() -> Array[String]:
	var produces: Array = _definition.get("produces", [])
	var result: Array[String] = []
	for item in produces:
		result.append(String(item))
	return result


func _complete_construction() -> void:
	building_state = BuildingState.ACTIVE
	hp = max_hp
	construction_progress = 1.0
	_setup_collision()
	_update_construction_visual()
	_update_visual_damage()
	health_changed.emit(hp, max_hp)
	construction_completed.emit()
	_notify_building_ready()
	_request_nav_rebuild()


func _notify_building_ready() -> void:
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_building_completed(self)
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		(population_manager as PopulationManager).recalculate_cap_from_buildings()
	var production_manager := get_tree().get_first_node_in_group("production_manager")
	if production_manager is ProductionManager:
		(production_manager as ProductionManager).register_producer(self)


func take_damage(amount: int, attacker: Unit = null) -> void:
	if not can_be_damaged():
		return
	if attacker != null and is_instance_valid(attacker):
		if not Team.are_hostile(team_id, attacker.team_id):
			return
		if attacker.garrisoned_building == self:
			return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_update_visual_damage()
	_play_hit_effect(attacker)
	_try_garrison_self_defense(attacker)

	if hp <= 0:
		_destroy()


func _try_garrison_self_defense(attacker: Unit) -> void:
	if team_id != Team.PLAYER:
		return
	if not is_garrison_occupied():
		return
	if attacker == null or not is_instance_valid(attacker) or attacker._is_dying or attacker.hp <= 0:
		return
	if not Team.are_hostile(team_id, attacker.team_id):
		return

	order_garrison_attack_unit(attacker)


func _play_hit_effect(attacker: Unit = null) -> void:
	var world := get_parent()
	if world == null:
		return
	var effect_position := get_sprite_center()
	if attacker != null and is_instance_valid(attacker) and attacker.combat_style == Unit.CombatStyle.RANGED:
		CombatEffects.spawn_ranged_impact(world, effect_position)
	else:
		CombatEffects.spawn_melee_impact(world, effect_position)


func _update_visual_damage() -> void:
	if sprite == null:
		return

	var ratio := 1.0 if max_hp <= 0 else float(hp) / float(max_hp)
	if building_state == BuildingState.CONSTRUCTING:
		sprite.modulate = Color(1.0, 1.0, 1.0, CONSTRUCTION_ALPHA)
		if damage_overlay != null:
			damage_overlay.visible = false
		return

	sprite.modulate = Color.WHITE
	if building_type_id == "wall":
		sprite.rotation_degrees = _wall_base_rotation()
		sprite.position = Vector2.ZERO
		if damage_overlay != null:
			damage_overlay.rotation_degrees = _wall_base_rotation()
		if ratio > 0.66:
			if damage_overlay != null:
				damage_overlay.visible = false
		elif ratio > 0.33:
			sprite.modulate = Color(0.82, 0.78, 0.74, 1.0)
			if damage_overlay != null:
				damage_overlay.visible = true
				damage_overlay.modulate = Color(0.3, 0.2, 0.15, 0.35)
		else:
			sprite.modulate = Color(0.62, 0.55, 0.5, 1.0)
			if damage_overlay != null:
				damage_overlay.visible = true
				damage_overlay.modulate = Color(0.2, 0.12, 0.1, 0.55)
		return
	if ratio > 0.66:
		sprite.rotation_degrees = 0.0
		sprite.position = Vector2.ZERO
		if damage_overlay != null:
			damage_overlay.visible = false
	elif ratio > 0.33:
		sprite.modulate = Color(0.82, 0.78, 0.74, 1.0)
		sprite.rotation_degrees = -2.5
		sprite.position = Vector2(2.0, 1.0)
		if damage_overlay != null:
			damage_overlay.visible = true
			damage_overlay.modulate = Color(0.3, 0.2, 0.15, 0.35)
	else:
		sprite.modulate = Color(0.62, 0.55, 0.5, 1.0)
		sprite.rotation_degrees = -5.0
		sprite.position = Vector2(4.0, 3.0)
		if damage_overlay != null:
			damage_overlay.visible = true
			damage_overlay.modulate = Color(0.2, 0.12, 0.1, 0.55)


func _update_construction_visual() -> void:
	if progress_bar != null:
		progress_bar.visible = building_state == BuildingState.CONSTRUCTING
		progress_bar.queue_redraw()
	if sprite == null or building_state != BuildingState.CONSTRUCTING:
		if sprite != null and building_state == BuildingState.ACTIVE:
			sprite.scale = Vector2.ONE
			sprite.modulate = Color.WHITE
		return

	var ratio := clampf(construction_progress, 0.0, 1.0)
	# Evolve from foundation scaffold to finished building
	var build_scale := lerpf(0.35, 1.0, ratio)
	sprite.scale = Vector2(build_scale, build_scale)
	var alpha := lerpf(0.45, 1.0, ratio)
	var warmth := lerpf(0.72, 1.0, ratio)
	sprite.modulate = Color(warmth, warmth * 0.95, warmth * 0.88, alpha)
	if building_type_id == "wall":
		sprite.rotation_degrees = _wall_base_rotation()
	else:
		sprite.rotation_degrees = lerpf(-3.0, 0.0, ratio)


func get_nav_block_outline() -> PackedVector2Array:
	if not blocks_navigation or building_state != BuildingState.ACTIVE:
		return PackedVector2Array()

	var center := get_collision_center()
	var half := get_collision_half_size()
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	])


func _destroy() -> void:
	building_state = BuildingState.DESTROYED
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_building_destroyed(self)
	var production_manager := get_tree().get_first_node_in_group("production_manager")
	if production_manager is ProductionManager:
		(production_manager as ProductionManager).unregister_producer(self)
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		(population_manager as PopulationManager).recalculate_cap_from_buildings()
	var units_to_kill := garrisoned_units.duplicate()
	garrisoned_units.clear()
	for unit in units_to_kill:
		if is_instance_valid(unit):
			unit.die_from_garrison_destruction()

	CombatEffects.spawn_death_burst(get_parent(), get_sprite_center())
	deselect()
	destroyed.emit()
	_request_nav_rebuild()

	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.8)
	await tween.finished
	queue_free()


func _request_nav_rebuild() -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("rebuild_navigation"):
		world.call_deferred("rebuild_navigation", self)
