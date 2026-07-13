class_name Unit
extends CharacterBody2D

enum CombatStyle { MELEE, RANGED }
enum UnitState { IDLE, MOVING, CHASING, ATTACKING, CONSTRUCTING, GARRISON_APPROACH, DYING }
enum FormationType { COLUMN, LINE, WEDGE, DIAMOND }

signal health_changed(current_hp: int, max_hp: int)
signal died

const HEALTH_BAR_VISIBLE_MS := 3000
const PERSONAL_SPACE_RADIUS := 28.0
const NAV_AGENT_RADIUS := 16.0
const STUCK_TIME_SECONDS := 0.4
const STUCK_MOVE_EPSILON_SQ := 2.0
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
@export var death_up_sheet: Texture2D
@export var death_down_sheet: Texture2D
@export var sprite_offset := Vector2(0.0, -36.0)
@export var combat_style: CombatStyle = CombatStyle.MELEE
@export var can_attack: bool = true
@export var can_build: bool = false
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

var _ground_layer: TinyTilesMap
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
		DEATH_FRAME_COUNT if death_up_sheet != null or death_down_sheet != null else -1
	)
	if frames.get_animation_names().is_empty():
		return
	animated_sprite.sprite_frames = frames
	animated_sprite.play(&"idle")


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
	return get_selection_rect().has_point(world_point)


func intersects_world_rect(world_rect: Rect2) -> bool:
	return world_rect.intersects(get_selection_rect(), true)


func move_to(target: Vector2) -> void:
	if garrisoned_building != null:
		exit_garrison()
	attack_target = null
	attack_target_building = null
	construction_target = null
	_unit_state = UnitState.MOVING
	_is_attack_animating = false
	_move_destination = target
	_reset_stuck_tracking()
	_nav_repath_attempts = 0
	navigation_agent.target_desired_distance = PERSONAL_SPACE_RADIUS * 0.85
	navigation_agent.target_position = target


func attack_target_unit(target: Unit) -> void:
	if not can_attack or target == self or not is_instance_valid(target) or target.hp <= 0 or target._is_dying:
		if not garrisoned_building:
			move_to(target.global_position if is_instance_valid(target) else global_position)
		return

	garrison_approach_target = null
	attack_target_building = null
	construction_target = null
	attack_target = target
	_unit_state = UnitState.CHASING if garrisoned_building == null else UnitState.IDLE
	_is_attack_animating = false
	_reset_stuck_tracking()
	_nav_repath_attempts = 0


func attack_target_building_node(target: Building) -> void:
	if not can_attack or not is_instance_valid(target) or not target.can_be_damaged():
		if garrisoned_building == null and is_instance_valid(target):
			move_to(target.global_position)
		return

	garrison_approach_target = null
	attack_target = null
	construction_target = null
	attack_target_building = target
	_unit_state = UnitState.CHASING if garrisoned_building == null else UnitState.IDLE
	_is_attack_animating = false
	_reset_stuck_tracking()
	_nav_repath_attempts = 0


func approach_garrison(building: Building) -> void:
	if not can_attack or not is_instance_valid(building) or not building.can_enter_garrison(self):
		return
	if garrisoned_building != null:
		return

	attack_target = null
	attack_target_building = null
	construction_target = null
	garrison_approach_target = building
	_unit_state = UnitState.GARRISON_APPROACH
	_is_attack_animating = false
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = building.get_entry_approach_point(global_position)


func assign_construction(site: Building) -> void:
	if not can_build or not is_instance_valid(site) or site.building_state != Building.BuildingState.CONSTRUCTING:
		return
	if garrisoned_building != null:
		exit_garrison()
	attack_target = null
	attack_target_building = null
	construction_target = site
	_unit_state = UnitState.CONSTRUCTING
	_is_attack_animating = false
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = site.get_approach_point(global_position)


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
	attack_target = null
	attack_target_building = null
	construction_target = null
	_unit_state = UnitState.IDLE
	_is_attack_animating = false
	velocity = Vector2.ZERO
	global_position = building.global_position
	navigation_agent.target_position = global_position
	animated_sprite.visible = false
	shadow_sprite.visible = false
	set_collision_layer_value(2, false)
	if is_selected:
		selection_indicator.visible = true
	else:
		selection_indicator.visible = false


func on_exited_garrison(exit_position: Vector2) -> void:
	garrisoned_building = null
	garrison_approach_target = null
	global_position = exit_position
	navigation_agent.target_position = exit_position
	animated_sprite.visible = true
	shadow_sprite.visible = true
	set_collision_layer_value(2, true)
	if is_selected:
		selection_indicator.visible = true
	_unit_state = UnitState.IDLE
	_play_idle()


func die_from_garrison_destruction() -> void:
	garrisoned_building = null
	_die()


func get_attack_damage() -> int:
	var base := attack_damage
	if garrisoned_building != null and is_instance_valid(garrisoned_building):
		var weapon_stats: Dictionary = garrisoned_building.get_weapon_stats()
		base = weapon_stats.get("damage", attack_damage)
		return int(round(float(base) * garrisoned_building.garrison_attack_multiplier))
	return attack_damage


func take_damage(amount: int, attacker: Unit = null) -> void:
	if _is_dying or hp <= 0:
		return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_play_hit_reaction(attacker)

	if hp <= 0:
		_die()


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

	if _unit_state == UnitState.CONSTRUCTING and construction_target != null:
		_process_construction(delta)
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
		return

	if _unit_state != UnitState.MOVING:
		velocity = Vector2.ZERO
		_play_idle()
		_update_terrain_feedback(delta)
		return

	_unit_state = UnitState.MOVING
	_follow_navigation_toward(_move_destination, PERSONAL_SPACE_RADIUS * 0.85, delta)
	_update_terrain_feedback(delta)


func _reset_stuck_tracking() -> void:
	_stuck_timer = 0.0
	_stuck_check_position = global_position


func _is_stuck_moving(delta: float) -> bool:
	if global_position.distance_squared_to(_stuck_check_position) > STUCK_MOVE_EPSILON_SQ:
		_reset_stuck_tracking()
		return false

	_stuck_timer += delta
	return _stuck_timer >= STUCK_TIME_SECONDS


func _force_navigation_repath(target: Vector2) -> void:
	_nav_repath_attempts += 1
	_reset_stuck_tracking()
	var map_rid := navigation_agent.get_navigation_map()
	if map_rid.is_valid():
		var reachable := NavigationServer2D.map_get_closest_point(map_rid, target)
		navigation_agent.target_position = reachable
	navigation_agent.target_position = target


func _follow_navigation_toward(target: Vector2, desired_distance: float, delta: float) -> void:
	var remaining := global_position.distance_to(target)
	if remaining <= desired_distance:
		velocity = Vector2.ZERO
		_reset_stuck_tracking()
		_play_idle()
		return

	navigation_agent.target_desired_distance = desired_distance
	if navigation_agent.target_position.distance_squared_to(target) > 4.0:
		navigation_agent.target_position = target

	var direction := _get_navigation_direction(target)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		_play_idle()
		return

	var before := global_position
	velocity = direction * _get_effective_move_speed()
	move_and_slide()

	if global_position.distance_squared_to(before) >= STUCK_MOVE_EPSILON_SQ:
		_reset_stuck_tracking()
		_play_walk_animation(direction)
	elif _is_stuck_moving(delta):
		_force_navigation_repath(target)
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


func _chase_melee_unit_direct(_delta: float) -> void:
	var target_point := attack_target.get_sprite_center()
	var direction := global_position.direction_to(target_point)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		_play_idle()
		return

	velocity = direction * _get_effective_move_speed()
	move_and_slide()
	_play_walk_animation(direction)


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


func _process_garrisoned_combat(delta: float) -> void:
	velocity = Vector2.ZERO
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	if attack_target != null and (not is_instance_valid(attack_target) or attack_target.hp <= 0 or attack_target._is_dying):
		attack_target = null
	if attack_target_building != null and (
		not is_instance_valid(attack_target_building)
		or not attack_target_building.can_be_damaged()
	):
		attack_target_building = null

	if attack_target == null and attack_target_building == null:
		_unit_state = UnitState.IDLE
		_play_idle()
		return

	if _is_in_attack_range() and _attack_cooldown_remaining <= 0.0:
		_start_attack()
		return

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
		return

	var approach := site.get_approach_point(global_position)
	var distance := global_position.distance_to(approach)
	if distance > build_range:
		_follow_navigation_toward(approach, 4.0, delta)
		return

	velocity = Vector2.ZERO
	_play_build_animation()
	var progress_rate := (1.0 / maxf(site.build_time_total, 0.1)) * build_power * delta
	site.add_construction_progress(progress_rate)


func _play_build_animation() -> void:
	if _is_attack_animating:
		return
	if animated_sprite.sprite_frames.has_animation(&"idle"):
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	# Subtle hammer bounce while building
	var bounce := sin(Time.get_ticks_msec() * 0.012) * 2.0
	animated_sprite.position = Vector2(0.0, bounce)


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
	var world := get_parent().get_parent()
	world.add_child(stone)
	stone.global_position = origin + dir * 14.0


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
	var world := get_parent().get_parent()
	world.add_child(stone)
	stone.global_position = origin + dir * 14.0


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
	var world := get_parent().get_parent()
	world.add_child(arrow)
	arrow.global_position = origin + dir * 12.0


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
	var world := get_parent().get_parent()
	world.add_child(arrow)
	arrow.global_position = origin + dir * 12.0


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
	animated_sprite.position = Vector2.ZERO
	if animated_sprite.animation != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")


func _play_idle_facing_target() -> void:
	if _is_attack_animating:
		return
	var direction := _direction_to_target()
	if direction != Vector2.ZERO:
		_last_facing_direction = direction
	animated_sprite.position = Vector2.ZERO
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
