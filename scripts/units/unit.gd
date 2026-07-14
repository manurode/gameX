class_name Unit
extends CharacterBody2D

enum CombatStyle { MELEE, RANGED }
enum UnitState { IDLE, MOVING, CHASING, ATTACKING, CONSTRUCTING, REPAIRING, GARRISON_APPROACH, GATHERING, DEPOSITING, RECRUITING, DYING }
enum FormationType { COLUMN, LINE, WEDGE, DIAMOND }

signal health_changed(current_hp: int, max_hp: int)
signal died

const HEALTH_BAR_VISIBLE_MS := 3000
const ALLY_DEFEND_RADIUS := 450.0
const TARGET_SCAN_INTERVAL := 0.35
const PLAYER_AGGRO_RANGE := 300.0
const PERSONAL_SPACE_RADIUS := 28.0
const NAV_AGENT_RADIUS := 16.0
const STUCK_TIME_SECONDS := 0.35
const STUCK_MOVE_EPSILON_SQ := 2.0
const STUCK_REPATH_MAX := 8
const BLOCKED_SPEED_RATIO := 0.35
const TARGET_PROGRESS_MIN := 2.5
const OBSTACLE_PROBE_DISTANCE := 44.0
const REPATH_WAYPOINT_REACHED := 18.0
const MELEE_DAMAGE_FRAME := 5
const RANGED_DAMAGE_FRAME := 6
const DEATH_LINGER_SECONDS := 2.8
const HIT_FLASH_DURATION := 0.14
const DEATH_FRAME_COUNT := 3
const STONE_SCENE: PackedScene = preload("res://scenes/combat/stone.tscn")

@export var move_speed: float = 95.0
@export var max_hp: int = 100
@export var selection_half_size := Vector2(40.0, 40.0)
@export var idle_sheet: Texture2D
@export var walk_up_sheet: Texture2D
@export var walk_down_sheet: Texture2D
@export var attack_up_sheet: Texture2D
@export var attack_down_sheet: Texture2D
@export var gather_sheet: Texture2D
@export var death_up_sheet: Texture2D
@export var death_down_sheet: Texture2D
@export var sprite_offset := Vector2(0.0, -36.0)
@export var combat_style: CombatStyle = CombatStyle.MELEE
@export var can_attack: bool = true
@export var can_build: bool = false
@export var can_gather: bool = false
@export var is_civilian: bool = false
@export var unit_type_id: String = ""
@export var build_range: float = 58.0
@export var build_power: float = 1.0
@export var attack_damage: int = 15
@export var attack_cooldown: float = 1.1
@export var melee_range: float = 52.0
@export var attack_range_min: float = 90.0
@export var attack_range_max: float = 210.0
@export var team_id: int = Team.PLAYER

var hp: int
var is_selected: bool = false
var attack_target: Unit = null
var attack_target_building: Building = null
var garrisoned_building: Building = null
var garrison_approach_target: Building = null
var construction_target: Building = null
var repair_target: Building = null
var gather_target: ResourceNode = null
var gather_building: Building = null
var recruitment_building: Building = null
var recruitment_type_id: String = ""
var recruitment_squad_size: int = 1
var recruitment_squad_id: String = ""

var _ground_layer: TinyTilesMap
var _gather_timer: float = 0.0
const GATHER_TIME_AT_NODE := 2.5
var _was_on_water := false
var _unit_state: UnitState = UnitState.IDLE
var _attack_cooldown_remaining: float = 0.0
var _is_attack_animating: bool = false
var _damage_dealt_this_swing: bool = false
var _last_damage_time: int = 0
var _is_dying: bool = false
var _last_facing_direction := Vector2.DOWN
var _move_destination: Vector2
var _hit_flash_tween: Tween
var _stuck_timer := 0.0
var _stuck_check_position := Vector2.ZERO
var _nav_repath_attempts := 0
var _nav_repath_waypoint := Vector2.INF
var _scan_timer := 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var selection_indicator: Line2D = $SelectionIndicator
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var dust_particles: GPUParticles2D = $DustParticles
@onready var health_bar: Node2D = $HealthBar


func _ready() -> void:
	hp = max_hp
	add_to_group("selectable_units")
	add_to_group("units")
	_setup_sprite_frames()
	_setup_shadow()
	_setup_dust()
	_setup_selection_indicator()
	animated_sprite.offset = sprite_offset
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	await get_tree().physics_frame
	_setup_navigation_agent()


func set_ground_layer(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer


func is_enemy() -> bool:
	return team_id == Team.ENEMY


func is_hostile_to(other: Unit) -> bool:
	if other == null or other == self:
		return false
	return Team.are_hostile(team_id, other.team_id)


func apply_cycle_visuals(is_night: bool) -> void:
	if shadow_sprite == null:
		return
	shadow_sprite.modulate = Color(1, 1, 1, 0.65) if is_night else Color(1, 1, 1, 1)


func should_show_health_bar() -> bool:
	if hp <= 0:
		return false
	if is_selected:
		return true
	return Time.get_ticks_msec() - _last_damage_time < HEALTH_BAR_VISIBLE_MS


func _setup_sprite_frames() -> void:
	var frames := SpriteSheetUtils.build_character_frames(
		idle_sheet,
		walk_up_sheet,
		walk_down_sheet,
		attack_up_sheet,
		attack_down_sheet,
		death_up_sheet,
		death_down_sheet,
		80,
		6.0,
		10.0,
		12.0,
		7.0,
		DEATH_FRAME_COUNT if death_up_sheet != null or death_down_sheet != null else -1,
		gather_sheet,
		9.0
	)
	if frames.get_animation_names().is_empty():
		return
	animated_sprite.sprite_frames = frames
	animated_sprite.play(&"idle")


func rebuild_visuals() -> void:
	_setup_sprite_frames()
	health_changed.emit(hp, max_hp)


func is_busy() -> bool:
	return _unit_state in [
		UnitState.MOVING,
		UnitState.CONSTRUCTING,
		UnitState.REPAIRING,
		UnitState.GATHERING,
		UnitState.DEPOSITING,
		UnitState.RECRUITING,
		UnitState.CHASING,
		UnitState.ATTACKING,
	]


func clear_gather_job() -> void:
	gather_target = null
	gather_building = null
	_gather_timer = 0.0
	if _unit_state in [UnitState.GATHERING, UnitState.DEPOSITING]:
		_unit_state = UnitState.IDLE


func assign_gather_at_node(node: ResourceNode) -> void:
	if not can_gather or not is_instance_valid(node):
		return
	cancel_recruitment()
	if garrisoned_building != null:
		exit_garrison()
	attack_target = null
	attack_target_building = null
	construction_target = null
	repair_target = null
	gather_target = node
	gather_building = null
	recruitment_building = null
	_unit_state = UnitState.GATHERING
	_gather_timer = 0.0
	_is_attack_animating = false
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = node.get_work_position(global_position)


func assign_deposit_at_building(building: Building) -> void:
	if not is_instance_valid(building):
		return
	gather_building = building
	gather_target = null
	_unit_state = UnitState.DEPOSITING
	_gather_timer = 0.0
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = building.get_approach_point(global_position)


func begin_recruitment(
	building: Building,
	target_type_id: String,
	squad_size: int = 1,
	squad_id: String = ""
) -> void:
	if not is_civilian or not is_instance_valid(building):
		return
	clear_gather_job()
	release_construction()
	release_repair()
	attack_target = null
	attack_target_building = null
	recruitment_building = building
	recruitment_type_id = target_type_id
	recruitment_squad_size = squad_size
	recruitment_squad_id = squad_id
	_unit_state = UnitState.RECRUITING
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = building.get_approach_point(global_position)


func transform_to_unit_type(type_id: String) -> void:
	UnitDatabase.apply_definition_to_unit(self, type_id)
	is_civilian = false
	can_gather = false
	recruitment_building = null
	recruitment_type_id = ""
	_unit_state = UnitState.IDLE
	construction_target = null
	repair_target = null
	gather_target = null
	gather_building = null


func release_construction() -> void:
	construction_target = null
	if _unit_state == UnitState.CONSTRUCTING:
		_unit_state = UnitState.IDLE


func release_repair() -> void:
	repair_target = null
	if _unit_state == UnitState.REPAIRING:
		_unit_state = UnitState.IDLE


func _setup_shadow() -> void:
	var image := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 48:
			var dx := (x - 24.0) / 24.0
			var dy := (y - 8.0) / 8.0
			var dist := dx * dx + dy * dy
			if dist <= 1.0:
				var alpha := 0.3 * (1.0 - dist) * (1.0 - dist)
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	var texture := ImageTexture.create_from_image(image)
	shadow_sprite.texture = texture
	shadow_sprite.position = Vector2.ZERO
	shadow_sprite.y_sort_enabled = false
	shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow_sprite.modulate = Color(1, 1, 1, 1)


func _setup_dust() -> void:
	var size := 8
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x - center, y - center).length() / center
			if dist <= 1.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, (1.0 - dist) * 0.9))
	dust_particles.texture = ImageTexture.create_from_image(image)
	dust_particles.position = Vector2(0, -2)
	dust_particles.y_sort_enabled = false


func _setup_selection_indicator() -> void:
	var points := PackedVector2Array()
	const SEGMENTS := 48
	const RADIUS_X := 26.0
	const RADIUS_Y := 11.0
	for i in SEGMENTS + 1:
		var angle := float(i) / float(SEGMENTS) * TAU
		points.append(Vector2(cos(angle) * RADIUS_X, sin(angle) * RADIUS_Y))
	selection_indicator.points = points
	selection_indicator.closed = true
	selection_indicator.position = Vector2.ZERO
	selection_indicator.y_sort_enabled = false


func _setup_navigation_agent() -> void:
	navigation_agent.path_desired_distance = 8.0
	navigation_agent.target_desired_distance = PERSONAL_SPACE_RADIUS * 0.85
	navigation_agent.radius = NAV_AGENT_RADIUS
	navigation_agent.max_speed = move_speed
	navigation_agent.avoidance_enabled = false
	_stuck_check_position = global_position
	reset_navigation()


func reset_navigation() -> void:
	_move_destination = global_position
	navigation_agent.target_position = global_position
	velocity = Vector2.ZERO
	_unit_state = UnitState.IDLE
	_reset_navigation_recovery()


static func compute_formation_positions(
	center: Vector2,
	count: int,
	formation: FormationType = FormationType.WEDGE
) -> PackedVector2Array:
	if count <= 0:
		return PackedVector2Array()

	var spacing := PERSONAL_SPACE_RADIUS * 2.0
	match formation:
		FormationType.COLUMN:
			return _compute_column_positions(center, count, spacing)
		FormationType.LINE:
			return _compute_line_positions(center, count, spacing)
		FormationType.WEDGE:
			return _compute_wedge_positions(center, count, spacing)
		FormationType.DIAMOND:
			return _compute_diamond_positions(center, count, spacing)
		_:
			return _compute_wedge_positions(center, count, spacing)


static func _compute_column_positions(center: Vector2, count: int, spacing: float) -> PackedVector2Array:
	var positions := PackedVector2Array()
	for i in count:
		positions.append(center + Vector2(0.0, float(i) * spacing))
	return positions


static func _compute_line_positions(center: Vector2, count: int, spacing: float) -> PackedVector2Array:
	var positions := PackedVector2Array()
	for i in count:
		var offset := (float(i) - (float(count) - 1.0) / 2.0) * spacing
		positions.append(center + Vector2(offset, 0.0))
	return positions


static func _compute_wedge_positions(center: Vector2, count: int, spacing: float) -> PackedVector2Array:
	var positions := PackedVector2Array()
	positions.append(center)

	var assigned := 1
	var row := 1
	while assigned < count:
		var depth := float(row) * spacing
		var width := row + 1
		for col in width:
			if assigned >= count:
				break
			var lateral := (float(col) - float(width - 1) / 2.0) * spacing
			positions.append(center + Vector2(lateral, depth))
			assigned += 1
		row += 1

	return positions


static func _compute_diamond_positions(center: Vector2, count: int, spacing: float) -> PackedVector2Array:
	var positions := PackedVector2Array()
	positions.append(center)

	if count <= 1:
		return positions

	var offsets: Array[Vector2] = []
	var layer := 1
	while offsets.size() < count - 1:
		for x in range(-layer, layer + 1):
			offsets.append(Vector2(float(x), -float(layer)))
		for y in range(-layer + 1, layer):
			offsets.append(Vector2(float(layer), float(y)))
			offsets.append(Vector2(-float(layer), float(y)))
		for x in range(layer - 1, -layer, -1):
			offsets.append(Vector2(float(x), float(layer)))
		layer += 1

	for i in count - 1:
		positions.append(center + offsets[i] * spacing)

	return positions


static func assign_move_destinations(
	units: Array,
	center: Vector2,
	formation: FormationType = FormationType.WEDGE
) -> void:
	var valid_units: Array[Unit] = []
	for unit in units:
		if is_instance_valid(unit) and unit.garrisoned_building == null:
			valid_units.append(unit)

	if valid_units.is_empty():
		return

	var slots := compute_formation_positions(center, valid_units.size(), formation)

	valid_units.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)

	for i in valid_units.size():
		valid_units[i].move_to(slots[i])


func select() -> void:
	is_selected = true
	selection_indicator.visible = true


func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false


func get_sprite_center() -> Vector2:
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		return garrisoned_building.get_sprite_center()
	return global_position + sprite_offset


func get_selection_rect() -> Rect2:
	return Rect2(get_sprite_center() - selection_half_size, selection_half_size * 2.0)


func contains_world_point(world_point: Vector2) -> bool:
	if garrisoned_building != null:
		return false
	return get_selection_rect().has_point(world_point)


func intersects_world_rect(world_rect: Rect2) -> bool:
	if garrisoned_building != null:
		return false
	return world_rect.intersects(get_selection_rect(), true)


func move_to(target: Vector2) -> void:
	cancel_recruitment()
	if garrisoned_building != null:
		exit_garrison()
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_villager_manual_move(self)
	release_construction()
	release_repair()
	clear_gather_job()
	attack_target = null
	attack_target_building = null
	construction_target = null
	repair_target = null
	_unit_state = UnitState.MOVING
	_is_attack_animating = false
	_move_destination = target
	_reset_navigation_recovery()
	navigation_agent.target_desired_distance = PERSONAL_SPACE_RADIUS * 0.85
	navigation_agent.target_position = target


func attack_target_unit(target: Unit) -> void:
	if not can_attack or target == self or not is_instance_valid(target) or target.hp <= 0 or target._is_dying:
		if not garrisoned_building:
			move_to(target.global_position if is_instance_valid(target) else global_position)
		return
	cancel_recruitment()
	if not is_hostile_to(target):
		if not garrisoned_building:
			move_to(target.global_position)
		return

	garrison_approach_target = null
	attack_target_building = null
	construction_target = null
	repair_target = null
	attack_target = target
	_unit_state = UnitState.CHASING if garrisoned_building == null else UnitState.IDLE
	_is_attack_animating = false
	_reset_navigation_recovery()


func attack_target_building_node(target: Building) -> void:
	cancel_recruitment()
	if not can_attack or not is_instance_valid(target) or not target.can_be_damaged():
		if garrisoned_building == null and is_instance_valid(target):
			move_to(target.global_position)
		return

	garrison_approach_target = null
	attack_target = null
	construction_target = null
	repair_target = null
	attack_target_building = target
	_unit_state = UnitState.CHASING if garrisoned_building == null else UnitState.IDLE
	_is_attack_animating = false
	_reset_navigation_recovery()


func approach_garrison(building: Building) -> void:
	cancel_recruitment()
	if not is_instance_valid(building) or not building.can_enter_garrison(self):
		return
	if garrisoned_building != null:
		return

	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).release_unit_job(self)

	attack_target = null
	attack_target_building = null
	construction_target = null
	repair_target = null
	garrison_approach_target = building
	_unit_state = UnitState.GARRISON_APPROACH
	_is_attack_animating = false
	_reset_navigation_recovery()
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = building.get_entry_approach_point(global_position)


func assign_construction(site: Building) -> void:
	cancel_recruitment()
	release_repair()
	if not can_build or not is_instance_valid(site) or site.building_state != Building.BuildingState.CONSTRUCTING:
		return
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).release_unit_job(self)
	if garrisoned_building != null:
		exit_garrison()
	attack_target = null
	attack_target_building = null
	construction_target = site
	_unit_state = UnitState.CONSTRUCTING
	_is_attack_animating = false
	_reset_navigation_recovery()
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = site.get_approach_point(global_position)


func assign_repair(target: Building) -> void:
	cancel_recruitment()
	release_construction()
	if not can_build or not is_instance_valid(target) or not target.can_be_repaired():
		return
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).release_unit_job(self)
	if garrisoned_building != null:
		exit_garrison()
	attack_target = null
	attack_target_building = null
	construction_target = null
	repair_target = target
	_unit_state = UnitState.REPAIRING
	_is_attack_animating = false
	_reset_navigation_recovery()
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = target.get_approach_point(global_position)


func enter_garrison(building: Building) -> void:
	if not is_instance_valid(building) or not building.enter_garrison(self):
		return
	garrison_approach_target = null


func exit_garrison() -> void:
	if garrisoned_building == null or not is_instance_valid(garrisoned_building):
		garrisoned_building = null
		return
	garrisoned_building.exit_garrison(self)


func on_entered_garrison(building: Building) -> void:
	garrisoned_building = building
	garrison_approach_target = null
	construction_target = null
	repair_target = null
	_unit_state = UnitState.IDLE
	_is_attack_animating = false
	velocity = Vector2.ZERO
	global_position = building.global_position
	navigation_agent.target_position = global_position
	animated_sprite.visible = false
	shadow_sprite.visible = false
	set_collision_layer_value(2, false)
	remove_from_group("selectable_units")
	deselect()
	_remove_from_selection()
	attack_target = building.garrison_attack_target
	attack_target_building = building.garrison_attack_target_building


func on_exited_garrison(exit_position: Vector2) -> void:
	garrisoned_building = null
	garrison_approach_target = null
	global_position = exit_position
	navigation_agent.target_position = exit_position
	animated_sprite.visible = true
	shadow_sprite.visible = true
	set_collision_layer_value(2, true)
	add_to_group("selectable_units")
	_unit_state = UnitState.IDLE
	_play_idle()


func die_from_garrison_destruction() -> void:
	garrisoned_building = null
	_die()


func get_attack_damage() -> int:
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		return garrisoned_building.get_garrison_attack_damage()
	return attack_damage


func fire_garrison_shot() -> void:
	if garrisoned_building == null or not is_instance_valid(garrisoned_building):
		return

	var building := garrisoned_building
	if building.garrison_attack_target != null and is_instance_valid(building.garrison_attack_target):
		if building.garrison_attack_target.hp <= 0 or building.garrison_attack_target._is_dying:
			return
		if not is_hostile_to(building.garrison_attack_target):
			return
		_fire_garrison_projectile_at_unit(building.garrison_attack_target)
		return

	if building.garrison_attack_target_building != null and is_instance_valid(building.garrison_attack_target_building):
		if not building.garrison_attack_target_building.can_be_damaged():
			return
		_fire_garrison_projectile_at_building(building.garrison_attack_target_building)


func _get_combat_world() -> Node:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null:
		return world
	var parent := get_parent()
	if parent != null and parent.get_parent() != null:
		return parent.get_parent()
	return get_tree().current_scene


func take_damage(amount: int, attacker: Unit = null) -> void:
	if _is_dying or hp <= 0:
		return
	if attacker != null and is_instance_valid(attacker) and not is_hostile_to(attacker):
		return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_play_hit_reaction(attacker)

	if hp <= 0:
		_die()
		return

	_handle_auto_defense(attacker)


func _handle_auto_defense(attacker: Unit) -> void:
	if team_id != Team.PLAYER:
		return
	if attacker == null or not is_instance_valid(attacker) or attacker._is_dying or attacker.hp <= 0:
		return
	if not is_hostile_to(attacker):
		return

	_try_self_defense(attacker)
	_alert_nearby_allies(attacker)


func _try_self_defense(attacker: Unit) -> void:
	if not can_attack or garrisoned_building != null:
		return
	attack_target_unit(attacker)


func _get_action_area_radius() -> float:
	match combat_style:
		CombatStyle.RANGED:
			return attack_range_max
		_:
			return maxf(melee_range, PLAYER_AGGRO_RANGE)


func _can_auto_attack_nearby_enemies() -> bool:
	if team_id != Team.PLAYER or not can_attack:
		return false
	if garrisoned_building != null or _is_dying or hp <= 0:
		return false
	if attack_target != null or attack_target_building != null:
		return false
	if construction_target != null or garrison_approach_target != null or repair_target != null:
		return false
	if gather_target != null or gather_building != null:
		return false
	if recruitment_building != null:
		return false
	if _unit_state == UnitState.MOVING:
		return false
	return true


func _evaluate_nearby_enemies() -> void:
	if not _can_auto_attack_nearby_enemies():
		return

	var nearby := _find_nearest_hostile_unit(_get_action_area_radius())
	if nearby != null:
		attack_target_unit(nearby)


func _find_nearest_hostile_unit(max_range: float) -> Unit:
	var best_unit: Unit = null
	var best_distance := max_range

	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Unit:
			continue

		var enemy := node as Unit
		if enemy._is_dying or enemy.hp <= 0:
			continue
		if not is_hostile_to(enemy):
			continue

		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best_unit = enemy

	return best_unit


func _can_help_defend_ally() -> bool:
	if not can_attack or garrisoned_building != null or _is_dying or hp <= 0:
		return false
	if attack_target != null or attack_target_building != null:
		return false
	if construction_target != null or garrison_approach_target != null or repair_target != null:
		return false
	if _unit_state == UnitState.MOVING:
		return false
	return true


func _alert_nearby_allies(attacker: Unit) -> void:
	var radius_sq := ALLY_DEFEND_RADIUS * ALLY_DEFEND_RADIUS
	var victim_pos := global_position

	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not node is Unit:
			continue

		var ally := node as Unit
		if ally.team_id != team_id:
			continue
		if ally.global_position.distance_squared_to(victim_pos) > radius_sq:
			continue
		if not ally._can_help_defend_ally():
			continue

		ally.attack_target_unit(attacker)


func _play_hit_reaction(attacker: Unit = null) -> void:
	_flash_hit()

	var world := get_parent().get_parent()
	var effect_position := get_sprite_center()
	if attacker != null and is_instance_valid(attacker) and attacker.combat_style == CombatStyle.RANGED:
		CombatEffects.spawn_ranged_impact(world, effect_position)
	else:
		CombatEffects.spawn_melee_impact(world, effect_position)


func _flash_hit() -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()

	animated_sprite.modulate = Color(1.6, 0.45, 0.45)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, HIT_FLASH_DURATION)


func _die() -> void:
	if _is_dying:
		return

	cancel_recruitment()
	_is_dying = true
	attack_target = null
	_unit_state = UnitState.DYING
	_is_attack_animating = false
	velocity = Vector2.ZERO
	deselect()
	died.emit()
	_remove_from_selection()
	remove_from_group("selectable_units")
	set_collision_layer_value(2, false)
	navigation_agent.target_position = global_position

	_play_death_sequence()


func _play_death_sequence() -> void:
	var world := get_parent().get_parent()
	CombatEffects.spawn_death_burst(world, get_sprite_center())
	_play_death_animation()

	await get_tree().create_timer(DEATH_LINGER_SECONDS).timeout

	var fade_tween := create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.65)
	fade_tween.tween_property(shadow_sprite, "modulate:a", 0.0, 0.65)
	await fade_tween.finished
	queue_free()


func _play_death_animation() -> void:
	var animation_name := _get_death_animation_name()
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
		return

	_play_procedural_death_fall()


func _get_death_animation_name() -> StringName:
	if _last_facing_direction.y < -0.15 and animated_sprite.sprite_frames.has_animation(&"death_up"):
		return &"death_up"
	if animated_sprite.sprite_frames.has_animation(&"death_down"):
		return &"death_down"
	if animated_sprite.sprite_frames.has_animation(&"death_up"):
		return &"death_up"
	return &"death_down"


func _play_procedural_death_fall() -> void:
	var fall_tween := create_tween()
	fall_tween.set_parallel(true)
	fall_tween.tween_property(animated_sprite, "rotation_degrees", 90.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall_tween.tween_property(animated_sprite, "position:y", sprite_offset.y + 20.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall_tween.tween_property(animated_sprite, "modulate", Color(0.7, 0.7, 0.7, 0.9), 0.5)


func _remove_from_selection() -> void:
	var selection_manager := get_node_or_null("/root/Main/GameWorld/SelectionManager")
	if selection_manager != null and selection_manager.has_method("remove_unit_from_selection"):
		selection_manager.remove_unit_from_selection(self)


func _physics_process(delta: float) -> void:
	if _is_dying or hp <= 0:
		return

	if team_id == Team.PLAYER and can_attack and garrisoned_building == null:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = TARGET_SCAN_INTERVAL
			_evaluate_nearby_enemies()

	if garrisoned_building != null:
		_process_garrisoned_combat(delta)
		return

	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	if attack_target != null and (not is_instance_valid(attack_target) or attack_target.hp <= 0 or attack_target._is_dying):
		attack_target = null
		_unit_state = UnitState.IDLE
		_is_attack_animating = false

	if attack_target_building != null and (
		not is_instance_valid(attack_target_building)
		or not attack_target_building.can_be_damaged()
	):
		attack_target_building = null
		_unit_state = UnitState.IDLE
		_is_attack_animating = false

	if construction_target != null and (
		not is_instance_valid(construction_target)
		or construction_target.building_state != Building.BuildingState.CONSTRUCTING
	):
		construction_target = null
		if _unit_state == UnitState.CONSTRUCTING:
			_unit_state = UnitState.IDLE

	if repair_target != null and (
		not is_instance_valid(repair_target)
		or not repair_target.can_be_repaired()
	):
		repair_target = null
		if _unit_state == UnitState.REPAIRING:
			_unit_state = UnitState.IDLE

	if garrison_approach_target != null and (
		not is_instance_valid(garrison_approach_target)
		or not garrison_approach_target.can_enter_garrison(self)
	):
		garrison_approach_target = null
		if _unit_state == UnitState.GARRISON_APPROACH:
			_unit_state = UnitState.IDLE

	if _unit_state == UnitState.GARRISON_APPROACH:
		_process_garrison_approach(delta)
		return

	if _unit_state == UnitState.RECRUITING and recruitment_building != null:
		_process_recruitment(delta)
		return

	if _unit_state == UnitState.GATHERING and gather_target != null:
		_process_gathering(delta)
		return

	if _unit_state == UnitState.DEPOSITING and gather_building != null:
		_process_depositing(delta)
		return

	if _unit_state == UnitState.CONSTRUCTING and construction_target != null:
		_process_construction(delta)
		return

	if _unit_state == UnitState.REPAIRING and repair_target != null:
		_process_repair(delta)
		return

	if _unit_state == UnitState.ATTACKING or _is_attack_animating:
		velocity = Vector2.ZERO
		_update_terrain_feedback(delta)
		return

	if attack_target != null or attack_target_building != null:
		_process_combat(delta)
		return

	if _should_stop_move_order():
		velocity = Vector2.ZERO
		_unit_state = UnitState.IDLE
		navigation_agent.target_position = global_position
		_play_idle()
		_update_terrain_feedback(delta)
		var job_manager := get_tree().get_first_node_in_group("job_manager")
		if job_manager is JobManager:
			(job_manager as JobManager).on_villager_move_completed(self)
		return

	if _unit_state != UnitState.MOVING:
		velocity = Vector2.ZERO
		_play_idle()
		_update_terrain_feedback(delta)
		return

	_unit_state = UnitState.MOVING
	_follow_navigation_toward(_move_destination, PERSONAL_SPACE_RADIUS * 0.85, delta)
	_update_terrain_feedback(delta)


func _reset_navigation_recovery() -> void:
	_reset_stuck_tracking()
	_nav_repath_attempts = 0
	_nav_repath_waypoint = Vector2.INF


func _reset_stuck_tracking(target: Vector2 = Vector2.INF) -> void:
	_stuck_timer = 0.0
	_stuck_check_position = global_position


func _is_stuck_moving(delta: float, target: Vector2) -> bool:
	var progress := _stuck_check_position.distance_to(target) - global_position.distance_to(target)
	var moved_sq := global_position.distance_squared_to(_stuck_check_position)

	if moved_sq > STUCK_MOVE_EPSILON_SQ and progress > TARGET_PROGRESS_MIN:
		_reset_stuck_tracking(target)
		return false

	_stuck_timer += delta
	return _stuck_timer >= STUCK_TIME_SECONDS


func _sync_navigation_target(target: Vector2) -> void:
	if _nav_repath_waypoint != Vector2.INF:
		if global_position.distance_to(_nav_repath_waypoint) > REPATH_WAYPOINT_REACHED:
			if navigation_agent.target_position.distance_squared_to(_nav_repath_waypoint) > 4.0:
				navigation_agent.target_position = _nav_repath_waypoint
			return
		_nav_repath_waypoint = Vector2.INF
		_nav_repath_attempts = 0

	if navigation_agent.target_position.distance_squared_to(target) > 4.0:
		navigation_agent.target_position = target


func _force_navigation_repath(target: Vector2) -> void:
	_nav_repath_attempts += 1
	_reset_stuck_tracking(target)

	var repath_target := target
	if _nav_repath_attempts > 1:
		repath_target = _get_stuck_repath_waypoint(target)

	var map_rid := navigation_agent.get_navigation_map()
	if map_rid.is_valid():
		repath_target = NavigationServer2D.map_get_closest_point(map_rid, repath_target)

	_nav_repath_waypoint = repath_target
	navigation_agent.target_position = global_position
	navigation_agent.target_position = repath_target


func _get_stuck_repath_waypoint(target: Vector2) -> Vector2:
	var to_target := global_position.direction_to(target)
	if to_target == Vector2.ZERO:
		to_target = Vector2.DOWN
	var side := Vector2(-to_target.y, to_target.x)
	var side_sign := 1.0 if _nav_repath_attempts % 2 == 0 else -1.0
	var offset_dist := 40.0 + float(_nav_repath_attempts) * 28.0
	return global_position + side * offset_dist * side_sign


func _move_with_obstacle_avoidance(preferred_direction: Vector2, target: Vector2, delta: float) -> bool:
	if preferred_direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return false

	var speed := _get_effective_move_speed()
	var before := global_position
	var dist_before := before.distance_to(target)

	velocity = preferred_direction.normalized() * speed
	move_and_slide()

	var moved := global_position.distance_to(before)
	var progress := dist_before - global_position.distance_to(target)
	if _did_move_well(moved, progress, speed, delta):
		_reset_stuck_tracking(target)
		_play_walk_animation(preferred_direction)
		return true

	var recovery := _get_obstacle_recovery_direction(preferred_direction, target)
	if recovery != Vector2.ZERO and recovery.angle_to(preferred_direction) > 0.05:
		var before_recovery := global_position
		var dist_before_recovery := before_recovery.distance_to(target)
		velocity = recovery * speed
		move_and_slide()
		moved = global_position.distance_to(before_recovery)
		progress = dist_before_recovery - global_position.distance_to(target)
		if _did_move_well(moved, progress, speed, delta):
			_reset_stuck_tracking(target)
			_play_walk_animation(recovery)
			return true

	return false


func _did_move_well(moved: float, progress: float, speed: float, delta: float) -> bool:
	return moved >= speed * delta * BLOCKED_SPEED_RATIO and progress >= TARGET_PROGRESS_MIN * delta


func _get_obstacle_recovery_direction(preferred_direction: Vector2, target: Vector2) -> Vector2:
	var wall_normal := _get_blocking_collision_normal()
	if wall_normal != Vector2.ZERO:
		var tangent_a := Vector2(-wall_normal.y, wall_normal.x)
		var tangent_b := -tangent_a
		var to_target := global_position.direction_to(target)
		if to_target == Vector2.ZERO:
			return tangent_a
		return tangent_a if tangent_a.dot(to_target) >= tangent_b.dot(to_target) else tangent_b

	return _probe_avoidance_direction(preferred_direction, target)


func _get_blocking_collision_normal() -> Vector2:
	var combined := Vector2.ZERO
	for i in get_slide_collision_count():
		combined += get_slide_collision(i).get_normal()
	if combined.length_squared() < 0.001:
		return Vector2.ZERO
	return combined.normalized()


func _probe_avoidance_direction(preferred_direction: Vector2, target: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var origin := global_position
	var to_target := origin.direction_to(target)
	if to_target == Vector2.ZERO:
		to_target = preferred_direction
	var base_angle := preferred_direction.angle()
	var best_dir := Vector2.ZERO
	var best_score := -INF

	for offset_deg in [0.0, 40.0, -40.0, 75.0, -75.0, 110.0, -110.0, 145.0, -145.0]:
		var dir := Vector2.from_angle(base_angle + deg_to_rad(offset_deg))
		if _is_direction_blocked(dir, space_state, origin):
			continue
		var score := dir.dot(to_target)
		if score > best_score:
			best_score = score
			best_dir = dir

	return best_dir if best_dir != Vector2.ZERO else preferred_direction


func _is_direction_blocked(direction: Vector2, space_state: PhysicsDirectSpaceState2D, origin: Vector2) -> bool:
	var params := PhysicsRayQueryParameters2D.create(
		origin,
		origin + direction.normalized() * OBSTACLE_PROBE_DISTANCE,
		collision_mask
	)
	params.exclude = [get_rid()]
	return not space_state.intersect_ray(params).is_empty()


func _follow_navigation_toward(target: Vector2, desired_distance: float, delta: float) -> void:
	var remaining := global_position.distance_to(target)
	if remaining <= desired_distance:
		velocity = Vector2.ZERO
		_reset_stuck_tracking(target)
		_nav_repath_waypoint = Vector2.INF
		_play_idle()
		return

	navigation_agent.target_desired_distance = desired_distance
	_sync_navigation_target(target)

	var direction := _get_navigation_direction(target)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		_play_idle()
		return

	if _move_with_obstacle_avoidance(direction, target, delta):
		return

	if _is_stuck_moving(delta, target):
		if _nav_repath_attempts < STUCK_REPATH_MAX:
			_force_navigation_repath(target)
		else:
			var recovery := _probe_avoidance_direction(direction, target)
			_move_with_obstacle_avoidance(recovery, target, delta)
			_reset_navigation_recovery()
		_play_idle()
	else:
		_play_idle()


func _get_navigation_direction(target: Vector2) -> Vector2:
	if not navigation_agent.is_navigation_finished():
		var next_position := navigation_agent.get_next_path_position()
		if next_position.distance_squared_to(global_position) > 4.0:
			return global_position.direction_to(next_position)

	var map_rid := navigation_agent.get_navigation_map()
	if map_rid.is_valid():
		var reachable := NavigationServer2D.map_get_closest_point(map_rid, target)
		if reachable.distance_squared_to(global_position) > 4.0:
			return global_position.direction_to(reachable)

	if global_position.distance_squared_to(target) > 4.0:
		return global_position.direction_to(target)

	return Vector2.ZERO


func _process_combat(_delta: float) -> void:
	_unit_state = UnitState.CHASING

	if _is_in_attack_range():
		if _attack_cooldown_remaining <= 0.0:
			_start_attack()
		else:
			velocity = Vector2.ZERO
			_play_idle_facing_target()
		_update_terrain_feedback(_delta)
		return

	# Melee vs unit: direct chase (no terrain blocking between open units).
	if combat_style == CombatStyle.MELEE and attack_target != null and is_instance_valid(attack_target):
		_chase_melee_unit_direct(_delta)
		_update_terrain_feedback(_delta)
		return

	var chase_target := _get_chase_navigation_target()
	var desired_distance := _get_chase_desired_distance()
	_follow_navigation_toward(chase_target, desired_distance, _delta)
	_update_terrain_feedback(_delta)


func _chase_melee_unit_direct(delta: float) -> void:
	var target_point := attack_target.get_sprite_center()
	var direction := global_position.direction_to(target_point)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		_play_idle()
		return

	if _move_with_obstacle_avoidance(direction, target_point, delta):
		return

	if _is_stuck_moving(delta, target_point):
		if _nav_repath_attempts < STUCK_REPATH_MAX:
			_force_navigation_repath(target_point)
		else:
			var recovery := _probe_avoidance_direction(direction, target_point)
			_move_with_obstacle_avoidance(recovery, target_point, delta)
			_reset_navigation_recovery()
		_play_idle()
	else:
		_play_idle()


func _get_chase_navigation_target() -> Vector2:
	if attack_target != null and is_instance_valid(attack_target):
		if combat_style == CombatStyle.MELEE:
			return attack_target.get_sprite_center()
		return _get_chase_standoff_point()

	if attack_target_building != null and is_instance_valid(attack_target_building):
		return _get_chase_standoff_point()

	return global_position


func _get_chase_desired_distance() -> float:
	if attack_target != null and is_instance_valid(attack_target):
		return 2.0 if combat_style == CombatStyle.MELEE else 4.0
	if attack_target_building != null:
		return 2.0
	return 4.0


func _get_melee_combat_distance() -> float:
	if attack_target != null and is_instance_valid(attack_target):
		return get_sprite_center().distance_to(attack_target.get_sprite_center())
	if attack_target_building != null and is_instance_valid(attack_target_building):
		return get_sprite_center().distance_to(attack_target_building.get_melee_attack_point())
	return INF


func _process_garrisoned_combat(_delta: float) -> void:
	velocity = Vector2.ZERO
	_unit_state = UnitState.IDLE
	_play_idle()


func _process_garrison_approach(_delta: float) -> void:
	var building := garrison_approach_target
	if building == null:
		_unit_state = UnitState.IDLE
		return

	var approach := building.get_entry_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance <= Building.ENTRY_RANGE:
		building.enter_garrison(self)
		return

	_follow_navigation_toward(approach, 4.0, _delta)
	distance = global_position.distance_to(approach)
	if navigation_agent.is_navigation_finished() and distance <= Building.ENTRY_RANGE * 1.5:
		building.enter_garrison(self)


func _process_construction(delta: float) -> void:
	var site := construction_target
	if site == null:
		_unit_state = UnitState.IDLE
		_notify_construction_finished()
		return

	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night is DayNightManager and not (day_night as DayNightManager).is_construction_allowed():
		velocity = Vector2.ZERO
		_play_idle()
		return

	var approach := site.get_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance > build_range:
		_follow_navigation_toward(approach, 4.0, delta)
		return

	velocity = Vector2.ZERO
	_play_build_animation()
	var work_multiplier := 1.0
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		work_multiplier = (population_manager as PopulationManager).get_civilian_work_multiplier()
	var progress_rate := (1.0 / maxf(site.build_time_total, 0.1)) * build_power * work_multiplier * delta
	var prev_progress := site.construction_progress
	site.add_construction_progress(progress_rate)
	if site.building_state != Building.BuildingState.CONSTRUCTING and prev_progress < 1.0:
		_notify_construction_finished()


func _notify_construction_finished() -> void:
	construction_target = null
	if _unit_state == UnitState.CONSTRUCTING:
		_unit_state = UnitState.IDLE
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_construction_finished(self)


func _process_repair(delta: float) -> void:
	var target := repair_target
	if target == null:
		_unit_state = UnitState.IDLE
		_notify_repair_finished()
		return

	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night is DayNightManager and not (day_night as DayNightManager).is_construction_allowed():
		velocity = Vector2.ZERO
		_play_idle()
		return

	var approach := target.get_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance > build_range:
		_follow_navigation_toward(approach, 4.0, delta)
		return

	var resource_manager := get_tree().get_first_node_in_group("resource_manager")
	if resource_manager is ResourceManager and not target.repair_paid:
		if not target.try_start_repair(resource_manager as ResourceManager):
			_notify_repair_finished()
			return

	velocity = Vector2.ZERO
	_play_build_animation()
	var work_multiplier := 1.0
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		work_multiplier = (population_manager as PopulationManager).get_civilian_work_multiplier()

	var repair_time := target.get_repair_work_duration()
	var progress_rate := (1.0 / maxf(repair_time, 0.1)) * build_power * work_multiplier * delta
	var prev_needs_repair := target.needs_repair()
	target.add_repair_progress(progress_rate)
	if prev_needs_repair and not target.needs_repair():
		_notify_repair_finished()


func _notify_repair_finished() -> void:
	repair_target = null
	if _unit_state == UnitState.REPAIRING:
		_unit_state = UnitState.IDLE
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_repair_finished(self)


func _process_gathering(delta: float) -> void:
	var node := gather_target
	if node == null or not is_instance_valid(node) or not node.has_resources():
		_finish_gather_job()
		return

	var work_pos := node.get_work_position(global_position)
	var distance := global_position.distance_to(work_pos)
	if distance > build_range:
		_follow_navigation_toward(work_pos, 4.0, delta)
		return

	velocity = Vector2.ZERO
	_play_gather_animation()
	_gather_timer += delta
	var gather_duration := GATHER_TIME_AT_NODE
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		gather_duration = (job_manager as JobManager).get_gather_duration(self)
	if _gather_timer >= gather_duration:
		_gather_timer = 0.0
		if job_manager is JobManager:
			var building: Building = (job_manager as JobManager).get_worker_building(self)
			if building != null and _is_mill_field_node(building, node):
				(job_manager as JobManager).on_unit_reached_deposit_building(self, building)
				return
			if building != null:
				assign_deposit_at_building(building)
				return
		_finish_gather_job()


func _process_depositing(delta: float) -> void:
	var building := gather_building
	if building == null or not is_instance_valid(building):
		_finish_gather_job()
		return

	var approach := building.get_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance > build_range:
		_gather_timer = 0.0
		_follow_navigation_toward(approach, 4.0, delta)
		return

	velocity = Vector2.ZERO
	_play_idle()
	if _gather_timer > 0.0:
		return
	_gather_timer = 1.0
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_unit_reached_deposit_building(self, building)


func _is_mill_field_node(building: Building, node: ResourceNode) -> bool:
	if not building.has_meta("mill_wheat_node"):
		return false
	return building.get_meta("mill_wheat_node") == node


func _process_recruitment(delta: float) -> void:
	var building := recruitment_building
	if (
		building == null
		or not is_instance_valid(building)
		or building.building_state != Building.BuildingState.ACTIVE
	):
		_release_recruitment_reservation()
		_unit_state = UnitState.IDLE
		return

	var approach := building.get_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance > build_range:
		_follow_navigation_toward(approach, 4.0, delta)
		return

	velocity = Vector2.ZERO
	var target_type := recruitment_type_id
	var squad_size := recruitment_squad_size
	var squad_id := recruitment_squad_id
	transform_to_unit_type(target_type)
	if not squad_id.is_empty():
		set_meta("squad_id", squad_id)
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("spawn_squad_members"):
		world.call("spawn_squad_members", self, target_type, maxi(0, squad_size - 1), squad_id)
	recruitment_building = null
	recruitment_type_id = ""
	recruitment_squad_size = 1
	recruitment_squad_id = ""


func _release_recruitment_reservation() -> void:
	var extra_population := maxi(0, recruitment_squad_size - 1)
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		(population_manager as PopulationManager).release_reserved_population(extra_population)
	recruitment_building = null
	recruitment_type_id = ""
	recruitment_squad_size = 1
	recruitment_squad_id = ""


func cancel_recruitment() -> void:
	if recruitment_building == null and recruitment_squad_size <= 1:
		return
	_release_recruitment_reservation()
	if _unit_state == UnitState.RECRUITING:
		_unit_state = UnitState.IDLE


func _exit_tree() -> void:
	cancel_recruitment()


func _finish_gather_job() -> void:
	gather_target = null
	gather_building = null
	_gather_timer = 0.0
	_unit_state = UnitState.IDLE
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).release_unit_job(self)
		(job_manager as JobManager).try_assign_idle_villager(self)


func _play_build_animation() -> void:
	if _is_attack_animating:
		return
	_reset_sprite_motion()
	if animated_sprite.sprite_frames.has_animation(&"idle"):
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	# Subtle hammer bounce while building
	var bounce := sin(Time.get_ticks_msec() * 0.012) * 2.0
	animated_sprite.position = Vector2(0.0, bounce)


func _play_gather_animation() -> void:
	if _is_attack_animating:
		return
	if animated_sprite.sprite_frames.has_animation(&"gather"):
		if animated_sprite.animation != &"gather":
			animated_sprite.play(&"gather")
		_reset_sprite_motion()
		return
	if animated_sprite.sprite_frames.has_animation(&"idle"):
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	var swing := sin(Time.get_ticks_msec() * 0.018)
	animated_sprite.rotation_degrees = swing * 10.0
	animated_sprite.position = Vector2(swing * 1.5, absf(swing) * 2.5)


func _reset_sprite_motion() -> void:
	animated_sprite.rotation_degrees = 0.0
	animated_sprite.position = Vector2.ZERO


func _should_stop_move_order() -> bool:
	if _unit_state != UnitState.MOVING:
		return false

	var distance_to_destination := global_position.distance_to(_move_destination)
	if distance_to_destination <= PERSONAL_SPACE_RADIUS:
		return true

	if distance_to_destination <= PERSONAL_SPACE_RADIUS * 2.25 and _is_adjacent_to_other_unit():
		return true

	if navigation_agent.is_navigation_finished():
		return distance_to_destination <= navigation_agent.target_desired_distance + 12.0

	return false


func _is_adjacent_to_other_unit() -> bool:
	var touch_distance_sq := PERSONAL_SPACE_RADIUS * PERSONAL_SPACE_RADIUS * 1.44
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not node is Unit:
			continue

		var other := node as Unit
		if other._is_dying or other.garrisoned_building != null:
			continue

		if global_position.distance_squared_to(other.global_position) <= touch_distance_sq:
			return true

	return false


func _get_effective_move_speed() -> float:
	var multiplier := 1.0
	for node in get_tree().get_nodes_in_group("slow_zones"):
		if node is TerrainObstacle:
			multiplier = minf(multiplier, node.get_slow_multiplier_at(global_position))
	if _ground_layer != null and _ground_layer.is_water_at(global_position):
		multiplier = minf(multiplier, 0.65)
	return move_speed * multiplier


func _is_in_attack_range() -> bool:
	var origin := global_position
	var weapon_stats: Dictionary = {}
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		origin = garrisoned_building.get_attack_point()
		weapon_stats = garrisoned_building.get_weapon_stats()

	if attack_target != null and is_instance_valid(attack_target):
		var dist := origin.distance_to(attack_target.get_sprite_center())
		if garrisoned_building != null:
			var range_max: float = weapon_stats.get("range_max", attack_range_max)
			return dist <= range_max
		match combat_style:
			CombatStyle.MELEE:
				return _get_melee_combat_distance() <= melee_range * 1.15
			CombatStyle.RANGED:
				return dist >= attack_range_min and dist <= attack_range_max

	if attack_target_building != null and is_instance_valid(attack_target_building):
		var building_origin := attack_target_building.get_melee_attack_point() if combat_style == CombatStyle.MELEE else attack_target_building.get_attack_point()
		var building_dist := get_sprite_center().distance_to(building_origin) if combat_style == CombatStyle.MELEE else origin.distance_to(building_origin)
		if garrisoned_building != null:
			var range_max: float = weapon_stats.get("range_max", attack_range_max)
			return building_dist <= range_max
		match combat_style:
			CombatStyle.MELEE:
				return building_dist <= melee_range * 1.35
			CombatStyle.RANGED:
				return building_dist >= attack_range_min * 0.85 and building_dist <= attack_range_max
	return false


func _get_desired_attack_distance() -> float:
	match combat_style:
		CombatStyle.RANGED:
			return (attack_range_min + attack_range_max) * 0.5
	return melee_range


func _get_chase_standoff_point() -> Vector2:
	if attack_target != null and is_instance_valid(attack_target):
		var target_pos := attack_target.get_sprite_center()
		var dir := global_position.direction_to(target_pos)
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN

		var dist := global_position.distance_to(target_pos)
		var desired := _get_desired_attack_distance()

		if combat_style == CombatStyle.RANGED:
			if dist > attack_range_max:
				desired = attack_range_max * 0.92
			elif dist < attack_range_min:
				desired = attack_range_min * 1.02
			elif _is_in_attack_range():
				return global_position

			return target_pos - dir * desired

		return target_pos

	if attack_target_building != null and is_instance_valid(attack_target_building):
		if combat_style == CombatStyle.MELEE:
			if _is_in_attack_range():
				return global_position
			return attack_target_building.get_combat_approach_point(global_position)

		var building_pos := attack_target_building.get_combat_approach_point(global_position)
		var building_dir := global_position.direction_to(building_pos)
		if building_dir == Vector2.ZERO:
			building_dir = Vector2.DOWN
		var building_dist := global_position.distance_to(building_pos)
		var building_desired := _get_desired_attack_distance()
		if building_dist > attack_range_max:
			building_desired = attack_range_max * 0.92
		elif building_dist < attack_range_min:
			building_desired = attack_range_min * 1.02
		elif _is_in_attack_range():
			return global_position
		return building_pos - building_dir * building_desired

	return global_position


func _start_attack() -> void:
	_unit_state = UnitState.ATTACKING
	_is_attack_animating = true
	_damage_dealt_this_swing = false
	velocity = Vector2.ZERO
	navigation_agent.target_position = global_position

	if garrisoned_building != null:
		_fire_garrison_attack()
		return

	_play_attack_animation(_direction_to_target())


func _direction_to_target() -> Vector2:
	if attack_target != null and is_instance_valid(attack_target):
		return global_position.direction_to(attack_target.get_sprite_center())
	if attack_target_building != null and is_instance_valid(attack_target_building):
		var aim_point := attack_target_building.get_melee_attack_point() if combat_style == CombatStyle.MELEE else attack_target_building.get_attack_point()
		return global_position.direction_to(aim_point)
	return Vector2.DOWN


func _play_attack_animation(direction: Vector2) -> void:
	_last_facing_direction = direction
	var animation_name := &"attack_down"
	if direction.y < -0.15:
		animation_name = &"attack_up"
	elif direction.y > 0.15:
		animation_name = &"attack_down"
	elif direction.x < 0.0:
		animation_name = &"attack_up" if animated_sprite.sprite_frames.has_animation(&"attack_up") else &"attack_down"
	else:
		animation_name = &"attack_down"

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		animation_name = &"attack_down" if animated_sprite.sprite_frames.has_animation(&"attack_down") else &"idle"

	animated_sprite.play(animation_name)


func _on_animation_frame_changed() -> void:
	if not _is_attack_animating:
		return

	var hit_frame := MELEE_DAMAGE_FRAME if combat_style == CombatStyle.MELEE else RANGED_DAMAGE_FRAME
	if animated_sprite.frame == hit_frame and not _damage_dealt_this_swing:
		_damage_dealt_this_swing = true
		_deal_attack()


func _fire_garrison_attack() -> void:
	_deal_attack()
	_is_attack_animating = false
	var cooldown_mult := 1.0
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		var weapon_stats: Dictionary = garrisoned_building.get_weapon_stats()
		cooldown_mult = weapon_stats.get("cooldown_mult", 1.0)
	_attack_cooldown_remaining = attack_cooldown * cooldown_mult
	_unit_state = UnitState.IDLE if garrisoned_building != null else UnitState.CHASING


func _deal_attack() -> void:
	if attack_target != null and is_instance_valid(attack_target) and attack_target.hp > 0 and not attack_target._is_dying:
		if not is_hostile_to(attack_target):
			return
		if garrisoned_building != null:
			_fire_garrison_projectile_at_unit(attack_target)
			return
		match combat_style:
			CombatStyle.MELEE:
				if _get_melee_combat_distance() <= melee_range * 1.15:
					attack_target.take_damage(get_attack_damage(), self)
			CombatStyle.RANGED:
				_spawn_arrow_at_unit(attack_target)
		return

	if attack_target_building != null and is_instance_valid(attack_target_building) and attack_target_building.can_be_damaged():
		if garrisoned_building != null:
			_fire_garrison_projectile_at_building(attack_target_building)
			return
		match combat_style:
			CombatStyle.MELEE:
				if _get_melee_combat_distance() <= melee_range * 1.35:
					attack_target_building.take_damage(get_attack_damage(), self)
			CombatStyle.RANGED:
				_spawn_arrow_at_building(attack_target_building)


func _fire_garrison_projectile_at_unit(target_unit: Unit) -> void:
	if garrisoned_building == null or target_unit == null:
		return
	var weapon_id := garrisoned_building.garrison_weapon
	if weapon_id == "stone":
		_spawn_stone_at_unit(target_unit)
	else:
		_spawn_arrow_at_unit(target_unit)


func _fire_garrison_projectile_at_building(target_building: Building) -> void:
	if garrisoned_building == null or target_building == null:
		return
	var weapon_id := garrisoned_building.garrison_weapon
	if weapon_id == "stone":
		_spawn_stone_at_building(target_building)
	else:
		_spawn_arrow_at_building(target_building)


func _spawn_stone_at_unit(target_unit: Unit) -> void:
	if target_unit == null:
		return

	var stone: Stone = STONE_SCENE.instantiate()
	var origin := get_sprite_center()
	var target_point := target_unit.get_sprite_center()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	stone.shooter = self
	stone.target = target_unit
	stone.damage = get_attack_damage()
	stone.direction = dir
	if garrisoned_building != null:
		var weapon_stats: Dictionary = garrisoned_building.get_weapon_stats()
		stone.speed = weapon_stats.get("speed", 220.0)
	var world := _get_combat_world()
	world.add_child(stone)
	stone.global_position = origin + dir * _get_projectile_spawn_offset()


func _spawn_stone_at_building(target_building: Building) -> void:
	if target_building == null:
		return

	var stone: Stone = STONE_SCENE.instantiate()
	var origin := get_sprite_center()
	var target_point := target_building.get_attack_point()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	stone.shooter = self
	stone.building_target = target_building
	stone.damage = get_attack_damage()
	stone.direction = dir
	if garrisoned_building != null:
		var weapon_stats: Dictionary = garrisoned_building.get_weapon_stats()
		stone.speed = weapon_stats.get("speed", 220.0)
	var world := _get_combat_world()
	world.add_child(stone)
	stone.global_position = origin + dir * _get_projectile_spawn_offset()


func _spawn_arrow_at_unit(target_unit: Unit) -> void:
	if target_unit == null:
		return

	var arrow_scene: PackedScene = preload("res://scenes/combat/arrow.tscn")
	var arrow: Arrow = arrow_scene.instantiate()
	var origin := get_sprite_center()
	var target_point := target_unit.get_sprite_center()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	arrow.shooter = self
	arrow.target = target_unit
	arrow.damage = get_attack_damage()
	arrow.direction = dir
	var world := _get_combat_world()
	world.add_child(arrow)
	arrow.global_position = origin + dir * _get_projectile_spawn_offset()


func _spawn_arrow_at_building(target_building: Building) -> void:
	if target_building == null:
		return

	var arrow_scene: PackedScene = preload("res://scenes/combat/arrow.tscn")
	var arrow: Arrow = arrow_scene.instantiate()
	var origin := get_sprite_center()
	var target_point := target_building.get_attack_point()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	arrow.shooter = self
	arrow.building_target = target_building
	arrow.damage = get_attack_damage()
	arrow.direction = dir
	var world := _get_combat_world()
	world.add_child(arrow)
	arrow.global_position = origin + dir * _get_projectile_spawn_offset()


func _get_projectile_spawn_offset() -> float:
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		return 36.0
	return 14.0


func _on_animation_finished() -> void:
	if _is_dying:
		_freeze_death_pose()
		return

	if not _is_attack_animating:
		return

	_is_attack_animating = false
	_attack_cooldown_remaining = attack_cooldown
	_play_idle()

	if attack_target != null and is_instance_valid(attack_target) and attack_target.hp > 0 and not attack_target._is_dying:
		_unit_state = UnitState.CHASING
	elif attack_target_building != null and is_instance_valid(attack_target_building) and attack_target_building.can_be_damaged():
		_unit_state = UnitState.CHASING
	else:
		attack_target = null
		attack_target_building = null
		_unit_state = UnitState.IDLE


func _freeze_death_pose() -> void:
	var animation_name := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return

	var last_frame := animated_sprite.sprite_frames.get_frame_count(animation_name) - 1
	animated_sprite.stop()
	animated_sprite.frame = last_frame


func _play_idle() -> void:
	if _is_attack_animating:
		return
	_reset_sprite_motion()
	if animated_sprite.animation != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")


func _play_idle_facing_target() -> void:
	if _is_attack_animating:
		return
	var direction := _direction_to_target()
	if direction != Vector2.ZERO:
		_last_facing_direction = direction
	_reset_sprite_motion()
	if animated_sprite.animation != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")


func _update_visual_separation() -> void:
	if garrisoned_building != null or _is_dying:
		return

	var nudge := Vector2.ZERO
	var separation_radius := PERSONAL_SPACE_RADIUS * 1.5
	for node in get_tree().get_nodes_in_group("units"):
		if node == self or not node is Unit:
			continue

		var other := node as Unit
		if other._is_dying or other.garrisoned_building != null:
			continue

		var offset := global_position - other.global_position
		var dist := offset.length()
		if dist >= separation_radius or dist < 0.01:
			continue
		nudge += offset.normalized() * (separation_radius - dist) * 0.25

	const MAX_NUDGE := 14.0
	if nudge.length() > MAX_NUDGE:
		nudge = nudge.normalized() * MAX_NUDGE

	animated_sprite.offset = sprite_offset + nudge


func _play_walk_animation(direction: Vector2) -> void:
	_last_facing_direction = direction
	var animation_name := &"walk_down"
	if direction.y < -0.15:
		animation_name = &"walk_up"
	elif direction.y > 0.15:
		animation_name = &"walk_down"
	elif direction.x < 0.0:
		animation_name = &"walk_up" if animated_sprite.sprite_frames.has_animation(&"walk_up") else &"walk_down"
	else:
		animation_name = &"walk_down"

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		animation_name = &"idle"

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
	_reset_sprite_motion()


func _update_terrain_feedback(_delta: float) -> void:
	_update_visual_separation()

	if _ground_layer == null:
		return

	var on_water := _ground_layer.is_water_at(global_position)
	if on_water and not _was_on_water:
		_spawn_splash()
	_was_on_water = on_water


func _spawn_splash() -> void:
	if dust_particles == null:
		return
	dust_particles.modulate = Color(0.55, 0.78, 1.0, 0.85)
	dust_particles.restart()
	dust_particles.emitting = true
