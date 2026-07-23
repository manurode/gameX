class_name Building
extends StaticBody2D

enum BuildingState { CONSTRUCTING, ACTIVE, DESTROYED }

signal health_changed(current_hp: int, max_hp: int)
signal destroyed
signal construction_completed
signal garrison_changed
signal upgraded(new_level: int, weapon_type: String)

const HEALTH_BAR_VISIBLE_MS := 4000
const DAMAGED_HP_RATIO := 0.5
## Fallback when a building has build_time 0 (e.g. town center): full-repair duration.
const DEFAULT_REPAIR_TIME := 12.0
## Never finish a repair faster than this, even for tiny damage.
const MIN_REPAIR_TIME := 2.0
const ENTRY_RANGE := 42.0
const GARRISON_ATTACK_RANGE := 260.0
const COLLISION_BODY_SHRINK := Vector2(0.84, 0.84)
const COLLISION_BODY_CENTER_Y := 0.2
const WALL_COLLISION_CENTER_Y := 0.15
const ARROW_SCENE := preload("res://scenes/combat/arrow.tscn")
const AUTO_DEFENSE_PROJECTILE_OFFSET := 36.0
const NIGHT_LIGHT_COLOR := Color(1.0, 0.82, 0.52)
const CONSTRUCTION_LIGHT_FACTOR := 0.42
## Unscaled local Y where the sprite base plants on the iso cell (see DepthSort).
const PLANT_UNSCALED := DepthSort.ISO_HALF_TILE
const WALL_PLANT_UNSCALED := DepthSort.WALL_PLANT

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
var _active_attackers: int = 0
var _definition: Dictionary = {}
var _visual_scale: float = 1.0
var _footprint := Vector2(70.0, 45.0)
var _wall_vertical: bool = false
var _repair_start_hp: int = 0
var _repair_target_hp: int = 0
var _repair_progress: float = 0.0
var _last_visual_phase: String = ""
var _night_light: PointLight2D
var _night_light_tween: Tween
var _base_light_energy: float = 0.0
var _base_light_scale: float = 1.0
var _ground_shadow: Sprite2D
## Cell-center snap; global_position is shifted south for Y-sort.
var _anchor_position := Vector2.ZERO
var _depth_ready: bool = false
var _sort_dy: float = 0.0
static var _shared_building_shadow_texture: Texture2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var damage_overlay: Sprite2D = $DamageOverlay
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var selection_indicator: Line2D = $SelectionIndicator
@onready var health_bar: Node2D = $HealthBar
@onready var progress_bar: Node2D = $ProgressBar


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("selectable_buildings")
	add_to_group("occlusion_props")
	_apply_definition()
	_update_visual_damage()
	_update_construction_visual()
	_setup_selection_indicator()
	_setup_ground_shadow()
	_setup_night_light()
	selection_indicator.visible = false
	set_process(true)
	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night != null and day_night.has_method("should_apply_night_visuals") and day_night.should_apply_night_visuals():
		apply_cycle_visuals(true, true)


func get_occlusion_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if building_state == BuildingState.DESTROYED:
		return sprites
	if sprite != null and sprite.visible and sprite.texture != null:
		sprites.append(sprite)
	return sprites


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
	_refresh_night_light_params()


func apply_cycle_visuals(is_night: bool, instant: bool = false) -> void:
	if _ground_shadow != null:
		_ground_shadow.modulate = Color(1, 1, 1, 0.65) if is_night else Color(1, 1, 1, 1)
	if _night_light == null:
		return
	if building_state == BuildingState.DESTROYED:
		_set_night_light_energy(0.0, false, instant)
		return
	_refresh_night_light_params()
	var target_energy := 0.0
	if is_night:
		target_energy = _base_light_energy
		if building_state == BuildingState.CONSTRUCTING:
			target_energy *= CONSTRUCTION_LIGHT_FACTOR
	_set_night_light_energy(target_energy, is_night and target_energy > 0.01, instant)


func _setup_night_light() -> void:
	if _night_light != null:
		return
	_night_light = PointLight2D.new()
	_night_light.name = "NightLight"
	_night_light.texture = DayNightManager.get_shared_light_texture()
	_night_light.color = NIGHT_LIGHT_COLOR
	_night_light.energy = 0.0
	_night_light.enabled = false
	# MIX keeps overlapping lights from stacking brighter than a single source.
	_night_light.blend_mode = PointLight2D.BLEND_MODE_MIX
	_night_light.shadow_enabled = false
	_night_light.z_index = -2
	_night_light.y_sort_enabled = false
	add_child(_night_light)
	_refresh_night_light_params()


func _refresh_night_light_params() -> void:
	var params := _resolve_night_light_params()
	_base_light_energy = float(params.get("energy", 2.0))
	_base_light_scale = float(params.get("scale", 2.4))
	if _night_light == null:
		return
	_night_light.texture_scale = _base_light_scale
	_night_light.position = Vector2(0.0, float(params.get("offset_y", -28.0)))


func _resolve_night_light_params() -> Dictionary:
	# Same brightness as units; only a bit more radius for settlement coverage.
	match building_type_id:
		"town_center":
			return {"energy": 1.15, "scale": 3.1, "offset_y": -46.0}
		"castle_big", "castle_small":
			return {"energy": 1.15, "scale": 2.35, "offset_y": -32.0}
		"tower":
			return {"energy": 1.15, "scale": 2.15, "offset_y": -36.0}
		"wall":
			return {"energy": 1.05, "scale": 1.75, "offset_y": -16.0}
		_:
			return {"energy": 1.15, "scale": 2.05, "offset_y": -24.0}


func _set_night_light_energy(target_energy: float, enable: bool, instant: bool = false) -> void:
	if _night_light == null:
		return
	if _night_light_tween != null and _night_light_tween.is_valid():
		_night_light_tween.kill()
		_night_light_tween = null
	if enable:
		_night_light.enabled = true
	if instant:
		_night_light.energy = target_energy
		if not enable:
			_night_light.enabled = false
		return
	_night_light_tween = create_tween()
	_night_light_tween.tween_property(_night_light, "energy", target_energy, DayNightManager.TRANSITION_SECONDS)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	if not enable:
		_night_light_tween.tween_callback(func() -> void:
			if _night_light != null and _night_light.energy <= 0.01:
				_night_light.enabled = false
		)


func is_night_light_active() -> bool:
	return (
		building_state != BuildingState.DESTROYED
		and _night_light != null
		and _night_light.enabled
		and _night_light.energy > 0.05
	)


func get_night_light_origin() -> Vector2:
	if _night_light == null:
		return global_position
	return to_global(_night_light.position)


func get_night_light_radius() -> float:
	if _night_light == null:
		return 0.0
	return DayNightManager.LIGHT_TEXTURE_SIZE * 0.5 * _night_light.texture_scale * 0.78


func set_wall_vertical(vertical: bool) -> void:
	if building_type_id != "wall":
		return
	_wall_vertical = vertical
	_apply_wall_orientation()


func is_wall_vertical() -> bool:
	return _wall_vertical


func notify_world_placed() -> void:
	# Capture cell snap before shifting south for Y-sort depth.
	if not _depth_ready:
		_anchor_position = global_position
		_depth_ready = true
	_sync_depth_from_anchor()
	# Only ACTIVE buildings carve nav; unfinished sites stay walkable.
	if building_state == BuildingState.ACTIVE and blocks_navigation:
		_request_nav_rebuild()


func place_at(world_pos: Vector2) -> void:
	_anchor_position = world_pos
	_depth_ready = true
	_sync_depth_from_anchor()


func get_anchor_position() -> Vector2:
	return _anchor_position if _depth_ready else global_position


func get_sort_y() -> float:
	return global_position.y


func _sync_depth_from_anchor() -> void:
	if not _depth_ready:
		return
	_sort_dy = DepthSort.plant_sort_dy(_plant_unscaled(), _visual_scale)
	global_position = _anchor_position + Vector2(0.0, _sort_dy)
	if sprite != null and sprite.texture != null:
		_apply_sprite_transform()
	else:
		_refresh_ground_shadow()
	_setup_collision()


func _plant_unscaled() -> float:
	if building_type_id == "wall":
		return WALL_PLANT_UNSCALED
	return PLANT_UNSCALED


func _sprite_draw_offset() -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	# Plant on the iso cell, then compensate if global_position was shifted for Y-sort.
	var base := Vector2(0.0, -sprite.texture.get_height() * 0.5 + _plant_unscaled())
	return DepthSort.compensate_draw_offset(base, _sort_dy, _visual_scale)


func _apply_sprite_transform() -> void:
	if sprite == null or sprite.texture == null:
		return
	if _depth_ready:
		_sort_dy = DepthSort.plant_sort_dy(_plant_unscaled(), _visual_scale)
		global_position = _anchor_position + Vector2(0.0, _sort_dy)
	sprite.offset = _sprite_draw_offset()
	sprite.scale = Vector2(_visual_scale, _visual_scale)
	# Selection / combat helpers use world-space offset after scale.
	sprite_offset = sprite.offset * sprite.scale
	_sync_pick_half_size_from_sprite()
	if damage_overlay != null:
		damage_overlay.offset = sprite.offset
		damage_overlay.scale = sprite.scale
	_refresh_ground_shadow()


## Click / select / command hitbox matches the scaled sprite AABB (visual footprint).
func _sync_pick_half_size_from_sprite() -> void:
	if sprite == null or sprite.texture == null:
		return
	var scaled_half := sprite.texture.get_size() * absf(_visual_scale) * 0.5
	if building_type_id == "wall":
		# Diagonal segment sits on a square canvas with lots of empty corners.
		pick_half_size = Vector2(scaled_half.x * 0.72, scaled_half.y * 0.58)
	else:
		pick_half_size = scaled_half
	if selection_indicator != null:
		_setup_selection_indicator()


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
	_visual_scale = float(_definition.get("visual_scale", 1.0))
	_footprint = _definition.get("footprint", Vector2(70.0, 45.0))
	pick_half_size = _definition.get("pick_half_size", Vector2(55.0, 50.0))
	_apply_upgrade_weapon()

	_setup_texture()
	_setup_collision()
	health_changed.emit(hp, max_hp)


func _setup_texture() -> void:
	if sprite == null:
		return

	_last_visual_phase = ""
	if building_type_id == "wall":
		_apply_wall_orientation()
	else:
		_apply_phase_texture(true)

	if sprite.texture != null:
		_apply_sprite_transform()
		sprite.modulate = _definition.get("tint", Color.WHITE)
		if damage_overlay != null:
			damage_overlay.visible = false
			damage_overlay.texture = sprite.texture
			damage_overlay.offset = sprite.offset
			damage_overlay.scale = sprite.scale


func _apply_wall_orientation() -> void:
	if building_type_id != "wall" or sprite == null:
		return
	sprite.rotation_degrees = 0.0
	sprite.position = Vector2.ZERO
	var wall_scale := float(_definition.get("visual_scale", 1.0))
	_visual_scale = wall_scale
	_footprint = WallTexture.footprint(_wall_vertical) * wall_scale
	pick_half_size = WallTexture.pick_half_size(_wall_vertical) * wall_scale
	_last_visual_phase = ""
	_apply_phase_texture(true)
	if sprite.texture != null:
		_apply_sprite_transform()
	if damage_overlay != null:
		damage_overlay.visible = false
		damage_overlay.rotation_degrees = 0.0
		damage_overlay.texture = sprite.texture
		damage_overlay.offset = sprite.offset
		damage_overlay.scale = sprite.scale
	_setup_collision()


func _resolve_visual_phase() -> String:
	if building_state == BuildingState.CONSTRUCTING:
		if construction_progress <= 0.001:
			return "plot"
		return "construction"
	if building_state == BuildingState.ACTIVE and max_hp > 0:
		if float(hp) / float(max_hp) <= DAMAGED_HP_RATIO:
			return "damaged"
	return "complete"


func _texture_path_for_phase(phase: String) -> String:
	if building_type_id == "wall":
		return WallTexture.get_texture_path(_wall_vertical, phase)
	var base_path: String = _definition.get("texture", "")
	if base_path.is_empty():
		return ""
	if phase.is_empty() or phase == "complete":
		return base_path
	return base_path.get_basename() + "_" + phase + ".png"


func _apply_phase_texture(force: bool = false) -> void:
	if sprite == null:
		return
	var phase := _resolve_visual_phase()
	if not force and phase == _last_visual_phase:
		return
	_last_visual_phase = phase

	var texture: Texture2D = null
	if building_type_id == "wall":
		texture = WallTexture.get_texture(_wall_vertical, phase)
	else:
		var path := _texture_path_for_phase(phase)
		if path.is_empty() or not ResourceLoader.exists(path):
			path = _texture_path_for_phase("complete")
		if not path.is_empty() and ResourceLoader.exists(path):
			texture = load(path)

	if texture == null:
		return

	sprite.texture = texture
	sprite.scale = Vector2(_visual_scale, _visual_scale)
	sprite.rotation_degrees = 0.0
	sprite.position = Vector2.ZERO
	_apply_sprite_transform()

	if damage_overlay != null:
		damage_overlay.visible = false
		damage_overlay.texture = texture
		damage_overlay.offset = sprite.offset
		damage_overlay.scale = sprite.scale
		damage_overlay.rotation_degrees = 0.0
		damage_overlay.position = Vector2.ZERO

	if building_state == BuildingState.ACTIVE:
		_apply_upgrade_visual()
	else:
		sprite.modulate = Color.WHITE


func _wall_base_rotation() -> float:
	return 0.0


func _setup_collision() -> void:
	if collision_shape == null:
		return
	if building_type_id == "wall":
		var shape := RectangleShape2D.new()
		shape.size = _get_collision_body_size()
		collision_shape.shape = shape
		collision_shape.position = get_collision_center() - global_position
		# Align the box with the painted iso diagonal so segments meet end-to-end.
		collision_shape.rotation = WallTexture.get_axis_direction(_wall_vertical).angle()
	else:
		# Iso diamond matching the visual ground footprint (avoids AABB corner ghosts).
		var convex := ConvexPolygonShape2D.new()
		var half := get_interaction_half_size()
		convex.points = PackedVector2Array([
			Vector2(0.0, -half.y),
			Vector2(half.x, 0.0),
			Vector2(0.0, half.y),
			Vector2(-half.x, 0.0),
		])
		collision_shape.shape = convex
		collision_shape.position = get_collision_center() - global_position
		collision_shape.rotation = 0.0
	# Unfinished buildings stay walkable; collision only once ACTIVE.
	set_collision_layer_value(1, building_state == BuildingState.ACTIVE)


func _get_collision_body_size() -> Vector2:
	if building_type_id == "wall":
		# Length along the wall axis, thickness across — continuous with neighbors.
		return Vector2(
			WallTexture.get_segment_spacing() * WallTexture.BLOCK_LENGTH_FACTOR,
			WallTexture.BLOCK_THICKNESS
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
	_prune_garrisoned_units()
	return garrisoned_units.size()


func _prune_garrisoned_units() -> void:
	var cleaned: Array[Unit] = []
	var removed := false
	for unit in garrisoned_units:
		if is_instance_valid(unit) and not unit._is_dying and unit.hp > 0:
			cleaned.append(unit)
		else:
			removed = true
	if removed:
		garrisoned_units = cleaned
		if garrisoned_units.is_empty():
			clear_garrison_attack()
		garrison_changed.emit()


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
	var nearest_distance_sq := INF
	var attack_range := get_garrison_attack_range()
	var attack_range_sq := attack_range * attack_range
	var origin := get_attack_point()
	for item in UnitSpatialIndex.query_nearby(get_tree(), origin, attack_range):
		if not item is Unit:
			continue
		var enemy := item as Unit
		if enemy._is_dying or enemy.hp <= 0:
			continue
		if not Team.are_hostile(team_id, enemy.team_id):
			continue
		var distance_sq := origin.distance_squared_to(enemy.get_sprite_center())
		if distance_sq <= attack_range_sq and distance_sq < nearest_distance_sq:
			nearest = enemy
			nearest_distance_sq = distance_sq
	if nearest == null:
		return
	_fire_automatic_defense_arrow(nearest)
	var weapon_stats := get_weapon_stats()
	_garrison_attack_cooldown = maxf(0.45, weapon_stats.get("cooldown_mult", 1.0))


func _fire_automatic_defense_arrow(target_unit: Unit) -> void:
	if target_unit == null or not is_instance_valid(target_unit):
		return
	var weapon_stats := get_weapon_stats()
	var origin := get_attack_point()
	var target_point := target_unit.get_sprite_center()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	var arrow: Arrow = ARROW_SCENE.instantiate()
	arrow.shooter_team_id = team_id
	arrow.target = target_unit
	arrow.damage = int(weapon_stats.get("damage", 14))
	arrow.speed = float(weapon_stats.get("speed", 380.0))
	arrow.direction = dir
	var world := get_parent()
	if world == null:
		world = get_tree().current_scene
	world.add_child(arrow)
	arrow.global_position = origin + dir * AUTO_DEFENSE_PROJECTILE_OFFSET


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
	if not needs_repair() and not repair_in_progress:
		return 0.0
	var missing_hp := max_hp - hp
	if repair_in_progress:
		missing_hp = maxi(1, _repair_target_hp - _repair_start_hp)
	var ratio := float(maxi(1, missing_hp)) / float(maxi(1, max_hp))
	var base_time := build_time_total if build_time_total > 0.0 else DEFAULT_REPAIR_TIME
	return maxf(base_time * ratio, MIN_REPAIR_TIME)


func get_repair_progress_ratio() -> float:
	if not repair_in_progress:
		return 1.0 if hp >= max_hp else 0.0
	return clampf(_repair_progress, 0.0, 1.0)


func try_start_repair(resource_manager: ResourceManager) -> bool:
	if not can_be_repaired() or resource_manager == null:
		return false
	if repair_paid:
		if not repair_in_progress:
			repair_in_progress = true
			_repair_start_hp = hp
			_repair_progress = 0.0
			_notify_health_bar()
			if progress_bar != null and progress_bar.has_method("refresh_from_building"):
				progress_bar.refresh_from_building()
		return true

	var full_cost := get_repair_cost()
	var cost := resource_manager.get_partial_cost(full_cost)
	if not resource_manager.has_any_cost(cost):
		return false
	if not resource_manager.spend(cost):
		return false

	var missing_hp := max_hp - hp
	var paid_fraction := resource_manager.get_affordable_fraction(full_cost)
	_repair_target_hp = hp
	if missing_hp > 0 and paid_fraction > 0.0:
		var restored_hp := int(floor(float(missing_hp) * paid_fraction))
		_repair_target_hp = mini(hp + maxi(1, restored_hp), max_hp)
	else:
		_repair_target_hp = max_hp

	repair_paid = true
	repair_in_progress = true
	_repair_start_hp = hp
	_repair_progress = 0.0
	_notify_health_bar()
	if progress_bar != null and progress_bar.has_method("refresh_from_building"):
		progress_bar.refresh_from_building()
	return true


func add_repair_progress(amount: float) -> void:
	if not repair_in_progress or not needs_repair():
		return

	var repairable_hp := _repair_target_hp - _repair_start_hp
	if repairable_hp <= 0:
		_complete_repair()
		return

	# Gradual HP fill (same idea as construction work), never jump to full in one tick.
	_repair_progress = clampf(_repair_progress + minf(amount, 0.2), 0.0, 1.0)
	hp = _repair_start_hp + int(floor(_repair_progress * float(repairable_hp)))
	hp = mini(hp, _repair_target_hp)
	# Only snap to target when work is actually done (avoids 1-HP instant completes).
	if _repair_progress >= 1.0:
		hp = _repair_target_hp
	health_changed.emit(hp, max_hp)
	_update_visual_damage()
	if progress_bar != null and progress_bar.has_method("refresh_from_building"):
		progress_bar.refresh_from_building()

	if _repair_progress >= 1.0:
		_complete_repair()


func _complete_repair() -> void:
	hp = _repair_target_hp if _repair_target_hp > 0 else max_hp
	repair_in_progress = false
	repair_paid = false
	_repair_start_hp = 0
	_repair_target_hp = 0
	_repair_progress = 0.0
	health_changed.emit(hp, max_hp)
	_update_visual_damage()
	_notify_health_bar()
	if progress_bar != null and progress_bar.has_method("refresh_from_building"):
		progress_bar.refresh_from_building()


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
	var origin := get_anchor_position()
	if building_type_id == "wall":
		return origin + Vector2(0.0, -_footprint.y * WALL_COLLISION_CENTER_Y)
	return get_interaction_center()


func get_collision_half_size() -> Vector2:
	if building_type_id == "wall":
		return _get_collision_body_size() * 0.5
	return get_interaction_half_size()


func get_interaction_center() -> Vector2:
	var center_y := WALL_COLLISION_CENTER_Y if building_type_id == "wall" else 0.2
	return get_anchor_position() + Vector2(0.0, -_footprint.y * center_y)


func get_interaction_half_size() -> Vector2:
	if building_type_id == "wall":
		# Axis-aligned bounds that cover the oriented block (used for approach points).
		return Vector2(
			WallTexture.get_block_half_length(),
			WallTexture.get_block_half_thickness()
		)
	return _footprint * 0.42


func get_closest_surface_point(from_position: Vector2) -> Vector2:
	var center := get_interaction_center()
	var half := get_interaction_half_size()
	var local := from_position - center
	var clamped := Vector2(
		clampf(local.x, -half.x, half.x),
		clampf(local.y, -half.y, half.y)
	)
	if clamped.distance_squared_to(local) < 0.01:
		var pen_x := half.x - absf(local.x)
		var pen_y := half.y - absf(local.y)
		if pen_x < pen_y:
			clamped.x = half.x if local.x >= 0.0 else -half.x
		else:
			clamped.y = half.y if local.y >= 0.0 else -half.y
	return center + clamped


func get_approach_point(from_position: Vector2, margin: float = 2.0) -> Vector2:
	var center := get_interaction_center()
	var surface := get_closest_surface_point(from_position)
	var outward := surface - center
	if outward.length_squared() < 0.01:
		outward = from_position - center
	if outward == Vector2.ZERO:
		outward = Vector2.DOWN
	return surface + outward.normalized() * margin


func get_combat_approach_point(from_position: Vector2) -> Vector2:
	return get_approach_point(from_position, 0.0)


func get_entry_approach_point(from_position: Vector2) -> Vector2:
	return get_approach_point(from_position, 2.0)


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
	# After depth shift, node origin is the planted base.
	selection_indicator.position = Vector2.ZERO
	selection_indicator.y_sort_enabled = false


func _setup_ground_shadow() -> void:
	if _ground_shadow != null:
		return
	if _shared_building_shadow_texture == null:
		var image := Image.create(64, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		for y in 24:
			for x in 64:
				var dx := (x - 32.0) / 32.0
				var dy := (y - 12.0) / 12.0
				var dist := dx * dx + dy * dy
				if dist <= 1.0:
					var alpha := 0.22 * (1.0 - dist) * (1.0 - dist)
					image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
		_shared_building_shadow_texture = ImageTexture.create_from_image(image)
	_ground_shadow = Sprite2D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.texture = _shared_building_shadow_texture
	_ground_shadow.z_index = -1
	_ground_shadow.y_sort_enabled = false
	_ground_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_ground_shadow)
	move_child(_ground_shadow, 0)
	_refresh_ground_shadow()


func _refresh_ground_shadow() -> void:
	if _ground_shadow == null:
		return
	# Node origin is the planted base after depth sync.
	_ground_shadow.position = Vector2.ZERO
	var radius_x := maxf(_footprint.x * 0.034, 1.15)
	var radius_y := maxf(_footprint.y * 0.028, 0.75)
	if building_type_id == "wall":
		radius_x = maxf(_footprint.x * 0.028, 0.9)
		radius_y = maxf(_footprint.y * 0.022, 0.55)
	_ground_shadow.scale = Vector2(radius_x, radius_y)
	_ground_shadow.visible = building_state != BuildingState.DESTROYED
	if selection_indicator != null:
		selection_indicator.position = Vector2.ZERO


func get_sprite_center() -> Vector2:
	return global_position + sprite_offset


func get_footprint() -> Vector2:
	return _footprint


func get_base_center() -> Vector2:
	return get_anchor_position() + Vector2(0.0, -_footprint.y * 0.2)


func get_melee_attack_point(from_position: Vector2 = Vector2.INF) -> Vector2:
	if from_position == Vector2.INF:
		return get_base_center()
	return get_closest_surface_point(from_position)


func get_attack_point() -> Vector2:
	return get_sprite_center()


func get_selection_rect() -> Rect2:
	return Rect2(get_sprite_center() - pick_half_size, pick_half_size * 2.0)


func contains_world_point(world_point: Vector2) -> bool:
	return get_selection_rect().has_point(world_point)


func contains_command_point(world_point: Vector2) -> bool:
	# Same area as selection so right-click commands (attack/repair) hit the sprite.
	return contains_world_point(world_point)


func should_show_health_bar() -> bool:
	if building_state == BuildingState.DESTROYED or hp <= 0:
		return false
	# Construction/repair already show ProgressBar; HP stays flat during build.
	if building_state == BuildingState.CONSTRUCTING or repair_in_progress:
		return false
	if is_selected:
		return true
	if is_being_attacked():
		return true
	return Time.get_ticks_msec() - _last_damage_time < HEALTH_BAR_VISIBLE_MS


func is_being_attacked() -> bool:
	return _active_attackers > 0


func register_attacker(_attacker: Unit) -> void:
	_active_attackers += 1
	_notify_health_bar()


func unregister_attacker(_attacker: Unit) -> void:
	_active_attackers = maxi(0, _active_attackers - 1)
	_notify_health_bar()


func _notify_health_bar() -> void:
	if health_bar != null and health_bar.has_method("notify_selection_changed"):
		health_bar.notify_selection_changed()


func select() -> void:
	is_selected = true
	if selection_indicator != null:
		selection_indicator.visible = true
	_notify_health_bar()


func deselect() -> void:
	is_selected = false
	if selection_indicator != null:
		selection_indicator.visible = false
	_notify_health_bar()


func get_garrison_space() -> int:
	return maxi(0, garrison_capacity - get_garrison_count())


func get_entry_range() -> float:
	return maxf(ENTRY_RANGE, maxf(pick_half_size.x, pick_half_size.y) * 0.55)


func can_accept_garrison_approach(unit: Unit) -> bool:
	# Only civilians (curfew shelter). No manual military garrison.
	return (
		building_state == BuildingState.ACTIVE
		and can_garrison
		and unit != null
		and is_instance_valid(unit)
		and not unit._is_dying
		and unit.hp > 0
		and unit.is_civilian
	)


func can_enter_garrison(unit: Unit) -> bool:
	return (
		can_accept_garrison_approach(unit)
		and get_garrison_space() > 0
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
	var selection_manager := get_node_or_null("/root/Main/Layout/WorldView/SubViewport/GameWorld/SelectionManager")
	if selection_manager != null and selection_manager.has_method("select_building"):
		selection_manager.select_building(self)


func exit_garrison(unit: Unit, exit_position: Variant = null) -> void:
	if not garrisoned_units.has(unit):
		return
	garrisoned_units.erase(unit)
	# Dying units only need list cleanup — don't respawn them at the exit point.
	if is_instance_valid(unit) and not unit._is_dying:
		var pos: Vector2 = exit_position if exit_position is Vector2 else _find_exit_position()
		unit.on_exited_garrison(pos)
	garrison_changed.emit()
	if garrisoned_units.is_empty():
		clear_garrison_attack()


func exit_garrison_units(units: Array) -> void:
	_prune_garrisoned_units()
	var to_exit: Array[Unit] = []
	for unit in units:
		# is_instance_valid must come before `is` — freed instances crash on `is`.
		if not is_instance_valid(unit):
			continue
		if unit is Unit and garrisoned_units.has(unit):
			to_exit.append(unit)
	if to_exit.is_empty():
		return
	var positions := _get_exit_positions(to_exit.size())
	for i in to_exit.size():
		exit_garrison(to_exit[i], positions[i])


func exit_all_garrison() -> void:
	exit_garrison_units(garrisoned_units.duplicate())


## Public spawn/exit point at the building footprint edge (same as garrison exit).
## Picks a free slot around the building so successive spawns do not stack.
func get_exit_position() -> Vector2:
	return _find_exit_position()


## Several free spawn/exit points around the building (no overlap between them).
func get_exit_positions(count: int) -> Array[Vector2]:
	return _get_exit_positions(count)


func _get_exit_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for _i in count:
		positions.append(_find_exit_position(positions))
	return positions


func _find_exit_position(reserved: Array[Vector2] = []) -> Vector2:
	var center := get_base_center()
	var spacing := Unit.PERSONAL_SPACE_RADIUS * 2.0
	var search_radius := maxf(_footprint.x, _footprint.y) + spacing * 6.0
	var nearby := _get_nearby_unit_positions(center, search_radius)

	# Prefer the open plaza in front of the building (+Y = screen bottom) so
	# tall sprites do not cover freshly spawned / ungarrisoned units.
	var front := _find_front_plaza_exit(reserved, nearby, spacing)
	if front != Vector2.INF:
		return front

	# Fallback rings: try the front half (+Y) first, then the back half.
	var base_radius := maxf(_footprint.x, _footprint.y) * 0.85
	for prefer_front in [true, false]:
		for ring in 8:
			var ring_radius := base_radius + float(ring) * spacing * 0.9
			var ring_capacity := maxi(6, int(TAU * ring_radius / spacing))
			var angle_offset := float(ring) * (PI / float(ring_capacity) * 0.5)
			for i in ring_capacity:
				var angle := angle_offset + TAU * float(i) / float(ring_capacity)
				var goes_front := sin(angle) >= 0.0
				if goes_front != prefer_front:
					continue
				var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
				if _is_spawn_slot_free(candidate, nearby, reserved):
					return candidate

	# Walkable fallback if every slot is blocked by units/obstacles.
	var clearance := _get_front_spawn_clearance()
	var offsets: Array[Vector2] = [
		Vector2(0.0, clearance),
		Vector2(_footprint.x * 0.45, clearance * 0.9),
		Vector2(-_footprint.x * 0.45, clearance * 0.9),
		Vector2(_footprint.x * 0.8, 0.0),
		Vector2(-_footprint.x * 0.8, 0.0),
		Vector2(0.0, -_footprint.y * 0.6),
	]
	for offset in offsets:
		var candidate := get_anchor_position() + offset
		if _is_position_walkable(candidate):
			return candidate
	return get_anchor_position() + Vector2(0.0, clearance)


## Distance south of the plant so spawned units clear courtyard walls / tall sprites.
func _get_front_spawn_clearance() -> float:
	var custom := float(_definition.get("spawn_front_offset", 0.0))
	if custom > 0.0:
		return custom
	return _footprint.y * 0.95


## Grid of free slots in the courtyard / grass strip south of the footprint.
func _find_front_plaza_exit(
	reserved: Array[Vector2],
	nearby: Array[Vector2],
	spacing: float
) -> Vector2:
	# Start well below the courtyard wall/stairs so the building sprite never covers units.
	var origin := get_anchor_position() + Vector2(0.0, _get_front_spawn_clearance())
	var half_span := _footprint.x * 0.55
	for row in 8:
		var y := origin.y + float(row) * spacing * 0.9
		var cols := maxi(5, int(half_span * 2.0 / spacing) + 1 + row)
		for i in cols:
			# Center-out left/right so successive spawns fan across the plaza.
			var signed_col := 0
			if i > 0:
				signed_col = (i + 1) / 2 if (i % 2) == 1 else -i / 2
			var x := origin.x + float(signed_col) * spacing
			var max_x := half_span + float(row) * spacing * 0.3
			if absf(x - origin.x) > max_x:
				continue
			var candidate := Vector2(x, y)
			if _is_spawn_slot_free(candidate, nearby, reserved):
				return candidate
	return Vector2.INF


func _get_nearby_unit_positions(center: Vector2, radius: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not is_inside_tree():
		return result
	var radius_sq := radius * radius
	for item in UnitSpatialIndex.query_nearby(get_tree(), center, radius):
		if not item is Unit:
			continue
		var unit := item as Unit
		if not is_instance_valid(unit) or unit._is_dying or unit.hp <= 0:
			continue
		if unit.garrisoned_building != null:
			continue
		if center.distance_squared_to(unit.global_position) <= radius_sq:
			result.append(unit.global_position)
	return result


func _is_spawn_slot_free(
	world_pos: Vector2,
	nearby_units: Array[Vector2],
	reserved: Array[Vector2]
) -> bool:
	if not _is_position_walkable(world_pos):
		return false
	var min_dist_sq := Unit.PERSONAL_SPACE_RADIUS * Unit.PERSONAL_SPACE_RADIUS
	for pos in nearby_units:
		if world_pos.distance_squared_to(pos) < min_dist_sq:
			return false
	for pos in reserved:
		if world_pos.distance_squared_to(pos) < min_dist_sq:
			return false
	return true


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
	var prev_progress := construction_progress
	construction_progress = clampf(construction_progress + amount, 0.0, 1.0)
	var crossed_work_start := prev_progress <= 0.001 and construction_progress > 0.001
	if crossed_work_start or construction_progress >= 1.0:
		_update_construction_visual()
	elif progress_bar != null and progress_bar.has_method("refresh_from_building"):
		progress_bar.refresh_from_building()
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
	var day_night := get_tree().get_first_node_in_group("day_night_manager")
	if day_night != null and day_night.has_method("should_apply_night_visuals") and day_night.should_apply_night_visuals():
		apply_cycle_visuals(true, true)


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


func take_damage(amount: int, attacker = null) -> void:
	# Untyped: projectiles may still hold a freed shooter ref; typed Unit args reject those.
	var source: Unit = null
	if is_instance_valid(attacker) and attacker is Unit:
		source = attacker as Unit
	if not can_be_damaged():
		return
	if source != null:
		if not Team.are_hostile(team_id, source.team_id):
			return
		if source.garrisoned_building == self:
			return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_update_visual_damage()
	_play_hit_effect(source)
	_try_garrison_self_defense(source)
	if source is EnemyUnit:
		(source as EnemyUnit).notify_building_hit(self)

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
	_apply_phase_texture()


func _update_construction_visual() -> void:
	if progress_bar != null and progress_bar.has_method("refresh_from_building"):
		progress_bar.refresh_from_building()
	elif progress_bar != null:
		progress_bar.visible = building_state == BuildingState.CONSTRUCTING
		progress_bar.queue_redraw()
	_apply_phase_texture()


func get_nav_block_outline() -> PackedVector2Array:
	if not blocks_navigation or building_state == BuildingState.DESTROYED:
		return PackedVector2Array()
	# Unfinished buildings are fully walkable (nav + physics) until construction completes.
	if building_state != BuildingState.ACTIVE:
		return PackedVector2Array()

	if building_type_id == "wall":
		return WallTexture.get_block_outline(get_collision_center(), _wall_vertical)

	var center := get_interaction_center()
	var half := get_interaction_half_size()
	return PackedVector2Array([
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
		center + Vector2(-half.x, 0.0),
	])


func _destroy() -> void:
	building_state = BuildingState.DESTROYED
	_active_attackers = 0
	apply_cycle_visuals(false, true)
	var job_manager := get_tree().get_first_node_in_group("job_manager")
	if job_manager is JobManager:
		(job_manager as JobManager).on_building_destroyed(self)
	var production_manager := get_tree().get_first_node_in_group("production_manager")
	if production_manager is ProductionManager:
		(production_manager as ProductionManager).unregister_producer(self)
	var population_manager := get_tree().get_first_node_in_group("population_manager")
	if population_manager is PopulationManager:
		(population_manager as PopulationManager).recalculate_cap_from_buildings()
	# During curfew, evacuate civilians and send them to the nearest other shelter
	# instead of killing them. Enemies can still kill them while they travel.
	var units_inside := garrisoned_units.duplicate()
	var curfew := get_tree().get_first_node_in_group("curfew_manager")
	var evacuate_for_curfew := (
		curfew is CurfewManager
		and (curfew as CurfewManager).is_active
		and not units_inside.is_empty()
	)
	if evacuate_for_curfew:
		exit_all_garrison()
		for unit in units_inside:
			if is_instance_valid(unit):
				(curfew as CurfewManager).send_villager_to_shelter(unit)
	else:
		garrisoned_units.clear()
		for unit in units_inside:
			if is_instance_valid(unit):
				unit.die_from_garrison_destruction()

	deselect()
	if health_bar != null:
		health_bar.visible = false
	if progress_bar != null:
		progress_bar.visible = false
	if selection_indicator != null:
		selection_indicator.visible = false

	# Capture destruction VFX from the live sprite, then hide it instantly (no fade).
	CombatEffects.spawn_building_destruction(get_parent(), self)
	if sprite != null:
		sprite.visible = false
	if damage_overlay != null:
		damage_overlay.visible = false
	if _ground_shadow != null:
		_ground_shadow.visible = false

	destroyed.emit()
	_request_nav_rebuild()
	queue_free()


func _request_nav_rebuild() -> void:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("rebuild_navigation"):
		world.call_deferred("rebuild_navigation", self)
