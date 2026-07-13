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
var can_garrison: bool = true
var blocks_navigation: bool = true
var pick_half_size := Vector2(55.0, 50.0)
var sprite_offset := Vector2(0.0, -40.0)
var is_selected: bool = false

var garrisoned_units: Array[Unit] = []
var _last_damage_time: int = 0
var _definition: Dictionary = {}
var _footprint := Vector2(70.0, 45.0)

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


func configure(type_id: String, state: BuildingState = BuildingState.ACTIVE, progress: float = 1.0) -> void:
	building_type_id = type_id
	building_state = state
	construction_progress = progress
	_apply_definition()
	_update_visual_damage()
	_update_construction_visual()


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
		sprite.texture = _create_wall_texture()
	else:
		var texture_path: String = _definition.get("texture", "")
		if not texture_path.is_empty():
			sprite.texture = load(texture_path)

	if sprite.texture != null:
		sprite.offset = Vector2(0.0, -sprite.texture.get_height() * 0.5 + 64.0)
		sprite_offset = sprite.offset
		if damage_overlay != null:
			damage_overlay.texture = sprite.texture
			damage_overlay.offset = sprite.offset


func _create_wall_texture() -> Texture2D:
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 128:
			var noise := sin(float(x) * 0.35) * 0.08 + cos(float(y) * 0.5) * 0.06
			var base := 0.42 + noise
			var alpha := 1.0
			if y < 6 or y > 57:
				base *= 0.75
			image.set_pixel(x, y, Color(base * 0.55, base * 0.52, base * 0.48, alpha))
	return ImageTexture.create_from_image(image)


func _setup_collision() -> void:
	if collision_shape == null:
		return
	var shape := RectangleShape2D.new()
	shape.size = _footprint
	collision_shape.shape = shape
	collision_shape.position = Vector2(0.0, -_footprint.y * 0.25)
	# Under construction: no physical collision so builders can reach the site
	set_collision_layer_value(1, building_state == BuildingState.ACTIVE)


func _apply_upgrade_weapon() -> void:
	var path: Array = BuildingDatabase.get_upgrade_path(building_type_id)
	if upgrade_level < path.size():
		var tier: Dictionary = path[upgrade_level]
		garrison_weapon = tier.get("weapon", garrison_weapon)


func get_weapon_stats() -> Dictionary:
	return BuildingDatabase.get_weapon_stats(garrison_weapon)


func is_garrison_occupied() -> bool:
	return garrisoned_units.size() > 0


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


func get_approach_point(from_position: Vector2, margin: float = 12.0) -> Vector2:
	var center := get_base_center()
	var direction := from_position.direction_to(center)
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	var half := _footprint * 0.55
	var reach := maxf(half.x, half.y) + margin
	return center - direction * reach


func get_combat_approach_point(from_position: Vector2) -> Vector2:
	# Just outside the nav block so melee units can reach the perimeter from any side.
	return get_approach_point(from_position, 4.0)


func get_entry_approach_point(from_position: Vector2) -> Vector2:
	return get_approach_point(from_position, 8.0)


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
		and unit.can_attack
		and not garrisoned_units.has(unit)
	)


func enter_garrison(unit: Unit) -> bool:
	if not can_enter_garrison(unit):
		return false
	garrisoned_units.append(unit)
	unit.on_entered_garrison(self)
	garrison_changed.emit()
	return true


func exit_garrison(unit: Unit) -> void:
	if not garrisoned_units.has(unit):
		return
	garrisoned_units.erase(unit)
	unit.on_exited_garrison(_find_exit_position())
	garrison_changed.emit()


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


func _complete_construction() -> void:
	building_state = BuildingState.ACTIVE
	hp = max_hp
	construction_progress = 1.0
	_setup_collision()
	_update_construction_visual()
	_update_visual_damage()
	health_changed.emit(hp, max_hp)
	construction_completed.emit()
	_request_nav_rebuild()


func take_damage(amount: int, attacker: Unit = null) -> void:
	if not can_be_damaged():
		return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_update_visual_damage()
	_play_hit_effect(attacker)

	if hp <= 0:
		_destroy()


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
	sprite.rotation_degrees = lerpf(-3.0, 0.0, ratio)


func get_nav_block_outline() -> PackedVector2Array:
	if not blocks_navigation or building_state != BuildingState.ACTIVE:
		return PackedVector2Array()

	var half := _footprint * 0.55
	var center := global_position + Vector2(0.0, -_footprint.y * 0.2)
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y * 0.5),
		center + Vector2(half.x, -half.y * 0.5),
		center + Vector2(half.x, half.y * 0.5),
		center + Vector2(-half.x, half.y * 0.5),
	])


func _destroy() -> void:
	building_state = BuildingState.DESTROYED
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
		world.call_deferred("rebuild_navigation")
